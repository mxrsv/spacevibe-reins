import SwiftUI

/// True while the headless screenshot mode renders a view with `ImageRenderer`. That renderer draws neither
/// `ScrollView` content nor AppKit-backed controls such as `TextField`, so the few views that need them
/// (`SpaceVibeScrollView`, the palette field) swap in a drawable stand-in when this is set. Normal runs never set it.
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
struct SpaceVibeScrollView<Content: View>: View {
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

/// Headless shots have no ScrollView, so content taller than the frame would be squeezed (rows overlap) or push the shell
/// off screen. In a shot the content takes its ideal height and is cut at the frame, like a scrolled page. No effect in the app.
struct ShotFit: ViewModifier {
    @Environment(\.isShotRendering) private var isShotRendering

    func body(content: Content) -> some View {
        if isShotRendering {
            GeometryReader { proxy in
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            }
        } else {
            content
        }
    }
}
