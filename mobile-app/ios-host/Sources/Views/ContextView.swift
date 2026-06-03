import SwiftUI

/// Entry screen — "Your context".
/// • Empty → GitHub hero connect (warm-first).
/// • Has a GitHub claim → tap it for the **warm-returning 1-tap** path
///   (Face ID → silent refresh → notarize), Hacks 2 + 6.
struct ContextView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var graph: ContextGraph
    @StateObject private var reprove = ReproveFlow()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your context")
                .font(.largeTitle.bold())
                .padding(.top, 28)

            if graph.claims.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(graph.claims) { claim in
                            ClaimRow(
                                claim: claim,
                                busy: claim.platform == "github" && reprove.phase != .idle,
                                onProveAgain: claim.platform == "github"
                                    ? { reprove.proveAgain(platform: "github") } : nil
                            )
                        }
                    }
                }
            }

            Spacer()
            connectButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .overlay { stageOverlay }
        .alert("Couldn't prove", isPresented: failedBinding) {
            Button("OK") { reprove.phase = .idle }
        } message: { Text(failedMessage) }
        .onAppear {
            reprove.onSuccess = { claim in
                graph.add(claim)
                withAnimation(Theme.snappy) { router.screen = .success(claim) }
            }
            reprove.onNeedsReconnect = {
                ProofAttemptCapture.shared.startAttempt(
                    platform: "github", mode: Config.defaultMode.rawValue.lowercased(),
                    appState: "warm-first", hackVariant: "hack-1+3+4+6")
                router.screen = .connect
            }
        }
    }

    @ViewBuilder private var stageOverlay: some View {
        // Only when the warm-returning notarize overruns the budget (slow net).
        if case .notarizing = reprove.phase, reprove.showStages {
            ZStack {
                Color.black.opacity(0.15).ignoresSafeArea()
                StageProgressView(current: reprove.stage).padding(40)
            }
            .transition(.opacity)
        }
    }

    private var failedBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = reprove.phase { return true } else { return false } },
            set: { if !$0 { reprove.phase = .idle } }
        )
    }
    private var failedMessage: String {
        if case .failed(let m) = reprove.phase { return m }
        return ""
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prove something true about yourself —").font(.title3)
            Text("verifiable, private, in one tap.").font(.title3).foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var connectButton: some View {
        Button {
            // Entry into the warm-first flow; the OAuth CTA (cta.tap) is emitted
            // by "Continue with GitHub" on the connect screen.
            ProofAttemptCapture.shared.startAttempt(
                platform: "github", mode: Config.defaultMode.rawValue.lowercased(),
                appState: "warm-first", hackVariant: "hack-1+3+4+6")
            router.screen = .connect
        } label: {
            HStack(spacing: 10) {
                Image(systemName: graph.isWarmReturning ? "plus.circle.fill" : "checkmark.seal.fill")
                Text(graph.isWarmReturning ? "Add platform" : "Connect GitHub").fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.github, in: RoundedRectangle(cornerRadius: Theme.corner))
            .foregroundStyle(.white)
        }
    }
}

struct ClaimRow: View {
    let claim: ProofClaim
    var busy: Bool = false
    var onProveAgain: (() -> Void)? = nil

    var body: some View {
        if let action = onProveAgain {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .disabled(busy)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.platform.capitalized + "  ·  " + claim.account).fontWeight(.semibold)
                Text("\(claim.value.formatted()) \(claim.label)")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            trailing
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var trailing: some View {
        if busy {
            Text("Proving…").font(.caption).foregroundStyle(Theme.accent)
        } else if onProveAgain != nil {
            HStack(spacing: 4) {
                Text("Prove again").font(.caption).foregroundStyle(Theme.accent)
                Image(systemName: "faceid").font(.caption).foregroundStyle(Theme.accent)
            }
        } else {
            Text(claim.mintedAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}
