import SwiftUI

/// The collapsed glance widget's ground (spec `docs/specs/2026-11-19-session-glance-widget.md`, GW14, GW20): a capsule on
/// `bgPop` with the `hair2` edge, holding its parts in a row or, on a left or right edge middle, in a column. The window
/// around it draws the drop shadow, so the capsule adds none and the window stays exactly its size. `isStale` fades the
/// parts (not the ground) while they show the last read of a feed that has failed.
struct GlanceCapsule<Content: View>: View {
    let axis: GlanceAxis
    var isStale = false
    @ViewBuilder var content: Content

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: Metrics.Glance.entrySpacing))
            : AnyLayout(VStackLayout(spacing: Metrics.Glance.entrySpacing))
        layout { content }
            .opacity(isStale ? Metrics.Glance.staleOpacity : 1)
            .padding(Metrics.Glance.stripPadding)
            .blockSurface(Palette.bgPop, edge: Palette.hair2, radius: Metrics.Glance.stripRadius)
            .fixedSize()
    }
}

/// One live session in the strip (GW3, GW20 form A): the state glyph, then the CLI logo, in a capsule that fills on hover.
/// The whole capsule takes the click.
struct GlanceEntryButton: View {
    let state: GlanceState
    let cli: CLIID
    let axis: GlanceAxis
    /// False while the widget is not on screen: the working ring stops.
    var isAnimating = true
    /// What VoiceOver reads: the CLI, the title and the state.
    let accessibilityName: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: Metrics.Glance.entryInnerSpacing))
            : AnyLayout(VStackLayout(spacing: Metrics.Glance.entryInnerSpacing))
        Button(action: action) {
            layout {
                SessionStateGlyph(state: state, isAnimating: isAnimating)
                // `CLIMark` is the only file that may draw an image (`IconPolicyTests`); its smallest bare size is 14, the mock's 12.
                CLIMark(cli, size: .glyph)
            }
            .padding(axis == .horizontal ? .horizontal : .vertical, Metrics.Glance.entryPadding)
            .frame(minWidth: Metrics.Glance.entrySide, minHeight: Metrics.Glance.entrySide)
            .background(Capsule().fill(hovering ? Palette.sel : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovering)
        .accessibilityLabel(accessibilityName)
    }
}

/// `+N` after the sixth entry (GW12): quiet, tabular, never a control (hovering the strip already lists every session). Its
/// padding runs along the strip, so a column keeps the entries' width.
struct GlanceOverflowCount: View {
    let text: String
    let axis: GlanceAxis
    let accessibilityName: String

    var body: some View {
        Text(text)
            .spaceVibeText(.smallLabel, tone: .secondary)
            .lineBox(.smallLabel)
            .padding(axis == .horizontal ? .horizontal : .vertical, Metrics.Glance.overflowPadding)
            .frame(minWidth: Metrics.Glance.entrySide, minHeight: Metrics.Glance.entrySide)
            .accessibilityLabel(accessibilityName)
    }
}

/// The strip with no live session (GW11, GW-R4): the glyph of the SpaceVibe mark (`Resources/AppIcon.svg`) without its dark
/// square, in the text ink and faint, as the mock draws it. The parts are flattened before the fade, so where the bars
/// cross the ring the glyph is not darker.
struct GlanceEmptyMark: View {
    let accessibilityName: String

    var body: some View {
        ZStack {
            ForEach(MarkPart.allCases, id: \.self) { part in
                MarkShape(part: part, scale: MarkShape.glyphScale).fill(Palette.fg)
            }
        }
        .frame(width: Metrics.Glance.markSize, height: Metrics.Glance.markSize)
        .compositingGroup()
        .opacity(Metrics.Glance.markOpacity)
        .padding(Metrics.Glance.markPadding)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
    }
}
