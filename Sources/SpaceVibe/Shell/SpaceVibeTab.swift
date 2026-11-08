import SwiftUI

/// The count at the right of a sidebar item. `alert` paints it in the danger colour (something needs a look).
struct TabBadge: Equatable {
    var value: Int
    var alert = false
    /// Spoken after the item's title, e.g. "2 sessions need attention". Defaults to the number.
    var spoken: String?
}

/// A key hint in the bottom bar: the key cap and what it does.
struct KeyHint: Hashable {
    var keys: String
    var label: String
}

/// One row in the `⌘K` palette. A screen contributes these as actions ("Rescan usage") or items
/// ("ponytail", "Bash(git push:*)"). `perform` runs on the main actor after the palette closes; to move to
/// another tab first, call `ShellModel.select(_:)` from it.
struct PaletteEntry: Identifiable {
    let id: String
    var title: String
    var subtitle: String?
    var icon: SpaceVibeGlyph?
    /// The v5 shell draws this instead of `icon` (a Phosphor or MingCute glyph).
    var glyph: (any GlyphSource)?
    /// Right-aligned hint such as a shortcut.
    var trailing: String?
    /// Extra words the search matches besides the title.
    var keywords: [String] = []
    var perform: @MainActor () -> Void
}

/// What a screen supplies to the shell. The shell lists tabs in `TabRegistry`, shows `title`, `icon` and
/// `badge` in the sidebar, `hints` in the bottom bar, the palette entries in `⌘K`, and keeps `content` alive
/// while another tab is showing (its scroll position and filters survive a switch).
///
/// Make a screen a `final class` conforming to this, mark it `@Observable` if its count or actions change:
/// the shell reads `badge`, `hints` and the palette entries while rendering, so Observation updates them.
///
///     @MainActor @Observable final class LoadoutTab: SpaceVibeTab {
///         let id = "loadout"; let title = "Loadout"; let icon = SpaceVibeGlyph.loadout
///         var badge: TabBadge? { TabBadge(value: items.count) }
///         var content: AnyView { AnyView(LoadoutScreen(model: model)) }
///     }
///
/// Screens read shared services from the environment: `@Environment(ToastCenter.self)` and `@Environment(ShellModel.self)`.
@MainActor
protocol SpaceVibeTab: AnyObject {
    /// Stable, lowercase. Position in `TabRegistry` decides the `⌘1`, `⌘2`, `⌘3` shortcut.
    var id: String { get }
    var title: String { get }
    /// The old sidebar's glyph (Solar). A v5 tab sets `glyph` and leaves this at its default.
    var icon: SpaceVibeGlyph { get }
    /// The glyph the v5 sidebar and palette draw: a Phosphor, MingCute or verdict glyph (`GlyphSource`).
    var glyph: any GlyphSource { get }
    /// The data source named at the right of the v5 status bar ("Counted from local logs"). Nil names none.
    var source: String? { get }
    var badge: TabBadge? { get }
    /// Shown after the always-present `⌘K Search or run` and before `Esc Close`.
    var hints: [KeyHint] { get }
    /// Shown under "Actions" while this tab is active.
    var paletteActions: [PaletteEntry] { get }
    /// Searchable under "Items" from any tab, once the user has typed something.
    var paletteItems: [PaletteEntry] { get }
    var content: AnyView { get }
    /// A confirmation the v5 shell draws over the whole window, sidebar included (V5-R59: the scrim covers the window). Nil: none.
    var modal: AnyView? { get }
}

extension SpaceVibeTab {
    /// Until the cut-over (X1) removes `icon`, a tab with no Solar glyph of its own takes this one and draws `glyph`.
    var icon: SpaceVibeGlyph { .loadout }
    var glyph: any GlyphSource { icon }
    var source: String? { nil }
    var badge: TabBadge? { nil }
    var hints: [KeyHint] { [] }
    var paletteActions: [PaletteEntry] { [] }
    var paletteItems: [PaletteEntry] { [] }
    var modal: AnyView? { nil }
}
