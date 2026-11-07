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

// v5 cells of a `ListRow` (V5-R56). Pages give their widths from `Metrics`; the cells own the look.

/// What a bar's fill says: neutral (`fg2`), or the state when little is left (the page decides; Limits by `LimitTone`).
enum BarTone {
    case neutral, warn, danger

    var fill: Color {
        switch self {
        case .neutral: Palette.fg2
        case .warn: Palette.warn
        case .danger: Palette.bad
        }
    }
}

/// A share as a bar 8 high with round ends on the `track`, filling the width it is given; an unknown share (nil) is a 1 pt
/// dashed `hair2` line instead, never an empty bar (V5-R74: "It is not 0%"). Decorative: the share cell beside it says the
/// number.
struct BarCell: View {
    /// 0 to 1, or nil when unknown.
    let share: Double?
    var tone: BarTone = .neutral

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let share {
                let fraction = min(max(share, 0), 1)
                Capsule()
                    .fill(Palette.track)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(tone.fill)
                                .frame(width: proxy.size.width * fraction)
                                .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.barWidth), value: fraction)
                        }
                    }
                    .clipShape(Capsule())
            } else {
                Line()
                    .stroke(Palette.hair2, style: StrokeStyle(lineWidth: Metrics.Radius.edge, dash: Metrics.Bar.unknownDash))
                    .frame(height: Metrics.Radius.edge)
            }
        }
        .frame(height: Metrics.Bar.height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// The share left in a row (20/28 600), right-aligned in its 64 column, or "—" when it is not known.
struct ShareCell: View {
    let percent: Int?

    var body: some View {
        Text(percent.map { "\($0)%" } ?? "\u{2014}")
            .reinsText(.heading, tone: .primary)
            .lineLimit(1)
            .frame(width: Metrics.ListRow.shareWidth, alignment: .trailing)
            .accessibilityLabel(percent.map { "\($0)% left" } ?? "Not known")
    }
}

/// A count in a row (13, `fg2`), right-aligned in the width the page gives: "12 sessions", "3 times", "41 edits".
struct CountCell: View {
    let text: String
    var width: CGFloat?

    var body: some View {
        Text(text)
            .reinsText(.prose, tone: .secondary)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

/// A row's secondary text (12, `fg3`) in the width the page gives: a matcher, a project, an event and the reason.
struct MetaCell: View {
    let text: String
    var width: CGFloat?
    var alignment: Alignment = .trailing

    var body: some View {
        Text(text)
            .reinsText(.meta, tone: .tertiary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}
