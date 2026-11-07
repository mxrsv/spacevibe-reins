import SwiftUI

/// The layout of the v5 gallery parts (`ContainerSpecimens`, `ControlSpecimens`): panels on the content panel's ground,
/// captions, and specimens two to a line at the width of a split page's card, so crops line up with the mock's.
enum SpecimenLayout {
    /// A card of a split page at 1440 x 900: half the canvas (the mock's tile).
    static let halfCanvas: CGFloat = 557

    static func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text(title).spaceVibeText(.meta, tone: .tertiary)
            content()
        }
        .padding(Space.s24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockSurface(Palette.bgPanel)
    }

    static func caption(_ text: String) -> some View {
        Text(text).spaceVibeText(.small, tone: .tertiary)
    }

    /// Specimens two to a line, each under its caption, each `halfCanvas` wide.
    static func pairs(_ items: [(String, AnyView)]) -> some View {
        let lines = stride(from: 0, to: items.count, by: 2).map { Array(items[$0 ..< min($0 + 2, items.count)]) }
        return VStack(alignment: .leading, spacing: Space.s24) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: Space.s24) {
                    ForEach(Array(line.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: Space.s8) {
                            caption(item.0)
                            item.1
                        }
                        .frame(width: halfCanvas, alignment: .topLeading)
                    }
                }
            }
        }
    }
}
