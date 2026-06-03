import SwiftUI

/// Named stages with ✓ / ● / ○ — the explicit-progress fallback shown only when
/// the notarize can't hide under the return animation (slow network, Hack 6
/// timeout). Anti-goal: never a bare "Loading…" spinner.
struct StageProgressView: View {
    let current: NotarizeStage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(NotarizeStage.allCases, id: \.self) { stage in
                let state = state(for: stage)
                HStack(spacing: 12) {
                    Image(systemName: state.glyph)
                        .foregroundStyle(state.color)
                        .symbolEffect(.pulse, isActive: state == .current)
                    Text(stage.rawValue)
                        .foregroundStyle(state == .pending ? Theme.textSecondary : Theme.textPrimary)
                        .fontWeight(state == .current ? .semibold : .regular)
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private func state(for stage: NotarizeStage) -> StageState {
        let order = NotarizeStage.allCases
        guard let ci = order.firstIndex(of: current),
              let si = order.firstIndex(of: stage) else { return .pending }
        if si < ci { return .done }
        if si == ci { return .current }
        return .pending
    }
}
