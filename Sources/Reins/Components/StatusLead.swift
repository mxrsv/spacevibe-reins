import SwiftUI

/// How a `StatusLead` reads: neutral states a fact, success is within safe limits, warn needs a look.
enum StatusTone: Equatable {
    case neutral, success, warn

    var icon: ReinsGlyph {
        switch self {
        case .neutral: .info
        case .success: .check
        case .warn: .warning
        }
    }

    var ink: Color {
        switch self {
        case .neutral: Palette.textSecondary
        case .success: Palette.successInk
        case .warn: Palette.warnInk
        }
    }

    var tint: Color {
        switch self {
        case .neutral: Palette.surfaceRaised
        case .success: Palette.successTint
        case .warn: Palette.warnTint
        }
    }
}

/// One plain sentence that sums up a page, with the settings it rests on under it (Codex on the Rules page: "Runs any
/// command and changes any file without asking"). A `surface` block on the well, radius 12, 16 inside: a 40 pt tile in the
/// tone's tint holding its icon, the sentence in `title` (warn keeps its ink), the detail in `code`. The one tinted lead
/// of its page.
struct StatusLead: View {
    let tone: StatusTone
    let sentence: String
    var detail: String?

    var body: some View {
        HStack(spacing: Space.s16) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(tone.tint)
                ReinsIcon(tone.icon, size: .row, ink: tone.ink)
            }
            .frame(width: Metrics.statusTileSize, height: Metrics.statusTileSize)
            VStack(alignment: .leading, spacing: 0) {
                Text(sentence)
                    .reinsText(.title, tone: tone == .warn ? .warn : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).reinsText(.code, tone: .tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s16)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .combine)
    }
}
