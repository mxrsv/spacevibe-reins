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
/// hints. A hint's keys are split at spaces into one cap each ("J K" draws two caps). Every hint stays on one line: in a
/// narrow window the data source goes first, then the last hints, rather than a label wrapping or being cut mid-word
/// (V5-A22; the keys are still named to VoiceOver).
struct StatusBar: View {
    let hints: [KeyHint]
    var source: String?

    var body: some View {
        StatusBarLayout(spacing: Metrics.ContentPanel.statusBarSpacing) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: Metrics.KeyCap.spacing) {
                    ForEach(Array(hint.keys.split(separator: " ").enumerated()), id: \.offset) { _, key in KeyCap(String(key)) }
                    Text(hint.label).lineLimit(1).fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hint.keys), \(hint.label)")
            }
            if let source { Text(source).lineLimit(1).fixedSize().layoutValue(key: StatusBarSource.self, value: true) }
        }
        .spaceVibeText(.meta, tone: .tertiary)
        .padding(.horizontal, Metrics.ContentPanel.statusBarPadding)
        .frame(height: Metrics.ContentPanel.statusBarHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: Metrics.Radius.edge).accessibilityHidden(true) }
    }
}

private struct StatusBarSource: LayoutValueKey {
    static let defaultValue = false
}

/// The hints left to right at their own width, the source at the right end. A hint that does not fit is placed outside the
/// bar (the bar clips it), and so is the source when it would come closer than `spacing` to the last hint shown.
private struct StatusBarLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let away = CGPoint(x: bounds.maxX + 1000, y: bounds.midY)
        var x = bounds.minX
        var room = true
        for subview in subviews where !subview[StatusBarSource.self] {
            let size = subview.sizeThatFits(.unspecified)
            if room && x + size.width <= bounds.maxX {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            } else {
                room = false
                subview.place(at: away, anchor: .leading, proposal: ProposedViewSize(size))
            }
        }
        for subview in subviews where subview[StatusBarSource.self] {
            let size = subview.sizeThatFits(.unspecified)
            if room && bounds.maxX - size.width >= x {
                subview.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(size))
            } else {
                subview.place(at: away, anchor: .leading, proposal: ProposedViewSize(size))
            }
        }
    }
}
