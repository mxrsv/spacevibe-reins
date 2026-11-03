import SwiftUI

/// A number in a column (cost, a count of runs), right-aligned in a fixed width so the column lines up.
struct NumberCell: View {
    let text: String
    var muted = false
    var width: CGFloat = Metrics.costWidth

    var body: some View {
        Text(text)
            .reinsText(.number, tone: muted ? .tertiary : .primary)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

/// A state tag right-aligned in a fixed column, so the text before it keeps one width whatever the state says.
struct StateCell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.frame(width: Metrics.stateWidth, alignment: .trailing)
    }
}

/// Any cell content right-aligned in a fixed width, to share a column with `NumberCell` (a repeat count under a cost).
struct FixedCell<Content: View>: View {
    var width: CGFloat = Metrics.costWidth
    @ViewBuilder var content: Content

    var body: some View {
        content.frame(width: width, alignment: .trailing)
    }
}

/// An empty 28 pt action slot, so per-CLI actions keep their column when one CLI has nothing to act on.
struct EmptyActionSlot: View {
    var body: some View {
        Color.clear.frame(width: Metrics.controlHeight, height: Metrics.controlHeight).accessibilityHidden(true)
    }
}

/// A lock in an action slot: the row cannot be changed here, and the help text says why.
struct ReadOnlyMark: View {
    let reason: String

    var body: some View {
        ReinsIcon(.lock, label: reason)
            .foregroundStyle(TextTone.tertiary.color)
            .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
            .help(reason)
    }
}

/// Holds a column's width in a header where the column has no label (the actions column).
struct ColumnSpacer: View {
    let width: CGFloat

    var body: some View {
        Color.clear.frame(width: width, height: Space.s2).accessibilityHidden(true)
    }
}
