import SwiftUI

/// A v5 page whose region is not built yet (W17): the tab head's place and "Not built yet" in the canvas. Registered by
/// `TabRegistry` for Activity until its task replaces it; deleted then.
@MainActor
final class PlannedPageTab: SpaceVibeTab {
    let id: String
    let title: String
    let glyph: any GlyphSource

    init(id: String, title: String, glyph: any GlyphSource) {
        self.id = id
        self.title = title
        self.glyph = glyph
    }

    var content: AnyView { AnyView(PlannedPage(title: title)) }
}

/// The empty tab head and the "Not built yet" state a planned page draws.
struct PlannedPage: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            TabHead {
            } actions: {
            }
            QuietEmptyState("Not built yet", message: "\(title) arrives in a later step of the v5 build.", placement: .list)
            Spacer(minLength: 0)
        }
    }
}
