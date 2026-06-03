import SwiftUI

/// Visual tokens. Subtle REP brand; target brand dominates during 3rd-party
/// login (anti-goal: no heavy REP branding over GitHub's screen).
enum Theme {
    static let bg = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let accent = Color(red: 0.36, green: 0.32, blue: 0.86)      // REP indigo
    static let github = Color(red: 0.13, green: 0.16, blue: 0.20)      // GitHub ink
    static let success = Color(red: 0.18, green: 0.70, blue: 0.40)
    static let warn = Color(red: 0.85, green: 0.55, blue: 0.10)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)

    static let corner: CGFloat = 16
    /// Hack 6 / NN-group threshold: transitions ≤ ~0.4s feel instant.
    static let snappy: Animation = .snappy(duration: 0.4)
}

/// Stage glyphs for StageProgressView — never the word "Loading".
enum StageState {
    case done      // ✓
    case current   // ●
    case pending   // ○

    var glyph: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .current: return "circle.fill"
        case .pending: return "circle"
        }
    }
    var color: Color {
        switch self {
        case .done: return Theme.success
        case .current: return Theme.accent
        case .pending: return Theme.textSecondary.opacity(0.4)
        }
    }
}

/// The named notarize stages shown when the proof can't hide under the
/// return animation (slow network). Order matters.
enum NotarizeStage: String, CaseIterable {
    case connecting = "Connecting"
    case confirming = "Confirming"
    case sealing = "Sealing"
}
