import SwiftUI

/// How a card lays out its body (V5-R54).
enum TileLayout {
    /// Rows (`ListRows`, `BandStack`): 0 on top, 12 at the sides, 16 below.
    case rows
    /// Free content (the Answer, figures, a chart, a note): 4 on top, 20 at the sides, 24 below, 20 between parts.
    case content
    /// A body that brings its own padding: `LoadingSkeleton`, `QuietEmptyState(placement: .card)`.
    case bare
}

/// A card (the Tile, D56, V5-R54): `bgRaise` with a 1 pt `hair` edge, radius 8 and the top-edge highlight, no drop shadow,
/// never nested. The header (52) holds the title (16/24 600), an optional count that names its unit and range ("4 commands,
/// last 14 days"), an optional state glyph, optional 28-high actions and the collapse chevron. Closed, only the header shows.
///
///     Tile("Next resets", count: "6", isOpen: $open) { ListRows { ... } }
///
/// `maxHeight` caps the whole card; a taller body scrolls inside it (V5-R52). The open state is the caller's, so a page keeps
/// it in `OpenStateStore` like a band's.
struct Tile<Actions: View, Content: View>: View {
    let title: String
    var count: String?
    var state: StateMark?
    var layout: TileLayout = .rows
    var maxHeight: CGFloat?
    @Binding var isOpen: Bool
    let actions: Actions
    let content: Content

    @Environment(\.isShotRendering) private var isShotRendering
    @State private var bodyHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen { cappedBody }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockSurface(Palette.bgRaise)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Metrics.Tile.headerSpacing) {
            Text(title)
                .spaceVibeText(.cardTitle, tone: .primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count).spaceVibeText(.prose, tone: .tertiary).lineLimit(1).fixedSize()
            }
            if let state { StateMarkIcon(mark: state) }
            Spacer(minLength: 0)
            HStack(spacing: Metrics.Tile.actionSpacing) {
                actions
                TileCollapseButton(title: title, isOpen: $isOpen)
            }
        }
        .padding(.leading, Metrics.Tile.headerLeading)
        .padding(.trailing, Metrics.Tile.headerTrailing)
        .frame(height: Metrics.Tile.headerHeight)
    }

    @ViewBuilder
    private var cappedBody: some View {
        if let maxHeight {
            let limit = max(0, maxHeight - Metrics.Tile.headerHeight)
            if isShotRendering {
                // A headless shot draws no scroll view: the body is cut at the cap, as if scrolled to the top.
                laidOutBody.fixedSize(horizontal: false, vertical: true).frame(maxHeight: limit, alignment: .top).clipped()
            } else {
                ScrollView {
                    laidOutBody.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bodyHeight = $0 }
                }
                .frame(height: min(bodyHeight, limit))
            }
        } else {
            laidOutBody
        }
    }

    @ViewBuilder
    private var laidOutBody: some View {
        switch layout {
        case .rows:
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, Metrics.Tile.rowsSide)
                .padding(.bottom, Metrics.Tile.rowsBottom)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .content:
            VStack(alignment: .leading, spacing: Metrics.Tile.contentSpacing) { content }
                .padding(.top, Metrics.Tile.contentTop)
                .padding(.horizontal, Metrics.Tile.contentSide)
                .padding(.bottom, Metrics.Tile.contentBottom)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bare:
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension Tile where Actions == EmptyView {
    init(_ title: String, count: String? = nil, state: StateMark? = nil, layout: TileLayout = .rows, maxHeight: CGFloat? = nil,
         isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, state: state, layout: layout, maxHeight: maxHeight, isOpen: isOpen,
                  actions: EmptyView(), content: content())
    }
}

extension Tile {
    init(_ title: String, count: String? = nil, state: StateMark? = nil, layout: TileLayout = .rows, maxHeight: CGFloat? = nil,
         isOpen: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, count: count, state: state, layout: layout, maxHeight: maxHeight, isOpen: isOpen,
                  actions: actions(), content: content())
    }
}

/// The card's collapse button: the caret (16, `fg2`) in a 28 square, turned a quarter left while closed. Hover fills it and
/// brightens the caret; focus fills it with `sel` (D57).
private struct TileCollapseButton: View {
    let title: String
    @Binding var isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        Button { isOpen.toggle() } label: {
            SpaceVibeIcon(content: .caretDown, size: .control)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
                .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: isOpen)
                .foregroundStyle(hovering ? Palette.fg : Palette.fg2)
                .frame(width: Metrics.Tile.headerControl, height: Metrics.Tile.headerControl)
                .background(shape.fill(hovering ? Palette.hover : .clear))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .spaceVibeFocusable(cornerRadius: Metrics.Radius.control)
        .accessibilityLabel("\(isOpen ? "Collapse" : "Expand") \(title)")
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }
}
