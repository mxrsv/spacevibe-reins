import SwiftUI

/// The reset countdown's mark (spec `docs/specs/2026-11-19-limit-reset-countdown.md`, LC10, LC-R5, LC-R6): the CLI logo inside
/// a ring that drains over the countdown's lead. The ring takes the window's tone (LC9) on the faint `fg4` track. Still: it
/// moves only when the controller draws it again, once a second (LC7, GW-R11). Decorative: the pill or row says it in words.
struct GlanceCountdownRing: View {
    let cli: CLIID
    /// What is left of the lead, 1 at the start and 0 at the reset.
    let share: Double
    let tone: BarTone

    var body: some View {
        let inset = Metrics.Glance.ringStroke / 2
        ZStack {
            Circle().inset(by: inset).stroke(Palette.fg4, lineWidth: Metrics.Glance.ringStroke)
            Circle().inset(by: inset)
                .trim(from: 0, to: min(1, max(0, share)))
                .stroke(tone.fill, style: StrokeStyle(lineWidth: Metrics.Glance.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CLIMark(cli, size: .ring)
        }
        .frame(width: Metrics.Glance.ringSide, height: Metrics.Glance.ringSide)
        .accessibilityHidden(true)
    }
}

/// The countdown pill beside the strip (LC10, LC-R5): the ring, the clock in the window's tone, then `5h` or `Week`. In a
/// column (a left or right edge middle) it is as wide as the strip, the label is dropped and the clock stacks one part per
/// line (`23 / 12 / 05`). Same ground and edge as the strip; it fills on hover, and the whole pill takes the click.
struct GlanceCountdownPill: View {
    let cli: CLIID
    let share: Double
    let ringTone: BarTone
    /// "42:17", "23:12:05".
    let clock: String
    let clockTone: TextTone
    /// "5h", "Week"; not drawn in a column.
    let label: String
    let axis: GlanceAxis
    /// What VoiceOver reads: the CLI, the window and the time left.
    let accessibilityName: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        Button(action: action) {
            content
                .background(shape.fill(hovering ? Palette.sel : Color.clear))
                .blockSurface(Palette.bgPop, edge: Palette.hair2, radius: Metrics.Glance.stripRadius)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovering)
        .accessibilityLabel(accessibilityName)
    }

    @ViewBuilder
    private var content: some View {
        let ring = GlanceCountdownRing(cli: cli, share: share, tone: ringTone)
        switch axis {
        case .horizontal:
            HStack(spacing: Metrics.Glance.pillSpacing) {
                ring
                Text(clock).spaceVibeText(.metaLabel, tone: clockTone).lineLimit(1).lineBox(.metaLabel)
                Text(label).spaceVibeText(.small, tone: .tertiary).lineLimit(1).lineBox(.small)
            }
            .padding(Metrics.Glance.pillPadding)
        case .vertical:
            VStack(spacing: Metrics.Glance.pillColumnSpacing) {
                ring
                VStack(spacing: 0) {
                    ForEach(Array(clock.split(separator: ":").enumerated()), id: \.offset) { _, part in
                        Text(String(part)).spaceVibeText(.smallLabel, tone: clockTone).lineLimit(1).lineBox(.smallLabel)
                    }
                }
            }
            .padding(Metrics.Glance.pillColumnPadding)
        }
    }
}

/// The hover list's Limits group (LC-R6): every counting window on a background step, kept under the session rows so it stays
/// in view while they scroll.
struct GlanceLimitsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, Metrics.Glance.limitsWellPadding)
            .background(RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle).fill(Palette.hover))
            .padding(.top, Metrics.Glance.limitsGroupGap)
            .accessibilityElement(children: .contain)
    }
}

/// One counting window in the Limits group (LC-R6): the ring around the CLI logo, the window's name with its clock on the
/// right, and under them the CLI with the reset's clock time ("Claude Code · resets at 21:12"). It fills on hover; the whole
/// row takes the click.
struct GlanceLimitRow: View {
    let cli: CLIID
    let share: Double
    let ringTone: BarTone
    /// "5-hour", "Weekly".
    let name: String
    let clock: String
    let clockTone: TextTone
    let detail: String
    let accessibilityName: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            HStack(spacing: Metrics.Glance.rowColumnSpacing) {
                GlanceCountdownRing(cli: cli, share: share, tone: ringTone)
                VStack(alignment: .leading, spacing: Metrics.Glance.rowLineSpacing) {
                    HStack(spacing: Metrics.Glance.rowColumnSpacing) {
                        Text(name).spaceVibeText(.metaLabel, tone: .primary).lineLimit(1).lineBox(.metaLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(clock).spaceVibeText(.metaLabel, tone: clockTone).lineLimit(1).lineBox(.metaLabel).fixedSize()
                    }
                    Text(detail).spaceVibeText(.small, tone: .tertiary).lineLimit(1).truncationMode(.tail).lineBox(.small)
                }
            }
            .padding(Metrics.Glance.limitRowPadding)
            .background(shape.fill(hovering ? Palette.sel : Color.clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(detail)
        .accessibilityAddTraits(.isButton)
    }
}
