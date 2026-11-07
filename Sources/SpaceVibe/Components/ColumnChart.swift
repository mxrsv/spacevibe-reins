import SwiftUI

/// `Column chart` (V5-R58): one bar per bucket, oldest first, up to 72 high and 2 apart with top corners of 2, in neutral
/// `fg3`; the current bucket (and a hovered one) in `fg`; an empty bucket as a 2 pt `hair2` line; a `hair2` base line; and
/// under it an axis of 11 pt labels (the first bucket, what is counted and over what range, the last). Heights are shares of
/// the largest bucket, so the page passes the engine's values unscaled.
struct ColumnChart: View {
    struct Bucket: Identifiable {
        let id: Int
        let value: Double
        /// The bucket's tooltip: "3 days ago: $1.20".
        let label: String
    }

    let buckets: [Bucket]
    /// The bucket drawn bright (today), if any.
    var currentIndex: Int?
    /// Two or three labels, spread across the width.
    let axis: [String]
    /// What VoiceOver reads for the chart: "Estimated cost per day, last 14 days".
    let summary: String

    var body: some View {
        let largest = buckets.map(\.value).max() ?? 0
        VStack(alignment: .leading, spacing: Metrics.ColumnChart.axisAbove) {
            HStack(alignment: .bottom, spacing: Metrics.ColumnChart.spacing) {
                ForEach(buckets) { bucket in
                    BucketBar(share: largest > 0 ? bucket.value / largest : 0, isCurrent: bucket.id == currentIndex, label: bucket.label)
                }
            }
            .frame(height: Metrics.ColumnChart.height - Metrics.Radius.edge, alignment: .bottom)
            .padding(.bottom, Metrics.Radius.edge)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair2).frame(height: Metrics.Radius.edge) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            HStack(spacing: 0) {
                ForEach(Array(axis.enumerated()), id: \.offset) { offset, label in
                    if offset > 0 { Spacer(minLength: Metrics.Stats.spacing) }
                    Text(label).spaceVibeText(.small, tone: .tertiary).lineLimit(1).lineBox(.small)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private struct BucketBar: View {
        let share: Double
        let isCurrent: Bool
        let label: String

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if share > 0 {
                        UnevenRoundedRectangle(topLeadingRadius: Metrics.ColumnChart.barRadius, topTrailingRadius: Metrics.ColumnChart.barRadius,
                                               style: Metrics.Radius.cornerStyle)
                            .fill(isCurrent || hovering ? Palette.fg : Palette.fg3)
                            .frame(height: (proxy.size.height * share).rounded())
                    } else {
                        Rectangle().fill(Palette.hair2).frame(height: Metrics.ColumnChart.emptyHeight)
                    }
                }
            }
            .frame(minWidth: Metrics.ColumnChart.barMinWidth, maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovering)
            .help(label)
        }
    }
}
