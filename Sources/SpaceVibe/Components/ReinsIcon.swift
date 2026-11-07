import SwiftUI

/// The two layers of a glyph: the solid one and, in a duotone set, the lighter one.
enum GlyphLayer {
    case solid, light
}

/// The box every generated glyph is drawn in, whatever grid its set uses (the generator scales to it).
enum GlyphBox {
    static let side: CGFloat = 24
}

/// One glyph of a generated icon set (`ReinsIconData.swift`, `CategoryIconData.swift`, `ContentIconData.swift`): its shapes in
/// the 24 x 24 box and how the set is drawn. `ReinsIcon` draws any of them.
protocol GlyphSource: Sendable {
    /// The icon of the set this glyph is drawn from, for example `flash-line`.
    var iconName: String { get }
    /// False for a single-layer set (MingCute Line).
    var hasLightLayer: Bool { get }
    /// The opacity of the lighter layer.
    var layerOpacity: Double { get }
    /// A stroke in the glyph's colour added around every shape, in the 24 box (Phosphor's, as the mock draws it); 0 for none.
    var outlineWidth: CGFloat { get }
    func evenOdd(_ layer: GlyphLayer) -> Bool
    func draw(_ layer: GlyphLayer, into p: inout GlyphPen)
}

/// Writes one layer of a generated glyph into a `Path`, in the glyph's 24 x 24 box.
struct GlyphPen {
    var path = Path()

    mutating func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: CGPoint(x: x, y: y)) }
    mutating func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: CGPoint(x: x, y: y)) }
    mutating func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    }
    mutating func z() { path.closeSubpath() }
}

extension GlyphSource {
    /// One layer as a path in the 24 x 24 box.
    func path(_ layer: GlyphLayer) -> Path {
        var pen = GlyphPen()
        draw(layer, into: &pen)
        return pen.path
    }
}

/// One layer of a glyph, scaled from its 24 pt box to the rect it is given (square, centred).
struct GlyphShape: Shape {
    let glyph: any GlyphSource
    let layer: GlyphLayer

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / GlyphBox.side
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale)
        return glyph.path(layer).applying(transform)
    }
}

/// The icon sizes: 16 for controls, tabs, rows, menus and the sidebar; 14 in popovers, file rows, notes and beside 12 pt text;
/// 12 for chevrons, checks and the filter-chip close; 24 in a pane head's tile (V5-R16). Never below 12. `sidebar` is the old
/// screens' size and goes with them; `row` stays for the verdict box.
enum IconSize: CaseIterable {
    /// A sidebar item of the old screens: 22.
    case sidebar
    /// A row's lead slot, a banner, in the old screens; the verdict glyph in a v5 verdict box (the kit's 20): 20.
    case row
    /// Buttons, tags, fields, cells, tabs, rows, menus and the v5 sidebar: 16.
    case control
    /// Beside 12 pt text (the usage legend, notes, palette hints, popovers, file rows): 14.
    case inline
    /// A chevron, a check, the filter-chip close: 12, the smallest.
    case small
    /// An empty state's mark and the pane head's tile: 24.
    case large

    var points: CGFloat {
        switch self {
        case .sidebar: Metrics.iconSidebar
        case .row: Metrics.iconRow
        case .control: Metrics.iconControl
        case .inline: Metrics.iconInline
        case .small: Metrics.iconSmall
        case .large: Metrics.iconLarge
        }
    }
}

/// An icon from one of the generated sets: its layers in one colour, the lighter at the set's `layerOpacity`. The colour is the
/// current foreground style, so an icon is neutral wherever it sits; `ink` is for the two places that tint one (a state tag, a
/// banner). Hidden from VoiceOver unless it has a `label`, for an icon that carries meaning on its own.
///
/// `ReinsIcon(.lock)` draws a Solar glyph (old screens). The v5 sets have their own labels, so a name that exists in two sets
/// never reads two ways: `ReinsIcon(category: .skill)` (MingCute) and `ReinsIcon(content: .stack)` (Phosphor).
struct ReinsIcon: View {
    let source: any GlyphSource
    var size: IconSize = .control
    var ink: Color?
    var label: String?

