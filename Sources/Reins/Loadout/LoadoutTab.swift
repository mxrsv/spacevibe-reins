import SwiftUI

/// Registers Loadout with the shell: sidebar item, badge, hint, palette entries and the screen.
@MainActor
final class LoadoutTab: ReinsTab {
    static let tabID = "loadout"

    let id = LoadoutTab.tabID
    let title = "Loadout"
    let systemImage = "square.stack.3d.up"
    let model: LoadoutModel

    init(env: AppEnvironment? = nil) { model = LoadoutModel(env: env ?? .shared) }

    init(model: LoadoutModel) { self.model = model }

    /// The rows of the global scope; a skill in both CLIs counts once.
    var badge: TabBadge? {
        model.badge.map { TabBadge(value: $0, spoken: "\($0) \($0 == 1 ? "item" : "items")") }
    }

    var hints: [KeyHint] { [KeyHint(keys: "Tab", label: "Row actions")] }
    var paletteActions: [PaletteEntry] { model.paletteActions }
    var paletteItems: [PaletteEntry] { model.paletteItems }
    var content: AnyView { AnyView(LoadoutScreen(model: model)) }
}
