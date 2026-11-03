import SwiftUI

enum TagTone {
    case neutral, danger, warn, success, claude, codex

    /// The 6 pt dot at the leading edge. A neutral tag has none.
    var dot: Color? {
        switch self {
        case .neutral: nil
        case .danger: Palette.danger
        case .warn: Palette.warn
        case .success: Palette.success
        case .claude: Palette.claude
        case .codex: Palette.codex
        }
    }

    /// The text: neutral, except warn and danger, which keep their ink.
    var text: Color {
        switch self {
        case .danger: Palette.dangerInk
        case .warn: Palette.warnInk
        case .neutral, .success, .claude, .codex: Palette.textSecondary
        }
    }

    /// An icon inside the tag takes the tone's ink: the one place besides a banner where an icon is coloured.
    var ink: Color {
        switch self {
        case .neutral: Palette.textSecondary
        case .danger: Palette.dangerInk
        case .warn: Palette.warnInk
        case .success: Palette.successInk
        case .claude: Palette.claudeInk
        case .codex: Palette.codexInk
        }
    }
}

/// A small status label next to a title: "plugin: neon", "17 errors", "running". 24 pt high, `label` type, radius 6, on
/// `surfaceRaised` with neutral text. The tone shows as a 6 pt dot in its colour (none when the tag has an icon or no
/// tone); warn and danger also keep their ink for the text. Neutral is a fact, success is live or done, warn needs a look,
/// danger is broken; the CLI tones mark identity only (`CLITag`).
struct Tag: View {
    let text: String
    var tone: TagTone = .neutral
    var icon: ReinsGlyph?

    init(_ text: String, tone: TagTone = .neutral, icon: ReinsGlyph? = nil) {
        self.text = text
        self.tone = tone
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            if let icon {
                ReinsIcon(icon, ink: tone.ink)
            } else if let dot = tone.dot {
                Circle().fill(dot).frame(width: Metrics.tagDotSize, height: Metrics.tagDotSize).accessibilityHidden(true)
            }
            Text(text).foregroundStyle(tone.text)
        }
        .reinsText(.label)
        .lineLimit(1)
        .padding(.horizontal, Space.s8)
        .frame(height: Metrics.tagHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.tagRadius, style: .continuous).fill(Palette.surfaceRaised))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
