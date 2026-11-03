import SwiftUI

/// Registers Rules with the shell: sidebar item and badge, hint, palette entries and the screen. Building it reads nothing;
/// the screen's first appearance starts the read.
@MainActor
final class RulesTab: ReinsTab {
    static let tabID = "rules"

    let id = RulesTab.tabID
    let title = "Rules"
    let icon = ReinsGlyph.rules
    let model: RulesModel

    init(env: AppEnvironment? = nil) { model = RulesModel(env: env ?? .shared) }

    init(model: RulesModel) { self.model = model }

    /// How many rules the global settings file holds.
    var badge: TabBadge? {
        model.badge.map { TabBadge(value: $0, spoken: "\($0) \($0 == 1 ? "rule" : "rules")") }
    }

    var hints: [KeyHint] { [KeyHint(keys: "Space", label: "Show the rules behind a row")] }
    var paletteActions: [PaletteEntry] { model.paletteActions }
    var paletteItems: [PaletteEntry] { model.paletteItems }
    var content: AnyView { AnyView(RulesScreen(model: model)) }
}
