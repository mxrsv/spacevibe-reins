import SwiftUI

/// The first line inside a card: the group's name in `title` with its count, an optional muted detail, and column labels
/// over the cells below ("● Claude Code", "● Codex"). 56 pt high on the card's own surface with no line under it, so the
/// card reads as one block and the name is the one thing in it at 16 pt. `lead` sits in the rows' lead slot (usually a
/// `CLIDot`).
struct CardHeader<Lead: View, Columns: View>: View {
    let title: String
    var count: Int?
    var detail: String?
    let lead: Lead
    let columns: Columns

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            Color.clear
                .frame(width: Metrics.rowLeadWidth, height: 1)
                .overlay { lead.fixedSize() }
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                Text(title).spaceVibeText(.title, tone: .primary).lineLimit(1)
                // "3 sessions" reads as one unit.
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    if let count { Count(count) }
                    if let detail { Text(detail).spaceVibeText(.caption, tone: .tertiary).lineLimit(1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            columns.spaceVibeText(.caption, tone: .tertiary)
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .frame(height: Metrics.cardHeaderHeight)
        .background(Palette.surface)
        .accessibilityElement(children: .contain)
        .groupedListPart(.header)
    }
}

extension CardHeader where Lead == EmptyView, Columns == EmptyView {
    init(_ title: String, count: Int? = nil, detail: String? = nil) {
        self.init(title: title, count: count, detail: detail, lead: EmptyView(), columns: EmptyView())
    }
}

extension CardHeader {
    init(_ title: String, count: Int? = nil, detail: String? = nil, @ViewBuilder lead: () -> Lead, @ViewBuilder columns: () -> Columns) {
        self.init(title: title, count: count, detail: detail, lead: lead(), columns: columns())
    }
}

extension CardHeader where Lead == EmptyView {
    init(_ title: String, count: Int? = nil, detail: String? = nil, @ViewBuilder columns: () -> Columns) {
        self.init(title: title, count: count, detail: detail, lead: EmptyView(), columns: columns())
    }
}

extension CardHeader where Columns == EmptyView {
    init(_ title: String, count: Int? = nil, detail: String? = nil, @ViewBuilder lead: () -> Lead) {
        self.init(title: title, count: count, detail: detail, lead: lead(), columns: EmptyView())
    }
}
