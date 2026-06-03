import SwiftUI

/// Hack 3 — pre-sheet explainer shown once before the iOS system consent sheet,
/// so the scary "App wants to use github.com to Sign In" has context. Target
/// brand (GitHub) dominates; REP stays subtle.
struct PreSheetView: View {
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Theme.textSecondary.opacity(0.25)).frame(width: 36, height: 5).padding(.top, 8)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.github)

            Text("Connect GitHub").font(.title2.bold())

            Text("We'll ask GitHub to share your 2026 contribution count. Next, iOS asks permission to continue — your password stays with GitHub, never with us.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)

            Button {
                onContinue()
                dismiss()
            } label: {
                Text("Continue with GitHub")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Theme.github, in: RoundedRectangle(cornerRadius: Theme.corner))
            .foregroundStyle(.white)

            Text("You can disconnect anytime.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(24)
        .onAppear { ProofAttemptCapture.shared.emit(type: "presheet.shown") }
    }
}
