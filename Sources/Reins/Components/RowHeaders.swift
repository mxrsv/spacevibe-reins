import SwiftUI

/// The column heading row at the top of a `GroupedList`. `title` sits over the text block; `columns` sit over the cells.
struct HeadRow<Columns: View>: View {
    let title: String
    let columns: Columns

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            Color.clear.frame(width: Metrics.rowLeadWidth, height: 1)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            columns
        }
        .font(ReinsFont.small)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .frame(minHeight: 34)
        .background(Palette.surfaceRaised)
        .accessibilityElement(children: .contain)
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

/// A divider row inside one group: "Skills 6", "Agents 5", "Hooks 1".
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
            HStack(spacing: 8) {
                Text(title).font(ReinsFont.smallStrong).foregroundStyle(Palette.textSecondary)
                if let count { Text("\(count)").font(ReinsFont.small).foregroundStyle(Palette.textTertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .frame(minHeight: 32)
        .background(Palette.surfaceRaised)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The CLI heading over a usage column: dot and name, as wide as a `UsageCell` so they line up.
struct CLIColumnHead: View {
    let cli: CLIKind

    init(_ cli: CLIKind) { self.cli = cli }

    var body: some View {
        HStack(spacing: 6) {
            CLIDot(cli, decorative: true)
            Text(cli.label)
        }
        .frame(width: Metrics.usageCellWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