    init(source: any GlyphSource, size: IconSize = .control, ink: Color? = nil, label: String? = nil) {
        self.source = source
        self.size = size
        self.ink = ink
        self.label = label
    }

    init(_ glyph: ReinsGlyph, size: IconSize = .control, ink: Color? = nil, label: String? = nil) {
        self.init(source: glyph, size: size, ink: ink, label: label)
    }

    init(category glyph: CategoryGlyph, size: IconSize = .control, ink: Color? = nil, label: String? = nil) {
        self.init(source: glyph, size: size, ink: ink, label: label)
    }

    init(content glyph: ContentGlyph, size: IconSize = .control, ink: Color? = nil, label: String? = nil) {
        self.init(source: glyph, size: size, ink: ink, label: label)
    }

    var body: some View {
        let drawn = ZStack {
            if source.hasLightLayer {
                GlyphLayerView(source: source, layer: .light, side: size.points).opacity(source.layerOpacity)
            }
            GlyphLayerView(source: source, layer: .solid, side: size.points)
        }
        .frame(width: size.points, height: size.points)
        Group {
            if let ink { drawn.foregroundStyle(ink) } else { drawn }
        }
        .modifier(IconAccessibility(label: label))
    }
}

/// A layer's fill, with the set's outline over it where it has one. One group, so the layer's opacity applies once.
private struct GlyphLayerView: View {
    let source: any GlyphSource
    let layer: GlyphLayer
    let side: CGFloat

    var body: some View {
        let shape = GlyphShape(glyph: source, layer: layer)
        ZStack {
            shape.fill(style: FillStyle(eoFill: source.evenOdd(layer)))
            if source.outlineWidth > 0 {
                shape.stroke(style: StrokeStyle(lineWidth: source.outlineWidth * side / GlyphBox.side, lineJoin: .round))
            }
        }
        .compositingGroup()
    }
}

/// The disclosure chevron and the menu's up-and-down mark, drawn as a stroke because Solar's Bold Duotone chevron breaks up
/// below 22 pt. The geometry is Solar's own Linear set in the same 24 box (`alt-arrow-right-linear`: M9 5 L15 12 L9 19;
/// `chevrons-up-down-linear` for the pair), 1.5 wide with round caps and joins, scaled with the icon.
struct Chevron: View {
    enum Direction {
        case right, left, down, upDown
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
        let scale = size.points / GlyphBox.side
        ChevronShape(direction: direction)
            .stroke(style: StrokeStyle(lineWidth: Metrics.chevronStroke * scale, lineCap: .round, lineJoin: .round))
            .frame(width: size.points, height: size.points)
            .modifier(IconAccessibility(label: label))
    }
}

private struct ChevronShape: Shape {
    let direction: Chevron.Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [[CGPoint]]
        switch direction {
        case .right: points = [[CGPoint(x: 9, y: 5), CGPoint(x: 15, y: 12), CGPoint(x: 9, y: 19)]]
        case .left: points = [[CGPoint(x: 15, y: 5), CGPoint(x: 9, y: 12), CGPoint(x: 15, y: 19)]]
        case .down: points = [[CGPoint(x: 5, y: 9), CGPoint(x: 12, y: 15), CGPoint(x: 19, y: 9)]]
        case .upDown:
            points = [[CGPoint(x: 18, y: 15), CGPoint(x: 12, y: 21), CGPoint(x: 6, y: 15)],
                      [CGPoint(x: 18, y: 9), CGPoint(x: 12, y: 3), CGPoint(x: 6, y: 9)]]
        }
        for line in points { path.addLines(line) }
        let side = min(rect.width, rect.height)
        let scale = side / GlyphBox.side
        return path.applying(CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale))
    }
}

private struct IconAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
