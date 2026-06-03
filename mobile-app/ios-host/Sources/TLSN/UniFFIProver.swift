// Item ⑧ — the REAL prover. Guarded by `#if canImport(TlsnProver)` so this file
// is a NO-OP until the xcframework from test-kit/setup/01-xcframework-build.md is
// added to the target. Then: set `Config.useMockProver = false` and it activates
// automatically (see `Prover.make()`). Module/symbol names follow setup/01
// (`TlsnProver`); if your bindgen emits a different module name, change the
// `canImport(...)`/`import` below to match.
#if canImport(TlsnProver)
import Foundation
import TlsnProver

@MainActor
final class UniFFIProver: TLSNProving {
    private static let initOnce: Void = { try? initialize() }()

    func prove(request: TLSNRequest,
               mode: ProverMode,
               onProgress: @escaping (NotarizeStage, Double, String) -> Void) async throws -> ProvedFact {
        _ = UniFFIProver.initOnce

        let req = HttpRequest(
            url: request.url,
            method: request.method,
            headers: request.headers.map { HttpHeader(name: $0.key, value: $0.value) },
            body: request.body
        )

        // Redaction map (GitHub hero, mirrors targets/github.md):
        //  • reveal request start-line + body (the GraphQL query),
        //  • DO NOT reveal request headers ⇒ `Authorization: Bearer …` redacted,
        //  • reveal response start-line + `date` + the two JSON fields.
        func p(_ path: String) -> HandlerParams {
            HandlerParams(key: nil, hideKey: nil, hideValue: nil,
                          contentType: "json", path: path, regex: nil, flags: nil)
        }
        let handlers: [Handler] = [
            Handler(handlerType: .sent, part: .startLine, action: .reveal, params: nil),
            Handler(handlerType: .sent, part: .body, action: .reveal, params: nil),
            Handler(handlerType: .recv, part: .startLine, action: .reveal, params: nil),
            Handler(handlerType: .recv, part: .headers, action: .reveal,
                    params: HandlerParams(key: "date", hideKey: nil, hideValue: nil,
                                          contentType: nil, path: nil, regex: nil, flags: nil)),
            Handler(handlerType: .recv, part: .body, action: .reveal, params: p("data.viewer.login")),
            Handler(handlerType: .recv, part: .body, action: .reveal,
                    params: p("data.viewer.contributionsCollection.contributionCalendar.totalContributions")),
        ]

        let options = ProverOptions(
            verifierUrl: Config.verifierURL.absoluteString,
            maxSentData: 2048,
            maxRecvData: 4096,
            handlers: handlers,
            mode: (mode == .proxy ? .proxy : .mpc)
        )

        let bridge = ProgressBridge(onProgress)
        let result: ProofResult = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try prove(request: req, options: options, progress: bridge)) }
                catch { cont.resume(throwing: error) }
            }
        }
        return Self.parse(result, request: request)
    }

    private static func parse(_ result: ProofResult, request: TLSNRequest) -> ProvedFact {
        let body = result.response.body
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
        let viewer = ((json?["data"] as? [String: Any])?["viewer"]) as? [String: Any]
        let login = viewer?["login"] as? String ?? "unknown"
        let cal = (((viewer?["contributionsCollection"] as? [String: Any])?["contributionCalendar"]) as? [String: Any])
        let total = cal?["totalContributions"] as? Int ?? 0
        let host = URL(string: request.url)?.host ?? GitHubProof.host
        return ProvedFact(
            account: login, value: total, label: "contributions",
            serverName: host, notaryKey: "(attestation key)",
            revealed: ["server: \(host)", "request: \(request.method) /graphql",
                       "viewer.login = \(login)", "totalContributions = \(total)"],
            redacted: ["Authorization: Bearer ••••••"]
        )
    }
}

private final class ProgressBridge: ProgressCallback {
    let cb: (NotarizeStage, Double, String) -> Void
    init(_ cb: @escaping (NotarizeStage, Double, String) -> Void) { self.cb = cb }
    func onProgress(step: String, progress: Double, message: String) {
        let s = step.uppercased()
        let stage: NotarizeStage =
            (s.contains("REVEAL") || s.contains("SEAL") || s.contains("PROOF")) ? .sealing :
            (s.contains("MPC") || s.contains("HANDSHAKE") || s.contains("TLS")) ? .confirming : .connecting
        cb(stage, progress, message)
    }
}
#endif
