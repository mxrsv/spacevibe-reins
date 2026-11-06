import SwiftUI

extension PageGlyph {
    /// The centre lines as a path in the 24 x 24 box.
    var path: Path {
        var pen = GlyphPen()
        draw(into: &pen)
        return pen.path
    }
}

/// A page glyph's centre lines, scaled from its 24 pt box to the rect it is given (square, centred).
struct PageGlyphShape: Shape {
    let glyph: PageGlyph

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / PageGlyph.box
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale)
        return glyph.path.applying(transform)
    }
}

/// An icon inside a page, from the generated Tabler set (spec v4, "Two icon sets, split by job"): the glyph stroked at
/// 2 x size / 24 with round caps and joins, in the current foreground style, so an icon is neutral wherever it sits; `ink`
/// is for the places that tint one (a state tag, a banner). The sizes are `IconSize`'s: 20 as a row lead, 16 in buttons
/// and tags, never below 14. Hidden from VoiceOver unless it has a `label`. The sidebar draws `ReinsIcon` (Solar) instead.
struct PageIcon: View {
    let glyph: PageGlyph
    var size: IconSize = .control
    var ink: Color?
    var label: String?

    init(_ glyph: PageGlyph, size: IconSize = .control, ink: Color? = nil, label: String? = nil) {
        self.glyph = glyph
        self.size = size
        self.ink = ink
        self.label = label
    }

    var body: some View {
        let width = PageGlyph.stroke * size.points / PageGlyph.box
        let drawn = PageGlyphShape(glyph: glyph)
            .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .frame(width: size.points, height: size.points)
        Group {
            if let ink { drawn.foregroundStyle(ink) } else { drawn }
        }
        .modifier(IconAccessibility(label: label))
    }
}

/// The disclosure chevrons, the back arrow and the menu's up-and-down mark: Tabler's `chevron-right`, `chevron-left`,
/// `chevron-down` and `selector`, drawn like every page icon.
struct Chevron: View {
    enum Direction {
        case right, left, down, upDown

        var glyph: PageGlyph {
            switch self {
            case .right: .chevronRight
            case .left: .back
            case .down: .chevronDown
            case .upDown: .selector
            }
        }
    }

    let direction: Direction
    var size: IconSize = .control
    var label: String?

    init(_ direction: Direction, size: IconSize = .control, label: String? = nil) {
        self.direction = direction
        self.size = size
        self.label = label
    }

    var body: some View {
        PageIcon(direction.glyph, size: size, label: label)
    }
}
