import SwiftUI

/// One CLI's usage evidence for one row. The five states look different from each other on purpose
/// (see `UsageCellModel`). Fixed width so the two CLI columns line up down a list.
struct UsageCell: View {
    let cli: CLIKind
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
                Button("Add to \(cli.label)", action: onAdd)
                    .buttonStyle(.reins(.dashed))
            } else {
                Text("not installed")
                    .font(ReinsFont.body)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel("\(cli.label): not installed")
            }
        case .pending(let reason):
            HStack(spacing: 10) {
                Capsule()
                    .strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(height: Metrics.barHeight)
                Text("\u{00B7}\u{00B7}\u{00B7}")
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: Metrics.usageNumberWidth, alignment: .trailing)
            }
            .help(reason ?? "Not counted yet")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cli.label): not counted yet")
            .accessibilityHint(reason ?? "")
        case .unmeasurable(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").imageScale(.small)
                Text("not measurable")
            }
            .font(ReinsFont.body)
            .foregroundStyle(Palette.textTertiary)
            .help(reason)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cli.label): not measurable")
            .accessibilityHint(reason)
        case .counted(let runs):
            HStack(spacing: 10) {
                UsageBar(fraction: UsageCellModel.barFraction(runs: runs, max: max), fill: cli.fill)
                Text(runs.formatted(.number.locale(Locale(identifier: "en_US"))))
                    .font(runs == 0 ? ReinsFont.bodyStrong : ReinsFont.body)
                    .foregroundStyle(runs == 0 ? Palette.dangerInk : Palette.text)
                    .frame(width: Metrics.usageNumberWidth, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(runs == 0 ? "\(cli.label): never ran" : "\(cli.label): \(runs) runs")
        }
    }
}

/// A 6 pt capsule track with a fill from the leading edge.
struct UsageBar: View {
    let fraction: Double
    let fill: Color

    var body: some View {
        Capsule()
            .fill(Palette.track)
            .frame(height: Metrics.barHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(fill).frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
    }
}
