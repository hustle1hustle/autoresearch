import SwiftUI

/// Entry screen — "Your context". Empty state leads to the GitHub hero connect;
/// once a proof exists it lists claims with a "Prove again" affordance.
/// (The true 1-tap warm-returning Face ID path is item ⑥ / Hack 2.)
struct ContextView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var graph: ContextGraph

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
                        ForEach(graph.claims) { ClaimRow(claim: $0) }
                    }
                }
            }

            Spacer()
            connectButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prove something true about yourself —")
                .font(.title3)
            Text("verifiable, private, in one tap.")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var connectButton: some View {
        Button {
            ProofAttemptCapture.shared.startAttempt(
                platform: "github",
                mode: Config.defaultMode.rawValue.lowercased(),
                appState: graph.isWarmReturning ? "warm-returning" : "warm-first",
                hackVariant: "hack-1+3+4+6"
            )
            ProofAttemptCapture.shared.emit(type: "cta.tap", payload: [
                "cta": .string(graph.isWarmReturning ? "add_platform" : "connect_github")
            ])
            router.screen = .connect
        } label: {
            HStack(spacing: 10) {
                Image(systemName: graph.isWarmReturning ? "plus.circle.fill" : "checkmark.seal.fill")
                Text(graph.isWarmReturning ? "Add platform" : "Connect GitHub")
                    .fontWeight(.semibold)
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
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.platform.capitalized + "  ·  " + claim.account).fontWeight(.semibold)
                Text("\(claim.value.formatted()) \(claim.label)")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(claim.mintedAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}
