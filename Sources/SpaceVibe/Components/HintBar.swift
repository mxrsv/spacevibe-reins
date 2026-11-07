import SwiftUI

/// The strip at the bottom: `⌘K` and `Esc` are always there, the active tab adds its own hints between them. 32 pt on the
/// well, with no line above it. Settings shows only its own hints (`shellKeys: false`).
struct HintBar: View {
    let hints: [KeyHint]
    var shellKeys = true

    var body: some View {
        let all = shellKeys ? [KeyHint(keys: "\u{2318}K", label: "Search or run")] + hints + [KeyHint(keys: "Esc", label: "Close")] : hints
        HStack(spacing: Space.s16) {
            ForEach(all, id: \.self) { hint in
                HStack(spacing: Space.s6) {
                    Kbd(hint.keys)
                    Text(hint.label)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hint.keys), \(hint.label)")
            }
            Spacer(minLength: 0)
        }
        .spaceVibeText(.caption, tone: .tertiary)
        .padding(.horizontal, Metrics.pagePadding)
        .frame(height: Metrics.hintBarHeight)
        .frame(maxWidth: .infinity)
        .background(Palette.well)
    }
}
