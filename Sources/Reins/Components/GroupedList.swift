import SwiftUI

/// What a child of a `GroupedList` is, so the list knows which separator goes between two children.
enum GroupedListPart {
    /// `detail`: an expansion under the row above it, so no line between them.
    case row, header, section, plain, detail
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct GroupedListPartKey: ContainerValueKey {
    static let defaultValue = GroupedListPart.row
}

/// Set by `Row`: its block is filled (hovered or selected), so the dividers on both sides of it hide.
private struct GroupedListFilledKey: ContainerValueKey {
    static let defaultValue = false
}

extension ContainerValues {
    var groupedListPart: GroupedListPart {
        get { self[GroupedListPartKey.self] }
        set { self[GroupedListPartKey.self] = newValue }
    }

    var groupedListFilled: Bool {
        get { self[GroupedListFilledKey.self] }
        set { self[GroupedListFilledKey.self] = newValue }
    }
}

extension View {
    /// Marks this child of a `GroupedList`; `CardHeader`, `SectionRow` and `EmptyRow` set it themselves.
    func groupedListPart(_ part: GroupedListPart) -> some View {
        containerValue(\.groupedListPart, part)
    }
}

/// A card: one rounded `surface` block on the page's `well` holding a `CardHeader`, rows and section rows. No border and no
/// shadow: the fill sets it off. Cards do not nest. 8 pt of space sits under the last child, and above the first when the
/// card has no header.
///
/// Separators: between two rows a faint `divider`, from where the row text starts to 8 pt before the row block's end; it
/// hides beside a row whose block is filled (hovered or selected). None under the header or a section row; 16 pt of space,
/// not a line, before a section row that follows rows. Controls inside the card take the card's ground (`surfaceRaised`).
struct GroupedList<Content: View>: View {
    /// `.belowPinnedHeader`: the rows of a card whose `CardHeader` pins separately (`.pinnedCardTop()`), so only the
    /// bottom corners round and the top edge lies on the header's bottom edge.
    var edges: CardEdges = .all
    @ViewBuilder var content: Content

    init(edges: CardEdges = .all, @ViewBuilder content: () -> Content) {
        self.edges = edges
        self.content = content()
    }

    var body: some View {
        let shape = edges.shape
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                // Keyed by each subview's own identity, so a row's hover and focus state stay with the row when rows are
                // removed or filtered out above it.
                ForEach(Array(subviews.enumerated()), id: \.element.id) { offset, subview in
                    let previous = offset == 0 ? nil : subviews[offset - 1].containerValues
                    separator(
                        after: previous?.groupedListPart,
                        before: subview.containerValues.groupedListPart,
                        hidden: (previous?.groupedListFilled ?? false) || subview.containerValues.groupedListFilled
                    )
                    subview
                }
            }
            .padding(.top, topPadding(first: subviews.first?.containerValues.groupedListPart))
            .padding(.bottom, Metrics.cardBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(Palette.surface))
        .clipShape(shape)
        .controlGround(.card)
        .accessibilityElement(children: .contain)
    }

    /// A card that starts with rows gets the same 8 pt above them as below; a header, or a pinned one above, needs none.
    private func topPadding(first: GroupedListPart?) -> CGFloat {
        guard edges == .all, let first, first != .header else { return 0 }
        return Metrics.cardBottomPadding
    }

    @ViewBuilder
    private func separator(after previous: GroupedListPart?, before part: GroupedListPart, hidden: Bool) -> some View {
        switch (previous, part) {
        case (nil, _), (.section?, _), (_, .detail), (.header?, _), (_, .header):
            EmptyView()
        case (_, .section):
            Color.clear.frame(height: Space.s16).accessibilityHidden(true)
        default:
            RowDivider().opacity(hidden ? 0 : 1)
        }
    }
}

/// The 1 pt line between two rows of a card: the text colour at 8%, from where the row text starts to 8 pt before the end
/// of the row block.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 1)
            .padding(.leading, Metrics.rowInset + Metrics.dividerLeadingInset)
            .padding(.trailing, Metrics.rowInset + Metrics.dividerTrailingInset)
            .accessibilityHidden(true)
    }
}

/// A full-width 1 pt line in the border colour, for overlays (the command palette) and the footnote region.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

enum CardEdges {
    case all, belowPinnedHeader

    var shape: UnevenRoundedRectangle {
        let r = Metrics.groupRadius
        switch self {
        case .all: return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        case .belowPinnedHeader: return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0, style: .continuous)
        }
    }
}

extension View {
    /// A `CardHeader` used as a pinned section header: the card's top corners, with the well behind them so rows that
    /// scroll under it never show in the corners. Pair with `GroupedList(edges: .belowPinnedHeader)`.
    func pinnedCardTop() -> some View {
        let r = Metrics.groupRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: r, style: .continuous)
        return clipShape(shape)
            .background(Palette.well)
    }
}
