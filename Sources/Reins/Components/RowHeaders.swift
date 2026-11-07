import SwiftUI

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
