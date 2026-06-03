import SwiftUI

/// Warm-returning hero path (Hack 2 + 6): tap "Prove again" → Face ID unlocks
/// the Keychain token → silent refresh → notarize. 1 tap, ~3–4 s, 0 app-switch.
@MainActor
final class ReproveFlow: ObservableObject {
    enum Phase: Equatable { case idle, authenticating, notarizing, failed(String) }

    @Published var phase: Phase = .idle
    @Published var stage: NotarizeStage = .connecting
    @Published var showStages = false

    private let prover = Prover.make()
    private let store = KeychainTokenStore.shared
    private let refresher = Refresher.make()

    /// Wired by the view.
    var onSuccess: ((ProofClaim) -> Void)?
    var onNeedsReconnect: (() -> Void)?

    func proveAgain(platform: String) {
        guard phase == .idle else { return }
        ProofAttemptCapture.shared.startAttempt(
            platform: platform, mode: Config.defaultMode.rawValue.lowercased(),
            appState: "warm-returning", hackVariant: "hack-2+6")
        ProofAttemptCapture.shared.emit(type: "cta.tap", payload: ["cta": .string("prove_again")])
        phase = .authenticating

        Task {
            let result = await store.loadWithBiometry(
                platform: platform,
                reason: "Use Face ID to refresh \(platform.capitalized) access")
            switch result {
            case .found(let tokens):
                ProofAttemptCapture.shared.emit(type: "oauth.tokenExchanged")   // silent grant
                do {
                    let fresh = try await refresher.refresh(tokens, platform: platform)
                    store.save(fresh, platform: platform)
                    await notarize(bearer: fresh.accessToken, platform: platform)
                } catch {
                    phase = .failed("Couldn't refresh \(platform.capitalized) access. Try again.")
                }
            case .noItem:
                // Re-enrolled biometry or never connected → reconnect.
                ProofAttemptCapture.shared.emit(type: "error", payload: ["errorCategory": .string("token_revoked")])
                phase = .idle
                onNeedsReconnect?()
            case .biometryFailed:
                ProofAttemptCapture.shared.emit(type: "abandon", payload: ["lastStage": .string("biometric")])
                phase = .idle   // user cancelled Face ID — no scary copy, just back to context
            }
        }
    }

    private func notarize(bearer: String, platform: String) async {
        phase = .notarizing
        showStages = false
        let notarizer = Notarizer(prover: prover)
        do {
            let claim = try await notarizer.run(
                bearer: bearer, platform: platform,
                onStage: { self.stage = $0 },
                onShowStages: {
                    if case .notarizing = self.phase { withAnimation(Theme.snappy) { self.showStages = true } }
                })
            phase = .idle
            onSuccess?(claim)
        } catch {
            phase = .failed("Connection dropped. Try again — nothing was kept.")
        }
    }
}
