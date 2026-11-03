import Observation
import SwiftUI

/// State of the window frame: which tab shows, whether the palette is open, and the footer status line.
/// Screens read it from the environment (`@Environment(ShellModel.self)`) to switch tabs or open the palette.
@MainActor
@Observable
final class ShellModel {
    let tabs: [any ReinsTab]
    let appearance: AppearanceStore

    var activeID: String
    /// The Limits page shows in the content area instead of the active tab (spec, Interface: Limits). It has no sidebar
    /// entry: the sidebar block and `⌘L` open it, choosing a tab closes it.
    var isLimitsOpen = false
    var isPaletteOpen = false
    var paletteQuery = ""
    /// A short line at the bottom of the sidebar ("Counting usage 3/9"). Nil hides it.
    var statusMessage: String?

    init(tabs: [any ReinsTab], appearance: AppearanceStore, activeID: String? = nil) {
        precondition(!tabs.isEmpty, "TabRegistry returned no tabs")
        self.tabs = tabs
        self.appearance = appearance
        self.activeID = activeID ?? tabs[0].id
    }

    var activeTab: any ReinsTab { tabs.first { $0.id == activeID } ?? tabs[0] }

    /// The top bar's title: the active tab's, or the Limits page's while it shows.
    var title: String { isLimitsOpen ? LimitsPage.title : activeTab.title }
    /// The hint bar's middle part, likewise.
    var hints: [KeyHint] { isLimitsOpen ? LimitsPage.hints : activeTab.hints }

    func select(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        isLimitsOpen = false
        isPaletteOpen = false
    }

    func openLimits() {
        isLimitsOpen = true
        isPaletteOpen = false
    }

    /// `⌘1` is index 0.
    func select(index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabs[index].id)
    }

    func openPalette(query: String = "") {
        paletteQuery = query
        isPaletteOpen = true
    }

    func closePalette() { isPaletteOpen = false }

    func togglePalette() {
        if isPaletteOpen { closePalette() } else { openPalette() }
    }
}
