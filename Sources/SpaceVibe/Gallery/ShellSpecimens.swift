import SwiftUI

/// The v5 shell blocks in every state of the spec's Components table (sidebar and content panel). Hover and focus are drawn
/// with `.specimen(_:)`. Synthetic names only.
struct ShellSpecimens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            SpecimenLayout.panel("Sidebar: product row, search row (rest, hover, focus), page items (current with its count, hover, focus, rest), CLI status rows (reading, not found, no log, no state), footer (rest, hover, focus)") {
                HStack(alignment: .top, spacing: Space.s24) {
                    sidebar(searchState: [], items: [.current, .hover, .focus], footer: [])
                    sidebar(searchState: .hover, items: [.rest, .focus, .hover], footer: .hover)
                    sidebar(searchState: .focus, items: [.rest, .rest, .rest], footer: .focus)
                }
            }
            SpecimenLayout.panel("Content panel: default (tab head, canvas, status bar with keys and the data source), then filtered (the chip row under the tab head)") {
                HStack(alignment: .top, spacing: Space.s24) {
                    panel(filtered: false)
                    panel(filtered: true)
                }
            }
        }
    }

    private enum ItemState { case rest, hover, focus, current }

    private func sidebar(searchState: SpecimenInteraction, items: [ItemState], footer: SpecimenInteraction) -> some View {
        let titles = ["Agents", "Activity", "Limits"]
        let glyphs: [ContentGlyph] = [.stack, .pulse, .gauge]
        return VStack(alignment: .leading, spacing: 0) {
            SidebarProductRow(name: SpaceVibeMark.productName)
            SidebarSearchRow(keyCap: "\u{2318}K", spokenKey: "Command K") {}
                .specimen(searchState)
                .padding(.top, Metrics.AppSidebar.searchAbove)
                .padding(.bottom, Metrics.AppSidebar.searchBelow)
            VStack(spacing: Metrics.AppSidebar.itemSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, state in
                    SidebarPageItem(title: titles[index], glyph: glyphs[index], count: index == 0 ? 22 : nil, isCurrent: state == .current) {}
                        .specimen(state == .hover ? .hover : (state == .focus ? .focus : []))
                }
            }
            Spacer(minLength: Space.s24)
            SidebarCLIStatusGroup {
                SidebarCLIStatusRow(name: "Claude Code", cli: .claude, state: .reading)
                SidebarCLIStatusRow(name: "Codex", cli: .codex, state: .notFound)
                SidebarCLIStatusRow(name: "Gemini CLI", cli: .gemini, state: .noLog)
                SidebarCLIStatusRow(name: "Claude Code", cli: .claude, state: nil)
            }
            HStack(spacing: Metrics.AppSidebar.itemSpacing) {
                SidebarFooterButton(title: "Settings", glyph: ContentGlyph.sliders) {}.specimen(footer)
                SidebarIconButton(glyph: ContentGlyph.sun, label: "Switch to light theme") {}.specimen(footer)
            }
        }
        .padding(.horizontal, Rhythm.side)
        .padding(.bottom, Rhythm.side)
        .frame(width: Metrics.AppSidebar.width, height: Self.sidebarHeight)
        .background(Palette.bgSide)
    }

    private func panel(filtered: Bool) -> some View {
        ContentPanel(hints: [KeyHint(keys: "J K", label: "move"), KeyHint(keys: "/", label: "filter")], source: "Counted from local logs") {
            VStack(spacing: 0) {
                TabHead {
                    TabChip(title: "Skills", glyph: CategoryGlyph.skill, count: 13, tone: .skill, isActive: true) {}
                    TabChip(title: "Subagents", glyph: CategoryGlyph.subagent, count: 6, tone: .subagent, isActive: false) {}
                } actions: {
                    ToolbarButton("Filter", glyph: .filter) {}
                }
                if filtered {
                    FilterChipRow(onClear: {}) { FilterFieldChip(field: "CLI is", value: "Codex") {} }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: SpecimenLayout.halfCanvas + Metrics.ContentPanel.inset, height: Self.panelHeight)
        .background(Palette.bgSide)
    }

    private static let sidebarHeight: CGFloat = 560
    private static let panelHeight: CGFloat = 260
}
