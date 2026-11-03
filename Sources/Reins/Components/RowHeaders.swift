import ReinsCore
import SwiftUI

/// Column labels with no group name, for a card whose header is only labels. Prefer `CardHeader`, which carries the name;
/// this goes once the last screen moves to it (design-language plan T6).
struct HeadRow<Columns: View>: View {
    let title: String
    let columns: Columns

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            Color.clear.frame(width: Metrics.rowLeadWidth, height: 1)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            columns
        }
        .reinsText(.caption, tone: .tertiary)
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .frame(height: Metrics.cardHeaderHeight)
        .background(Palette.surface)
        .accessibilityElement(children: .contain)
        .groupedListPart(.header)
    }
}

extension HeadRow {
    init(_ title: String, @ViewBuilder columns: () -> Columns) {
        self.title = title
        self.columns = columns()
    }
}

extension HeadRow where Columns == EmptyView {
    init(_ title: String) {
        self.title = title
        self.columns = EmptyView()
    }
}

/// A sub-group inside one card: "Deny 3", "Ask first 2". 32 pt, no fill and no line under it: the 16 pt of space the card
/// puts before it does the separating.
struct SectionRow: View {
    let title: String
    var count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            Color.clear.frame(width: Metrics.rowLeadWidth, height: 1)
            HStack(spacing: Space.s6) {
                Text(title).reinsText(.captionStrong, tone: .secondary)
                if let count { Count(count) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .frame(height: Metrics.sectionRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .groupedListPart(.section)
    }
}

/// The CLI heading over a usage column: dot and name, as wide as a `UsageCell` so they line up.
struct CLIColumnHead: View {
    let cli: InventoryCLI
    var width: CGFloat = Metrics.usageCellWidth

    init(_ cli: InventoryCLI, width: CGFloat = Metrics.usageCellWidth) {
        self.cli = cli
        self.width = width
    }

    var body: some View {
        HStack(spacing: Space.s6) {
            CLIDot(cli, decorative: true)
            Text(cli.label)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
