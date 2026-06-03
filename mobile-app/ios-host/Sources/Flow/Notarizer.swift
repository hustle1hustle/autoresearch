import SwiftUI

/// Shared notarize step used by both connect (warm-first) and reprove
/// (warm-returning) flows, so the Hack 6 timing + analytics live in one place.
@MainActor
struct Notarizer {
    let prover: TLSNProving

    /// Runs the proof. Hack 6: the named StageProgress UI is revealed via
    /// `onShowStages` only if the proof overruns the animation budget. Stage
    /// updates go through `onStage`. Returns the minted claim.
    func run(bearer: String,
             platform: String,
             onStage: @escaping (NotarizeStage) -> Void,
             onShowStages: @escaping () -> Void) async throws -> ProofClaim {
        let budget = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Config.notarizeAnimationBudget * 1_000_000_000))
            onShowStages()
        }
        ProofAttemptCapture.shared.emit(type: "notarize.requestFired")
        let request = GitHubProof.request(bearer: bearer)
        let mode = ModeRouter.initialMode()
        do {
            let fact = try await prover.prove(request: request, mode: mode) { st, _, _ in
                Task { @MainActor in onStage(st) }     // progress may arrive off-main
            }
            budget.cancel()
            ProofAttemptCapture.shared.emit(type: "notarize.proofComputed")
            ProofAttemptCapture.shared.emit(type: "success", payload: [
                "totalDurationMs": .double(ProofAttemptCapture.shared.elapsedMs()),
                "notarizationsCount": .int(1),
            ])
            ProofAttemptCapture.shared.endAttempt()
            return ProofClaim(
                platform: platform, account: fact.account, value: fact.value,
                label: fact.label, mode: mode.rawValue.lowercased(),
                serverName: fact.serverName, revealed: fact.revealed, redacted: fact.redacted
            )
        } catch {
            budget.cancel()
            ProofAttemptCapture.shared.emit(type: "error", payload: ["errorCategory": .string("notarize_timeout")])
            throw error
        }
    }
}
