import SwiftUI

/// The two layers of a glyph: the solid one and the lighter one Solar draws at half opacity.
enum GlyphLayer {
    case solid, light
}

/// Writes one layer of a generated glyph (`ReinsIconData.swift`) into a `Path`, in the glyph's 24 x 24 box.
struct GlyphPen {
    var path = Path()

    mutating func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: CGPoint(x: x, y: y)) }
    mutating func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: CGPoint(x: x, y: y)) }
    mutating func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    }
    mutating func z() { path.closeSubpath() }
}

extension ReinsGlyph {
    /// One layer as a path in the 24 x 24 box.
    func path(_ layer: GlyphLayer) -> Path {
        var pen = GlyphPen()
        draw(layer, into: &pen)
        return pen.path
    }
}

/// One layer of a glyph, scaled from its 24 pt box to the rect it is given (square, centred).
struct GlyphShape: Shape {
    let glyph: ReinsGlyph
    let layer: GlyphLayer

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / ReinsGlyph.box
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale)
        return glyph.path(layer).applying(transform)
    }
}

/// The icon sizes (spec v3 and v4, Icons), shared by both sets: never below 14, where Solar's Bold weight loses its detail.
enum IconSize {
    /// A sidebar item: 22.
    case sidebar
    /// A row's lead slot, a banner: 20.
    case row
    /// Buttons, tags, fields and cells: 16.
    case control
    /// Beside 12 pt text (the usage legend, notes, palette hints): 14, the smallest.
    case inline
    /// An empty state's mark: 24.
    case large

    var points: CGFloat {
        switch self {
        case .sidebar: Metrics.iconSidebar
        case .row: Metrics.iconRow
        case .control: Metrics.iconControl
        case .inline: Metrics.iconInline
        case .large: Metrics.iconLarge
        }
    }
}

/// A sidebar icon from the generated Solar set: both layers in one colour, the lighter at half opacity. The colour is the
/// current foreground style; `ink` tints one (the stale clock of a Limits tile). Hidden from VoiceOver unless it has a
/// `label`, for an icon that carries meaning on its own. Since v4 only the sidebar's items and footer draw it; everything
/// inside a page draws `PageIcon` (Tabler), and `IconPolicyTests` holds that split by file.
struct ReinsIcon: View {
    let glyph: ReinsGlyph
    var size: IconSize = .control
    var ink: Color?
    var label: String?

    init(_ glyph: ReinsGlyph, size: IconSize = .control, ink: Color? = nil, label: String? = nil) {
        self.glyph = glyph
        self.size = size
        self.ink = ink
        self.label = label
    }

    var body: some View {
        let drawn = ZStack {
            GlyphShape(glyph: glyph, layer: .light)
                .fill(style: FillStyle(eoFill: glyph.evenOdd(.light)))
                .opacity(ReinsGlyph.lightOpacity)
            GlyphShape(glyph: glyph, layer: .solid)
                .fill(style: FillStyle(eoFill: glyph.evenOdd(.solid)))
        }
        .frame(width: size.points, height: size.points)
        Group {
            if let ink { drawn.foregroundStyle(ink) } else { drawn }
        }
        .modifier(IconAccessibility(label: label))
    }
}

/// Hidden from VoiceOver unless the icon carries meaning on its own (`label`). Shared by `ReinsIcon` and `PageIcon`.
struct IconAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
