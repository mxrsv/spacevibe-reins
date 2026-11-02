import SwiftUI

/// The two agents Reins compares. Colour means the CLI everywhere it appears.
enum CLIKind: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// For bars and dots.
    var fill: Color { self == .claude ? Palette.claude : Palette.codex }
    /// For text in the CLI's colour.
    var ink: Color { self == .claude ? Palette.claudeInk : Palette.codexInk }
    var tint: Color { self == .claude ? Palette.claudeTint : Palette.codexTint }
    var tagTone: TagTone { self == .claude ? .claude : .codex }
}
