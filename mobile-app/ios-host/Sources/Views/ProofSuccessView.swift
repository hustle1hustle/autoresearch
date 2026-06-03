import SwiftUI

/// Explicit success state with the fact (anti-goal: never a silent green
/// checkmark). "What was proved" is an expandable affordance *after* success
/// (OQ7) — not a blocking pre-commit step.
struct ProofSuccessView: View {
    let claim: ProofClaim
    @EnvironmentObject var router: AppRouter
    @State private var showDetail = false

    private var shareURL: URL { URL(string: "https://rep.xyz/p/\(claim.id.uuidString)")! }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 68))
                .foregroundStyle(Theme.success)
                .transition(.scale.combined(with: .opacity))

            Text("Proof minted").font(.title.bold())
            Text("\(claim.account)  ·  \(claim.value.formatted()) \(claim.label)")
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 12) {
                ShareLink(item: shareURL) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.corner))
                .foregroundStyle(.white)

                Button {
                    withAnimation(Theme.snappy) { showDetail.toggle() }
                } label: {
                    Label("What was proved", systemImage: showDetail ? "chevron.up" : "chevron.down")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
            }
            .padding(.horizontal, 4)

            if showDetail { detail }

            Spacer()

            Button("Done") { router.screen = .context }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.github, in: RoundedRectangle(cornerRadius: Theme.corner))
                .foregroundStyle(.white)
        }
        .padding(20)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Revealed")
            ForEach(claim.revealed, id: \.self) { Text("• \($0)").font(.footnote) }
            label("Redacted")
            ForEach(claim.redacted, id: \.self) {
                Text("• \($0)").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Divider()
            Text("Notarized over **\(claim.mode)** mode · server **\(claim.serverName)**")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2.bold()).foregroundStyle(Theme.textSecondary).padding(.top, 4)
    }
}
