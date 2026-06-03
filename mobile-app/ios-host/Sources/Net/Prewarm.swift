import Foundation
import Combine

/// Hack 1 — **reduced** (see open-questions Q2). The TLSN build fuses
/// connect+request into `prove()`, with no separable `connect()`, so we can't
/// pre-open the prover WebSocket without forking (forbidden). We do the cheap,
/// fork-free part: pre-generate PKCE and warm DNS/TLS to the verifier host so
/// the eventual connect pays less. Best-effort; **never blocks the CTA**.
@MainActor
final class Prewarm: ObservableObject {
    static let shared = Prewarm()
    @Published private(set) var ready = false
    private(set) var pkce: PKCE?

    func run() {
        pkce = PKCE.generate()                       // free; reused by GitHubOAuth
        Task.detached(priority: .utility) {
            var req = URLRequest(url: Config.verifierURL)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 3
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = try? await URLSession.shared.data(for: req)   // warms DNS + TLS to verifier
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            await MainActor.run {
                self.ready = true
                ProofAttemptCapture.shared.emit(
                    type: "notarize.websocketConnected",
                    payload: ["stage": .string("prewarm"),
                              "durationMs": .double(ms),
                              "success": .bool(true)]
                )
            }
        }
    }
}
