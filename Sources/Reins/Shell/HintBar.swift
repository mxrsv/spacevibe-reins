import SwiftUI

/// The strip at the bottom: `⌘K` and `Esc` are always there, the active tab adds its own hints between them.
struct HintBar: View {
    let hints: [KeyHint]

    var body: some View {
        let all = [KeyHint(keys: "\u{2318}K", label: "Search or run")] + hints + [KeyHint(keys: "Esc", label: "Close")]
        HStack(spacing: 18) {
            ForEach(all, id: \.self) { hint in
                HStack(spacing: 6) {
                    Kbd(hint.keys)
                    Text(hint.label)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hint.keys), \(hint.label)")
            }
            Spacer(minLength: 0)
        }
        .font(ReinsFont.small)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Metrics.pagePadding)
        .frame(height: Metrics.hintBarHeight)
        .frame(maxWidth: .infinity)
        .background(Palette.sidebar)
        .overlay(alignment: .top) { Hairline() }
    }
}
