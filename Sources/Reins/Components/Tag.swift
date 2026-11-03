import SwiftUI

enum TagTone {
    case neutral, danger, warn, success, claude, codex

    var background: Color {
        switch self {
        case .neutral: Palette.surfaceRaised
        case .danger: Palette.dangerTint
        case .warn: Palette.warnTint
        case .success: Palette.successTint
        case .claude: Palette.claudeTint
        case .codex: Palette.codexTint
        }
    }

    var foreground: Color {
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

/// A small status label next to a title: "plugin: neon", "17 errors", "running". 20 pt high, `label` type, radius 4.
/// Tone marks state: neutral is a fact, success is live or done (with a dot), warn needs a look, danger is broken; the CLI
/// tones mark identity only (`CLITag`).
struct Tag: View {
    let text: String
    var tone: TagTone = .neutral
    var systemImage: String?

    init(_ text: String, tone: TagTone = .neutral, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            if tone == .success {
                Circle().fill(tone.foreground).frame(width: Space.s6, height: Space.s6).accessibilityHidden(true)
            }
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
            }
            Text(text)
        }
        .reinsText(.label)
        .lineLimit(1)
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, Space.s8)
        .frame(height: Metrics.tagHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.tagRadius, style: .continuous).fill(tone.background))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
