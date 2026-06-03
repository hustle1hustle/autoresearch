import Foundation

enum ProverMode: String { case proxy = "Proxy"; case mpc = "Mpc" }

struct TLSNRequest {
    let url: String
    let method: String
    var headers: [String: String]
    var body: String?
}

/// UI-ready parsed result of a proof.
struct ProvedFact {
    let account: String       // viewer.login
    let value: Int            // totalContributions
    let label: String         // "contributions"
    let serverName: String    // api.github.com
    let notaryKey: String
    let revealed: [String]    // for the "What was proved" card
    let redacted: [String]
}

enum ProverError: Error { case cloudflareChallenge, network, timeout, tokenExpired }

protocol TLSNProving {
    /// One-shot prove (OQ7: hero 1-tap path). Emits (stage, 0…1, message).
    func prove(request: TLSNRequest,
               mode: ProverMode,
               onProgress: @escaping (NotarizeStage, Double, String) -> Void) async throws -> ProvedFact
}

/// GitHub hero request builder — mirrors test-kit/targets/github.md.
enum GitHubProof {
    static let host = "api.github.com"
    static func request(bearer: String) -> TLSNRequest {
        let query = #"{"query":"query { viewer { login contributionsCollection(from: \"2026-01-01T00:00:00Z\") { contributionCalendar { totalContributions } } } }"}"#
        return TLSNRequest(
            url: "https://\(host)/graphql",
            method: "POST",
            headers: [
                "Host": host,
                "User-Agent": "rep-prover/1.0",
                "Authorization": "Bearer \(bearer)",     // REDACTED in proof
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Connection": "close",
            ],
            body: query
        )
    }
}

/// Proxy by default; flip to MPC on a Cloudflare/WAF signal (ROUTING Level 1).
enum ModeRouter {
    static func initialMode() -> ProverMode { Config.defaultMode }
    static func fallback(after error: Error) -> ProverMode? {
        if case ProverError.cloudflareChallenge = error { return .mpc }
        return nil
    }
}

/// Mock prover — realistic GitHub result with proxy-like ~1.6 s staged
/// progress. No Rust/xcframework needed; this is what makes the opening UX
/// runnable on the simulator today. Swap for UniFFIProver in item ⑧.
final class MockProver: TLSNProving {
    func prove(request: TLSNRequest,
               mode: ProverMode,
               onProgress: @escaping (NotarizeStage, Double, String) -> Void) async throws -> ProvedFact {
        let total: Double = (mode == .proxy) ? 1.6 : 12.5     // simulate the proxy/MPC gap
        let stages: [(NotarizeStage, String)] = [
            (.connecting, "Connecting to api.github.com"),
            (.confirming, "Confirming TLS session"),
            (.sealing, "Sealing proof"),
        ]
        for (i, s) in stages.enumerated() {
            onProgress(s.0, Double(i) / Double(stages.count), s.1)
            try await Task.sleep(nanoseconds: UInt64(total / Double(stages.count) * 1_000_000_000))
        }
        onProgress(.sealing, 1.0, "Done")
        let contributions = 1247
        return ProvedFact(
            account: "octocat",
            value: contributions,
            label: "contributions",
            serverName: GitHubProof.host,
            notaryKey: "ed25519:demo…",
            revealed: ["server: api.github.com",
                       "request: POST /graphql (viewer.contributions)",
                       "viewer.login = octocat",
                       "totalContributions = \(contributions)"],
            redacted: ["Authorization: Bearer ••••••"]
        )
    }
}

/// Resolves the active prover from Config.
enum Prover {
    static func make() -> TLSNProving {
        // if !Config.useMockProver { return UniFFIProver() }   // item ⑧
        return MockProver()
    }
}
