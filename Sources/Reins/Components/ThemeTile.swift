import SwiftUI

/// One choice of Settings > Theme: a small Reins window painted in that appearance, with the choice's icon and name under
/// it. 8 pt inside, radius 12; the chosen tile takes the `selection` fill, the others `hover` under the pointer. The
/// picture is drawn from the real tokens with the appearance forced, so it changes when the palette does.
struct ThemeTile: View {
    let title: String
    let icon: PageGlyph
    /// What the picture shows; nil is System: dark on the left, light on the right.
    let appearance: ColorScheme?
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.s8) {
                picture
                HStack(spacing: Space.s8) {
                    PageIcon(icon).foregroundStyle(TextTone.secondary.color)
                    Text(title).reinsText(isSelected ? .bodyStrong : .body, tone: isSelected ? .primary : .secondary)
                }
                .padding(.horizontal, Space.s4)
            }
            .padding(Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isSelected ? Palette.selection : (hovering ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: Metrics.groupRadius)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return ZStack {
            if let appearance {
                MiniWindow().environment(\.colorScheme, appearance)
            } else {
                MiniWindow().environment(\.colorScheme, .dark)
                MiniWindow().environment(\.colorScheme, .light).clipShape(LightHalf())
            }
        }
        .aspectRatio(Metrics.themeThumbnailAspect, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.divider, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A Reins window at thumbnail size: the sidebar with one active item, a page title and two cards of text lines.
private struct MiniWindow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Space.s8) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) }
                }
                .padding(.bottom, Space.s6)
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index == 0 ? Palette.surface : .clear)
                        .frame(height: 10)
                        .overlay(alignment: .leading) {
                            Capsule().fill(index == 0 ? strong : line).frame(width: 24, height: 3).padding(.leading, Space.s4)
                        }
                }
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: Space.s6) {
                Capsule().fill(strong).frame(width: 40, height: 4).padding(.top, Space.s2)
                card(lines: [0.42, 1, 0.7, 0.8])
                card(lines: [0.42, 0.7])
            }
        }
        .padding(Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.well)
    }

    private var strong: Color { Palette.text.opacity(0.7) }
    private var line: Color { Palette.text.opacity(0.18) }

    /// Widths as shares of the card; the first line is the card's title.
    private func card(lines: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, share in
                GeometryReader { proxy in
                    Capsule().fill(index == 0 ? strong : line).frame(width: proxy.size.width * share)
                }
                .frame(height: 3)
            }
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.surface))
    }
}

/// The System tile's light part: a slanted cut so both halves show the same window.
private struct LightHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
