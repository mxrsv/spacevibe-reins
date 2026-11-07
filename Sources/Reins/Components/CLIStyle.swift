import ReinsCore
import SwiftUI

/// Colour means the CLI everywhere it appears.
extension InventoryCLI {
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

    /// The same CLI as the core's DTOs name it.
    // bridge: removed with the Loadout migration
    init(_ cli: CoreCLI) { self = cli == .claude ? .claude : .codex }
}

extension CoreCLI {
    // bridge: removed with the Loadout migration
    var label: String { InventoryCLI(self).label }
}
