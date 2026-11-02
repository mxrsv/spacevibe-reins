import SwiftUI

/// True while the headless screenshot mode renders a view with `ImageRenderer`. That renderer draws neither
/// `ScrollView` content nor AppKit-backed controls such as `TextField`, so the few views that need them
/// (`ReinsScrollView`, the palette field) swap in a drawable stand-in when this is set. Normal runs never set it.
private struct ShotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isShotRendering: Bool {
        get { self[ShotRenderingKey.self] }
        set { self[ShotRenderingKey.self] = newValue }
    }
}

/// The scroll container for every screen. Use it instead of `ScrollView` so headless screenshots show the content.
struct ReinsScrollView<Content: View>: View {
    @Environment(\.isShotRendering) private var isShotRendering
    @ViewBuilder var content: Content

    var body: some View {
        if isShotRendering {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView { content.frame(maxWidth: .infinity, alignment: .topLeading) }
        }
    }
}
