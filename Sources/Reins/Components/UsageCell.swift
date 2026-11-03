import ReinsCore
import SwiftUI

/// One CLI's usage evidence for one row. The five states look different from each other on purpose
/// (see `UsageCellModel`). Fixed width so the two CLI columns line up down a list.
struct UsageCell: View {
    let cli: InventoryCLI
    let model: UsageCellModel
    /// Largest run count among the compared rows; scales the bar.
    var max: Int = 1
    /// For `.missing`: shows an "Add to <CLI>" button. Without it the cell says "not installed".
    var onAdd: (() -> Void)?

    var body: some View {
        content
            .frame(width: Metrics.usageCellWidth, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch model {
        case .missing:
            if let onAdd {
                Button(action: onAdd) {
                    HStack(spacing: Space.s4) {
                        ReinsIcon(.add)
                        Text("Add to \(cli.label)")
                    }
                }
                .buttonStyle(.reins(.ghost))
            } else {
                Text("not installed")
                    .reinsText(.body, tone: .tertiary)
                    .accessibilityLabel("\(cli.label): not installed")
            }
        case .pending(let reason):
            HStack(spacing: Metrics.rowSpacing) {
                Ruler(share: nil, fill: cli.fill)
                Text("\u{00B7}\u{00B7}\u{00B7}")
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: Metrics.usageNumberWidth, alignment: .trailing)
            }
            .help(reason ?? "Not counted yet")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cli.label): not counted yet")
            .accessibilityHint(reason ?? "")
        case .unmeasurable(let reason):
            HStack(spacing: Space.s6) {
                ReinsIcon(.warning)
                Text("not measurable")
            }
            .reinsText(.body, tone: .tertiary)
            .help(reason)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cli.label): not measurable")
            .accessibilityHint(reason)
        case .counted(let runs):
            HStack(spacing: Metrics.rowSpacing) {
                Ruler(share: UsageCellModel.barFraction(runs: runs, max: max), fill: cli.fill)
                Text(runs.formatted(.number.locale(Locale(identifier: "en_US"))))
                    .font(runs == 0 ? ReinsType.numberStrong.font : ReinsType.number.font)
                    .foregroundStyle(runs == 0 ? Palette.dangerInk : Palette.text)
                    .frame(width: Metrics.usageNumberWidth, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(runs == 0 ? "\(cli.label): never ran" : "\(cli.label): \(runs) runs")
        }
    }
}
