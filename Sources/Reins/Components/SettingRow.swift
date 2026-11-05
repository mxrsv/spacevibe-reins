import SwiftUI

/// Children side by side, wrapping onto the next line when they do not fit: the agent card's buttons, the Model panel's
/// chips. `spacing` between children and between lines.
struct FlowRow: Layout {
    var spacing: CGFloat = Space.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var rows: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if needed > width, !line.indices.isEmpty {
                rows.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty { rows.append(line) }
        return rows
    }
}

/// One setting inside a panel card (mock C′, `.row.stack`): its name in `rowTitle`, the config key beside it in `code`,
/// the control under them at full width, and an optional note: a description in the tertiary tone, or the consequence of
/// a risky value in the warn ink. 12 pt above and below, inset like every row.
struct SettingRow<Control: View>: View {
    let title: String
    var key: String?
    var note: String?
    var warn = false
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                Text(title).reinsText(.rowTitle, tone: .primary)
                if let key { Text(key).reinsText(.code, tone: .tertiary).lineLimit(1).truncationMode(.middle) }
                Spacer(minLength: 0)
            }
            control
            if let note {
                Text(note).reinsText(.caption, tone: warn ? .warn : .tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupedListPart(.plain)
    }
}

/// An inline row of fields and controls inside a panel card (the add rows): inset like a row, 8 pt under it.
struct FormRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) { content }
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.bottom, Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .groupedListPart(.plain)
    }
}
