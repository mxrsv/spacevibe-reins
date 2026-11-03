import ReinsCore
import SwiftUI

/// One CLI in the sidebar's Limits block: its mark, name and the share left of its tightest window, with a ruler under
/// them. Filled with the CLI's tint, or warn or danger when nearly out. A CLI with no reading is `muted` (plain surface,
/// the reason in `caption` under the name instead of a number, no bar).
struct LimitSidebarTile: View {
    let cli: LimitsCLI
    let name: String
    let value: String
    var tone: LimitTone = .normal
    /// The ruler's fill, 0...1; nil draws no ruler.
    var fraction: Double?
    var isMuted = false

    var body: some View {
        Group {
            if isMuted {
                HStack(spacing: Space.s8) {
                    CLIMark(cli, small: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).reinsText(.body, tone: .secondary).lineLimit(1)
                        Text(value).reinsText(.caption, tone: .secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: Space.s8) {
                    HStack(spacing: Space.s8) {
                        CLIMark(cli, small: true)
                        Text(name).reinsText(.bodyStrong, tone: .primary).lineLimit(1).layoutPriority(1)
                        Spacer(minLength: Space.s4)
                        Text(value).reinsText(.bodyStrong, tone: tone.figureTone).lineLimit(1)
                    }
                    if let fraction {
                        Ruler(share: fraction, fill: tone.barFill ?? cli.fill)
                    }
                }
            }
        }
        .padding(Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(background))
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        if isMuted { return Palette.surface }
        return tone.tint ?? cli.tint
    }
}

/// A warn clock beside the block's title: at least one CLI's reading is older than six hours.
struct StaleMark: View {
    var body: some View {
        ReinsIcon(.clock, ink: Palette.warnInk, label: "A reading is old")
    }
}
