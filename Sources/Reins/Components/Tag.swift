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

/// A small status label next to a title: "never ran", "plugin: neon", "17 errors". Colour marks state only.
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
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
            }
            Text(text)
        }
        .font(ReinsFont.tiny)
        .lineLimit(1)
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: Metrics.tagRadius, style: .continuous).fill(tone.background))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
