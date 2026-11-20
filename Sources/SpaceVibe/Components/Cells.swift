import SwiftUI

// v5 cells of a `ListRow` (V5-R56). Pages give their widths from `Metrics`; the cells own the look.

/// What a bar's fill says: neutral (`fg2`), or the state when little is left (the page decides; Limits by `LimitTone`).
enum BarTone: Equatable {
    case neutral, warn, danger
    /// A CLI's identity (the Skills pane's meters), from `CLIRegistry`: never a state.
    case cli(CLIID)

    var fill: Color {
        switch self {
        case .cli(let cli): cli.identity.tone.bar
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
            .spaceVibeText(.heading, tone: .primary)
            .lineLimit(1)
            .frame(width: Metrics.ListRow.shareWidth, alignment: .trailing)
            .accessibilityLabel(percent.map { "\($0)% left" } ?? "Not known")
    }
}

/// A countdown in a row ("42:17", "23:12:05") in the tone the page gives, in a slot of fixed width that stays empty when
/// nothing counts, so the columns after it never move (Limits, LC-R3).
struct CountdownCell: View {
    let text: String?
    var tone: TextTone = .primary
    var spoken: String?
    let width: CGFloat

    var body: some View {
        Text(text ?? "")
            .spaceVibeText(.metaLabel, tone: tone)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .accessibilityLabel(spoken ?? text ?? "")
            .accessibilityHidden(text == nil)
    }
}

/// A count in a row (13, `fg2`), right-aligned in the width the page gives: "12 sessions", "3 times", "41 edits".
struct CountCell: View {
    let text: String
    var width: CGFloat?
    /// Where the text sits in `width`: the right edge by default, the left for a column that starts at a fixed place (Rules' verdict).
    var alignment: Alignment = .trailing

    var body: some View {
        Text(text)
            .spaceVibeText(.prose, tone: .secondary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

/// A row's secondary text (12, `fg3`) in the width the page gives: a matcher, a project, an event and the reason.
struct MetaCell: View {
    let text: String
    var width: CGFloat?
    var alignment: Alignment = .trailing
    /// A narrow row lets this column give way down to this width (the text then ends in an ellipsis) so the row's name keeps
    /// room; nil keeps the column fixed at `width`.
    var shrinksTo: CGFloat?

    var body: some View {
        let text = Text(text).spaceVibeText(.meta, tone: .tertiary).lineLimit(1)
        if let shrinksTo, let width {
            text.frame(minWidth: shrinksTo, maxWidth: width, alignment: alignment)
        } else {
            text.frame(width: width, alignment: alignment)
        }
    }
}
