import SwiftUI

/// The colour a tab takes while it is active (V5-R11, V5-R20, V5-R69): its category's, or the accent on Activity, whose
/// tabs are not categories.
enum TabTone: CaseIterable {
    case skill, subagent, hook, rule, accent

    /// The chip (26%, 34% focused) and the count circle (40%).
    var fill: Color {
        switch self {
        case .skill: Palette.catSkill
        case .subagent: Palette.catSubagent
        case .hook: Palette.catHook
        case .rule: Palette.catRule
        case .accent: Palette.accent
        }
    }

    /// The glyph and the label (600) on the active chip.
    var ink: Color {
        switch self {
        case .skill: Palette.catSkillInk
        case .subagent: Palette.catSubagentInk
        case .hook: Palette.catHookInk
        case .rule: Palette.catRuleInk
        case .accent: Palette.accentInk
        }
    }

    /// The count on the active chip's circle.
    var countInk: Color {
        switch self {
        case .skill: Palette.catSkillCountInk
        case .subagent: Palette.catSubagentCountInk
        case .hook: Palette.catHookCountInk
        case .rule: Palette.catRuleCountInk
        case .accent: Palette.accentCountInk
        }
    }
}

/// One tab of a tab head (V5-R20): a chip 36 high, padding 0 14, radius 6, holding the glyph (16), the label (13, 500) and
/// the count in its circle, 6 apart. No underline, no border, no ring.
///
/// Inactive, it is neutral: the chip `fg` at 7% with label, glyph and count in `fg2`; hovered or focused the chip is 12% and
/// the three turn `fg` (the mock keeps the count `fg2`, which reads 3.89:1 on the hovered circle; a named departure). Active,
/// it takes its tone: the chip at 26% (34% focused), the glyph and the label (600) in the tone's ink, the count in its count
/// ink. The mock draws the glyph in the category colour, which reads under 3:1 on the chip in light; a named departure.
struct TabChip: View {
    let title: String
    let glyph: any GlyphSource
    var count: Int?
    let tone: TabTone
    let isActive: Bool
    let action: () -> Void

    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let hovered = hovering || specimen.contains(.hover)
        let isFocused = focused || specimen.contains(.focus)
        let lifted = !isActive && (hovered || isFocused)
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            HStack(spacing: Metrics.TabChip.innerSpacing) {
                SpaceVibeIcon(source: glyph, ink: isActive ? tone.ink : (lifted ? Palette.fg : Palette.fg2))
                Text(title)
                    .spaceVibeText(isActive ? .controlStrong : .control)
                    .foregroundStyle(isActive ? tone.ink : (lifted ? Palette.fg : Palette.fg2))
                    .lineLimit(1)
                if let count {
                    TabCount(count: count, ink: isActive ? tone.countInk : (lifted ? Palette.fg : Palette.fg2),
                             fill: isActive ? tone.fill.opacity(TabChipAlpha.activeCount) : Palette.fg.opacity(TabChipAlpha.count))
                }
            }
            .padding(.horizontal, Metrics.TabChip.padding)
            .frame(height: Metrics.TabChip.height)
            .background(shape.fill(chipFill(lifted: lifted, focused: isFocused)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: lifted)
        .accessibilityLabel(title)
        .accessibilityValue(Self.spokenValue(count: count, isActive: isActive))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func chipFill(lifted: Bool, focused: Bool) -> Color {
        if isActive { return tone.fill.opacity(focused ? TabChipAlpha.activeFocus : TabChipAlpha.active) }
        return Palette.fg.opacity(lifted ? TabChipAlpha.hover : TabChipAlpha.rest)
    }

    /// What VoiceOver reads after the tab's name (V5-R43): "13, selected tab", "6, tab".
    static func spokenValue(count: Int?, isActive: Bool) -> String {
        let role = isActive ? "selected tab" : "tab"
        return count.map { "\($0), \(role)" } ?? role
    }
}

/// A tab's count: 10 pt (500, tabular) in a circle at least 16 x 16, 4 at the sides.
private struct TabCount: View {
    let count: Int
    let ink: Color
    let fill: Color

    var body: some View {
        Text("\(count)")
            .spaceVibeText(.micro)
            .foregroundStyle(ink)
            .padding(.horizontal, Metrics.TabChip.countPadding)
            .frame(minWidth: Metrics.TabChip.countSize, minHeight: Metrics.TabChip.countSize)
            .background(Capsule().fill(fill))
    }
}

/// The tab head at the top of the content panel (V5-R19, V5-R51, V5-R61): 60 high with a `hair` line under it; the tabs
/// from the content edge (32) at the left, 10 apart; the actions (toolbar buttons) at the right, 4 apart, ending 32 from
/// the edge. Limits passes no tabs and one `Refresh`.
struct TabHead<Tabs: View, Actions: View>: View {
    @ViewBuilder var tabs: Tabs
    @ViewBuilder var actions: Actions

    var body: some View {
        // Wide enough for the tabs and the actions with their words: that. Otherwise the buttons keep only their glyphs.
        ViewThatFits(in: .horizontal) {
            row
            row.environment(\.toolbarIconsOnly, true)
        }
        .frame(height: Metrics.ContentPanel.tabHeadHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: Metrics.Radius.edge).accessibilityHidden(true) }
        .zIndex(1)
    }

    private var row: some View {
        HStack(spacing: 0) {
            HStack(spacing: Metrics.TabChip.spacing) { tabs }
                .padding(.leading, Rhythm.edge)
                .padding(.trailing, Metrics.TabChip.tabsTrailing)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Tabs")
            Spacer(minLength: 0)
            HStack(spacing: Metrics.TabChip.actionSpacing) { actions }
                .padding(.trailing, Rhythm.edge)
        }
    }
}
