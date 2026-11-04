import SwiftUI

/// The frame every screen sits in below the shell's top bar: an optional tools row (filters, selectors) and a scrolling body
/// on the `well`, inset by the page padding. The tools row sits 8 pt under the top bar and 24 pt above the first card; a
/// screen without tools starts its first card 24 pt under the top bar. Inside the body, stack cards with `Rhythm`.
struct PageLayout<Tools: View, Content: View>: View {
    let tools: Tools
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if Tools.self != EmptyView.self {
                tools
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, Space.s8)
                    .padding(.bottom, Space.s24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ReinsScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, Tools.self == EmptyView.self ? Space.s24 : 0)
                    .padding(.bottom, Metrics.pageBottomPadding)
            }
        }
        .background(Palette.well)
    }
}

extension PageLayout where Tools == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.tools = EmptyView()
        self.content = content()
    }
}

extension PageLayout {
    init(@ViewBuilder tools: () -> Tools, @ViewBuilder content: () -> Content) {
        self.tools = tools()
        self.content = content()
    }
}

extension View {
    /// The tools row of a screen that builds its own scrolling body (Loadout's pinned headers): PageLayout's tools padding.
    func pageTools() -> some View {
        padding(.horizontal, Metrics.pagePadding)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The scrolling body of such a screen: PageLayout's side and bottom padding.
    func pageContent() -> some View {
        padding(.horizontal, Metrics.pagePadding)
            .padding(.bottom, Metrics.pageBottomPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The `well` behind a screen.
    func pageBackground() -> some View {
        background(Palette.well)
    }
}

/// Vertical rhythm between blocks on a page: nearness says what belongs together.
enum Rhythm {
    /// Between two cards of one screen (Skills, Agents, Hooks).
    static let cards = Space.s24
    /// Between regions (Rules' grid and its rule list; Activity's lanes and the file history).
    static let regions = Space.s32
    /// Between two cards in one Activity lane.
    static let laneCards = Space.s16
    /// Between controls in a toolbar.
    static let tools = Space.s8
    /// Between a scope picker and the filter chips after it.
    static let toolGroups = Space.s16
    /// Between chips of one filter.
    static let chips = Space.s6
    /// A legend or note line under the card it explains.
    static let caption = Space.s8
    /// Between tiles inside one card (the Limits page's facts).
    static let tiles = Space.s12
}
