import ReinsCore
import SwiftUI

/// How close a window is to its limit. Tints the lead tile and the ruler: low at 20% left, out at 5%.
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

/// What a window tile reads out: the share left, or nothing known once its reset has passed.
enum LimitReading: Equatable {
    case share(left: Int, tone: LimitTone)
    case unknown
}

struct LimitTileTag: Equatable {
    let text: String
    var tone: TagTone = .neutral
    var icon: ReinsGlyph?
}

/// One usage-limit window as its own block, not a row in a list: a clock square, the window's name with its tags and the
/// reset line, the share left on the right, and a ruler the full width below. A CLI card holds one tile per window.
///
/// `isLead` marks the window that decides how much is usable: it is tinted (the CLI's colour, or warn or danger when
/// nearly out) and shows the share in `figure`. The others sit on `surfaceRaised` with the share in `title`.
/// No border and no divider: the fill and the space around it separate the tiles.
struct LimitTile: View {
    let cli: LimitsCLI
    let title: String
    let detail: String
    var tags: [LimitTileTag] = []
    let reading: LimitReading
    var isLead = false

    private var tone: LimitTone {
        if case .share(_, let tone) = reading { return tone }
        return .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(spacing: Space.s12) {
                ReinsIcon(.clock, size: .row)
                    .frame(width: Metrics.limitTileIconSize, height: Metrics.limitTileIconSize)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.surface))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s8) {
                        Text(title).reinsText(.title, tone: .primary).lineLimit(1)
                        ForEach(tags, id: \.text) { Tag($0.text, tone: $0.tone, icon: $0.icon) }
                    }
                    Text(detail).reinsText(.body, tone: .secondary).lineLimit(2)
                }
                Spacer(minLength: Space.s8)
                figure
            }
            Ruler(share: fraction, fill: tone.barFill ?? cli.fill)
        }
        .padding(Space.s16)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(background))
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double? {
        if case .share(let left, _) = reading { return Double(left) / 100 }
        return nil
    }

    private var background: Color {
        guard isLead else { return Palette.surfaceRaised }
        return tone.tint ?? cli.tint
    }

    @ViewBuilder
    private var figure: some View {
        switch reading {
        case .share(let left, let tone):
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(left)%").reinsText(isLead ? .figure : .title, tone: tone.figureTone)
                Text("left").reinsText(.caption, tone: .secondary)
            }
        case .unknown:
            Text("unknown").reinsText(.title, tone: .secondary)
        }
    }
}
