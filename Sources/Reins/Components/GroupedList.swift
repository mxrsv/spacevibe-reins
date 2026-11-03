import SwiftUI

/// What a child of a `GroupedList` is, so the list knows which separator goes between two children.
enum GroupedListPart {
    case row, header, section, plain
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct GroupedListPartKey: ContainerValueKey {
    static let defaultValue = GroupedListPart.row
}

extension ContainerValues {
    var groupedListPart: GroupedListPart {
        get { self[GroupedListPartKey.self] }
        set { self[GroupedListPartKey.self] = newValue }
    }
}

extension View {
    /// Marks this child of a `GroupedList`; `CardHeader`, `SectionRow` and `EmptyRow` set it themselves.
    func groupedListPart(_ part: GroupedListPart) -> some View {
        containerValue(\.groupedListPart, part)
    }
}

/// A card: one bordered, rounded `surface` holding a `CardHeader`, rows and section rows. It reads as one block against
/// the page's `well`. Elevation is the border only; cards do not nest.
///
/// Separators: a full hairline under the header; between two rows a `track` line inset to the text (`Metrics.separatorInset`)
/// so the rows read as one group; none under a section row; 16 pt of space, not a line, before a section row that follows
/// rows.
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    separator(
                        after: index == subviews.startIndex ? nil : subviews[index - 1].containerValues.groupedListPart,
                        before: subviews[index].containerValues.groupedListPart
                    )
                    subviews[index]
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(Palette.surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func separator(after previous: GroupedListPart?, before part: GroupedListPart) -> some View {
        switch (previous, part) {
        case (nil, _), (.section?, _):
            EmptyView()
        case (.header?, _), (_, .header):
            Hairline()
        case (_, .section):
            Color.clear.frame(height: Space.s16).accessibilityHidden(true)
        default:
            Hairline(inset: true)
        }
    }
}

/// A 1 pt separator: full width in the border colour, or `inset` to the row text in the track colour.
struct Hairline: View {
    var inset = false

    var body: some View {
        Rectangle()
            .fill(inset ? Palette.track : Palette.border)
            .frame(height: 1)
            .padding(.leading, inset ? Metrics.separatorInset : 0)
            .padding(.trailing, inset ? Metrics.rowHorizontalPadding : 0)
            .accessibilityHidden(true)
    }
}
