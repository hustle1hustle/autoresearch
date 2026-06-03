import SwiftUI
import UIKit
import AuthenticationServices

/// Orchestrates one GitHub connect attempt: CTA → (Hack 3 pre-sheet) → OAuth
/// handoff → notarize. Hack 6: notarize runs concurrently with the return
/// transition; the named StageProgress UI appears only if it overruns the
/// animation budget (slow network).
@MainActor
final class ConnectFlow: ObservableObject {
    enum Phase: Equatable { case idle, authing, notarizing, failed(String) }

    @Published var phase: Phase = .idle
    @Published var presheetVisible = false
    @Published var stage: NotarizeStage = .connecting
    @Published var showStages = false

    @AppStorage("hasSeenGitHubPreSheet") private var hasSeenPreSheet = false

    private let auth = Auth.make()
    private let prover = Prover.make()
    private let tokens: TokenStore = InMemoryTokenStore.shared

    /// Wired by the view: persist claim + navigate to success.
    var onSuccess: ((ProofClaim) -> Void)?

    func start(anchor: ASPresentationAnchor) {
        if hasSeenPreSheet {
            Task { await authThenProve(anchor: anchor) }
        } else {
            presheetVisible = true            // Hack 3
        }
    }

    func continueFromPreSheet(anchor: ASPresentationAnchor) {
        ProofAttemptCapture.shared.emit(type: "presheet.continue")
        hasSeenPreSheet = true
        presheetVisible = false
        Task { await authThenProve(anchor: anchor) }
    }

    private func authThenProve(anchor: ASPresentationAnchor) async {
        phase = .authing
        do {
            let t = try await auth.authenticate(anchor: anchor) { stageName in
                ProofAttemptCapture.shared.emit(type: stageName)
            }
            ProofAttemptCapture.shared.emit(type: "oauth.tokenExchanged")
            tokens.save(t, platform: "github")
            await notarize(bearer: t.accessToken)
        } catch AuthError.cancelled {
            ProofAttemptCapture.shared.emit(type: "abandon", payload: ["lastStage": .string("webauth")])
            phase = .idle                      // "Got it. You can connect GitHub later."
        } catch AuthError.needsIOS174 {
            phase = .failed("This device needs iOS 17.4+ for the GitHub sign-in. (Dev: use mock auth.)")
        } catch AuthError.misconfigured {
            phase = .failed("GitHub isn't configured yet. (Dev: set Config.githubClientID or useMockAuth.)")
        } catch {
            ProofAttemptCapture.shared.emit(type: "error", payload: ["errorCategory": .string("oauth_denied")])
            phase = .failed("GitHub needs to share your contribution count for this. Want to try again?")
        }
    }

    private func notarize(bearer: String) async {
        phase = .notarizing
        showStages = false

        // Hack 6: reveal named stages only if we overrun the animation budget.
        let budget = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Config.notarizeAnimationBudget * 1_000_000_000))
            if case .notarizing = phase { withAnimation(Theme.snappy) { showStages = true } }
        }

        ProofAttemptCapture.shared.emit(type: "notarize.requestFired")
        let request = GitHubProof.request(bearer: bearer)
        let mode = ModeRouter.initialMode()
        do {
            let fact = try await prover.prove(request: request, mode: mode) { st, _, _ in
                Task { @MainActor in self.stage = st }   // progress callback may run off-main
            }
            budget.cancel()
            ProofAttemptCapture.shared.emit(type: "notarize.proofComputed")
            ProofAttemptCapture.shared.emit(type: "success", payload: [
                "totalDurationMs": .double(ProofAttemptCapture.shared.elapsedMs()),
                "notarizationsCount": .int(1),
            ])
            ProofAttemptCapture.shared.endAttempt()
            let claim = ProofClaim(
                platform: "github", account: fact.account, value: fact.value,
                label: fact.label, mode: mode.rawValue.lowercased(),
                serverName: fact.serverName, revealed: fact.revealed, redacted: fact.redacted
            )
            onSuccess?(claim)
        } catch {
            budget.cancel()
            // (ModeRouter.fallback(after:) → MPC retry wired in a later item.)
            ProofAttemptCapture.shared.emit(type: "error", payload: ["errorCategory": .string("notarize_timeout")])
            phase = .failed("Connection dropped. Try again — we don't keep anything from the failed attempt.")
        }
    }
}

struct ConnectGitHubView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var graph: ContextGraph
    @StateObject private var flow = ConnectFlow()
    @StateObject private var prewarm = Prewarm.shared

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            content
            Spacer()
        }
        .padding(20)
        .task {
            prewarm.run()                                  // Hack 1 (micro)
            flow.onSuccess = { claim in
                graph.add(claim)
                withAnimation(Theme.snappy) { router.screen = .success(claim) }
            }
        }
        .sheet(isPresented: $flow.presheetVisible) {
            PreSheetView(onContinue: { flow.continueFromPreSheet(anchor: keyWindowAnchor()) })
                .presentationDetents([.medium])
        }
    }

    // GitHub-dominant card (target brand dominates; REP subtle).
    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Theme.github, in: RoundedRectangle(cornerRadius: 20))
            Text("GitHub").font(.title2.bold())
            Text("Prove your 2026 contributions")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 40)
    }

    @ViewBuilder private var content: some View {
        switch flow.phase {
        case .idle:
            cta
        case .authing:
            namedStatus("Opening GitHub")
        case .notarizing:
            if flow.showStages { StageProgressView(current: flow.stage) }
            else { namedStatus("Minting your proof") }   // brief; hidden under transition
        case .failed(let msg):
            VStack(spacing: 14) {
                Text(msg).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
                cta
            }
        }
    }

    private var cta: some View {
        Button {
            ProofAttemptCapture.shared.emit(type: "cta.tap", payload: ["cta": .string("connect_github")])
            flow.start(anchor: keyWindowAnchor())
        } label: {
            Text("Continue with GitHub")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.github, in: RoundedRectangle(cornerRadius: Theme.corner))
                .foregroundStyle(.white)
        }
    }

    // A named micro-status (NOT a "Loading…" spinner).
    private func namedStatus(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse)
            Text(text + "…").foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 16)
    }
}

/// The presentation anchor ASWebAuthenticationSession needs, from SwiftUI.
@MainActor
func keyWindowAnchor() -> ASPresentationAnchor {
    let scene = UIApplication.shared.connectedScenes
        .first { $0.activationState == .foregroundActive } as? UIWindowScene
    return scene?.keyWindow ?? ASPresentationAnchor()
}
