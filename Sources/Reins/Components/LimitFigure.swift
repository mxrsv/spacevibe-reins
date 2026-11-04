import SwiftUI

/// How close a window is to its limit. Tints the ruler, the figure and the sidebar tile: low at 20% left, out at 5%.
enum LimitTone: Equatable {
    case normal, low, out

    var barFill: Color? {
        switch self {
        case .normal: nil
        case .low: Palette.warn
        case .out: Palette.danger
        }
    }

    var tint: Color? {
        switch self {
        case .normal: nil
        case .low: Palette.warnTint
        case .out: Palette.dangerTint
        }
    }

    var figureTone: TextTone {
        switch self {
        case .normal: .primary
        case .low: .warn
        case .out: .danger
        }
    }
}

/// The share left of the window the Limits page shows: the `display` number with "left" after it, in the warn or danger
/// ink when nearly out. A share that is not known (its reset has passed) reads "unknown" on the same line box.
struct LimitFigure: View {
    /// Whole percent left; nil when not known.
    let left: Int?
    var tone: LimitTone = .normal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
            if let left {
                Text("\(left)%").reinsText(.display, tone: tone.figureTone).lineLimit(1)
                Text("left").reinsText(.title, tone: .secondary)
            } else {
                Text("unknown").reinsText(.title, tone: .secondary)
            }
        }
        .frame(minHeight: ReinsType.display.lineBox, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
