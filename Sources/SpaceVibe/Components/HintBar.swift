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

/// The v5 status bar at the foot of the content panel (V5-R35, V5-R51): 32 high with a hairline above, the page's working
/// keys at the left as key caps and the data source at the right ("Counted from local logs"), 12 pt `fg3`, 16 between
/// hints. A hint's keys are split at spaces into one cap each ("J K" draws two caps).
struct StatusBar: View {
    let hints: [KeyHint]
    var source: String?

    var body: some View {
        HStack(spacing: Metrics.ContentPanel.statusBarSpacing) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: Metrics.KeyCap.spacing) {
                    ForEach(Array(hint.keys.split(separator: " ").enumerated()), id: \.offset) { _, key in KeyCap(String(key)) }
                    Text(hint.label)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hint.keys), \(hint.label)")
            }
            Spacer(minLength: 0)
            if let source { Text(source).lineLimit(1) }
        }
        .spaceVibeText(.meta, tone: .tertiary)
        .padding(.horizontal, Metrics.ContentPanel.statusBarPadding)
        .frame(height: Metrics.ContentPanel.statusBarHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: Metrics.Radius.edge).accessibilityHidden(true) }
    }
}
