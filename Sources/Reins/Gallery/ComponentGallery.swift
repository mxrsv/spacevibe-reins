import ReinsCore
import SwiftUI

/// Every shared view in every state. Reach it with `SPACEVIBE_GALLERY=1`; the screenshot mode renders the same content, in two
/// halves (`part`) because one image taller than 16384 px renders blank.
struct ComponentGalleryContent: View {
    enum Part {
        case all, first, second
    }

    var part: Part = .all

    @State private var segment = "ask"
    @State private var file = "shared"
    @State private var scope = "global"
    @State private var chip = "all"
    @State private var rulesCLI = InventoryCLI.claude
    @State private var draft = ""
    @State private var badDraft = "Bash(npm test"
    @FocusState private var draftFocused: Bool
    @FocusState private var badDraftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if part != .second {
                section("Colour tokens") { Swatches() }
                section("Text roles: Inter at 12, 14 and 16, plus figure and display") { TypeRoles() }
                section("Buttons on the well, then inside a card (no outline: surface, then surfaceRaised)") {
                    VStack(alignment: .leading, spacing: Space.s12) {
                        buttons
                        GroupedList { buttons.padding(.horizontal, Metrics.rowHorizontalPadding) }
                    }
                }
                section("Tags inside a card: neutral, with an icon, and a dot per tone; counts, CLI tag and dot, key caps") {
                    GroupedList { tags.padding(.horizontal, Metrics.rowHorizontalPadding) }
                }
                section("Segmented control, filter chips, scope picker, search field: all 28 pt, on the well, then inside a card") {
                    VStack(alignment: .leading, spacing: Space.s12) {
                        controls
                        GroupedList { controls.padding(.horizontal, Metrics.rowHorizontalPadding) }
                    }
                }
                section("CLI switch with brand glyphs, then read-only readouts: neutral, a value that needs a look, and nothing set") {
                    VStack(alignment: .leading, spacing: Space.s12) {
                        SegmentedControl(label: "Rules for", options: [
                            SegmentOption("Claude Code", value: InventoryCLI.claude, cli: .claude),
                            SegmentOption("Codex", value: InventoryCLI.codex, cli: .codex),
                        ], selection: $rulesCLI)
                        GroupedList {
                            HStack(spacing: Rhythm.tools) {
                                SegmentReadout(label: "Sandbox", options: ["Read only", "Workspace", "Full access"], selected: "Workspace")
                                SegmentReadout(label: "Asks before acting", options: ["Unless allowed", "When needed", "Never"], selected: "Never", warn: true)
                                SegmentReadout(label: "Network", options: ["Off", "On"], selected: nil)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Metrics.rowHorizontalPadding)
                        }
                    }
                }
                section("Status lead in each tone, and the bar about the other CLI") {
                    VStack(spacing: Space.s12) {
                        StatusLead(tone: .warn, sentence: "Has no sandbox and never asks, except for 1 command rule", detail: #"sandbox_mode = "danger-full-access" · approval_policy = "never""#)
                        StatusLead(tone: .success, sentence: "Writes only inside the workspace and asks when it needs more", detail: #"sandbox_mode = "workspace-write""#)
                        StatusLead(tone: .neutral, sentence: "Runs on its defaults: there is no ~/.codex/config.toml")
                        CLISummaryBar(cli: .codex, message: "Has no sandbox and never asks, except for 1 command rule", warn: true, actionTitle: "Open Codex") {}
                        CLISummaryBar(cli: .claude, message: "Asks before push and deploy, blocks secrets (.env)", actionTitle: "Open Claude Code") {}
                    }
                }
                section("Text input: normal and invalid") {
                    HStack(spacing: Rhythm.tools) {
                        TextInputField(label: "Rule", placeholder: "Bash(npm test *)", text: $draft, code: true, focused: $draftFocused) {}
                        TextInputField(label: "Rule", placeholder: "Bash(npm test *)", text: $badDraft, code: true, invalid: true, focused: $badDraftFocused) {}
                        Text("Write the rule as Tool(pattern).").reinsText(.caption, tone: .danger)
                        Spacer(minLength: 0)
                    }
                }
                section("Ruler: 0, 4, 39 and 100 percent, not known, low (20% left) and out (5% left)") { RulerSpecimens() }
                section("Icons of the old screens: Solar Bold Duotone at 14, 16, 20 and 22, then the drawn chevrons. Solar by 480 Design, CC BY 4.0") { IconSpecimens() }
                if LaunchMode.uiV5Enabled() {
                    section("Icons of the v5 screens: MingCute Line (category), Phosphor Duotone (sidebar and content) and the verdict glyphs, at 12, 14, 16 and 24, then in the sidebar's tone") { V5IconSpecimens() }
                }
            }
            if part != .first {
                section("Cards, rows and the five usage states") { DemoLoadoutList() }
                section("Rows: the selected one hides the dividers on both sides of it") {
                    GroupedList {
                        CardHeader("Rows", count: 5)
                        Row { RowText("Plain row", subtitle: "Second line in the muted colour") }
                            .lead { ReinsIcon(.skill, size: .row) }
                        Row(selected: true, revealActions: true, onActivate: {}) {
                            RowText("Selected row with actions", subtitle: "Actions stay visible while selected")
                        }
                        .lead { ReinsIcon(.skill, size: .row) }
                        .actions {
                            RowActionButton(title: "Copy to Codex", icon: .copy) {}
                            RowActionButton(title: "Remove", icon: .trash, kind: .danger, iconOnly: true) {}
                        }
                        Row(onActivate: {}) { RowText("Session with a state", subtitle: "spacevibe-bench \u{00B7} just now") }
                            .lead { CLIDot(.codex) }
                            .cells { StateCell { Tag("not measurable", icon: .warning) }; NumberCell(text: "~$148.20") }
                        Row(onActivate: {}) { RowText("A row with nothing to change", subtitle: "Owned by a plugin") }
                            .lead { ReinsIcon(.skill, size: .row) }
                            .cells { FixedCell { Tag("\u{00D7}3") }; NumberCell(text: "~$1.33") }
                            .actions { HStack(spacing: Space.s4) { EmptyActionSlot(); ReadOnlyMark(reason: "Read-only: owned by a plugin") } }
                        Row(tall: true) {
                            VStack(alignment: .leading, spacing: 0) {
                                RowText("pnpm tsc --noEmit", subtitle: "exit 2 \u{00B7} spacevibe-bench \u{00B7} last 1 h ago", mono: true, codeSubtitle: false)
                                Text("lib/leaderboard/rank.ts(41,9): error TS2322").reinsText(.code, tone: .secondary)
                            }
                        }
                        .lead { CLIDot(.claude) }
                        .cells { Tag("\u{00D7}8", tone: .danger) }
                        EmptyRow("Nothing matches this filter.")
                        ShowMoreRow(reveal: 8, hiddenAfter: 12) {}
                    }
                }
                section("Section rows inside one card") {
                    GroupedList {
                        CardHeader("Claude Code rules at Global", count: 4, lead: { CLIDot(.claude, decorative: true) })
                        SectionRow("Deny", count: 2)
                        Row { RowText("Bash(rm -rf:*)", mono: true) { Tag("Deny", tone: .danger) } }
                        Row { RowText("Read(.env*)", mono: true) { Tag("Deny", tone: .danger) } }
                        SectionRow("Allow", count: 2)
                        Row { RowText("Read(*)", mono: true) { Tag("Allow") } }
                        Row { RowText("Bash(git status)", mono: true) { Tag("Allow") } }
                    }
                }
                section("Notes") {
                    NoteRegion(
                        title: "Cannot be measured",
                        columns: [
                            .init(cli: .claude, notes: ["Claude Code does not record permission prompts, so a long tool run and a wait for approval look the same."]),
                            .init(cli: .codex, notes: ["Codex does not log hook runs, so failed hooks are not shown for Codex."]),
                        ],
                        shared: ["Cost is estimated from logged tokens at API prices (API-equivalent), not what you are billed."]
                    )
                }
                section("Inset box and warning, as inside a confirmation") {
                    VStack(alignment: .leading, spacing: Space.s12) {
                        InsetBox {
                            HStack(spacing: Space.s8) { Tag("Deny", tone: .danger); Text("Bash(git push *)").reinsText(.code, tone: .primary) }
                            HStack(spacing: Space.s8) { Tag("Allow"); Text("Bash(vercel *)").reinsText(.code, tone: .primary) }
                        }
                        WarningNote(text: "A rule that stays in this file still wins, so Push and deploy will read Ask, not Allow.")
                    }
                    .frame(maxWidth: Metrics.wideDialogWidth)
                }
                section("Confirmation") {
                    ConfirmationDialog("Stop Fix leaderboard rank tie?", message: "The current turn ends and work already done stays. This cannot be undone.", cancel: {}) {
                        Button("Cancel") {}.buttonStyle(.reins(.normal))
                        Button("Stop") {}.buttonStyle(.reins(.danger))
                    }
                    .frame(height: Metrics.galleryOverlayHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous))
                }
                section("Sidebar items and the command palette") {
                    HStack(alignment: .top, spacing: Space.s24) {
                        VStack(spacing: Metrics.sidebarItemSpacing) {
                            SidebarItem(title: "Loadout", icon: .loadout, count: 22, isActive: true) {}
                            SidebarItem(title: "Rules", icon: .rules, count: 11, isActive: false) {}
                            SidebarItem(title: "Activity", icon: .activity, count: 2, alert: true, isActive: false) {}
                        }
                        .sidebarSurface()
                        .frame(height: Metrics.galleryOverlayHeight)
                        PaletteCard {
                            Text("Search skills, hooks, rules, or run an action").paletteField()
                            Hairline()
                            VStack(alignment: .leading, spacing: 0) {
                                PaletteSectionTitle(title: "Go to")
                                PaletteRow(entry: PaletteEntry(id: "g.loadout", title: "Loadout", icon: .loadout, trailing: "\u{2318}1") {}, isHighlighted: true) {}
                                PaletteRow(entry: PaletteEntry(id: "g.rules", title: "Rules", icon: .rules, trailing: "\u{2318}2") {}, isHighlighted: false) {}
                                PaletteSectionTitle(title: "Skills")
                                PaletteRow(entry: PaletteEntry(id: "s.ponytail", title: "ponytail", subtitle: "Pick the laziest solution", icon: .skill) {}, isHighlighted: false) {}
                                PaletteEmptyRow(text: "No matches")
                            }
                            .paletteList()
                            Hairline()
                            PaletteFooter {
                                PaletteHint(text: "navigate") { ReinsIcon(.navigate, size: .inline) }
                                PaletteHint(text: "close") { Kbd("Esc") }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                section("Limits: share cells (normal, low 20%, out 5%, not known), the figure in each tone, fact tiles, sidebar tiles") {
                    LimitsSpecimens()
                }
                section("Banner") {
                    VStack(spacing: Space.s12) {
                        Banner(.error, message: "Could not read settings.json", detail: "Line 14: unexpected comma. Nothing was changed.", actionTitle: "Try again") {}
                        Banner(.warn, message: "Usage counting is slower than usual", detail: "Showing counts from the last scan.", actionTitle: "Rescan") {}
                        Banner(.warn, message: "Codex does not record hook runs")
                    }
                }
                section("Empty state") {
                    GroupedList {
                        EmptyState("No skills yet", message: "Skills you add to Claude Code or Codex show up here with how often they ran.", icon: .loadout) {
                            Button("Rescan") {}.buttonStyle(.reins(.normal))
                        }
                    }
                }
                section("Toast") {
                    HStack(spacing: Space.s16) {
                        ToastView(toast: Toast(message: "Removed ponytail", tone: .info, action: .undo {}), run: {}, dismiss: {})
                        ToastView(toast: Toast(message: "Could not write settings.json", tone: .danger, action: nil), run: {}, dismiss: {})
                        Spacer(minLength: 0)
                    }
                }
                section("Hint bar") {
                    HintBar(hints: [KeyHint(keys: "Tab", label: "Row actions")])
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous))
                }
                section("Settings: rail tabs, theme tiles (System, Light, Dark), the switch on, off and disabled, the Reins mark, a raised block") {
                    SettingsSpecimens()
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, Metrics.pageBottomPadding)
        .background(Palette.well)
    }

    private var buttons: some View {
        HStack(spacing: Rhythm.tools) {
            Button("Normal") {}.buttonStyle(.reins(.normal))
            Button("Primary") {}.buttonStyle(.reins(.primary))
            Button("Remove") {}.buttonStyle(.reins(.danger))
            Button {} label: {
                HStack(spacing: Space.s4) { ReinsIcon(.add); Text("Add to Codex") }
            }
            .buttonStyle(.reins(.ghost))
            Button {} label: { ReinsIcon(.trash) }.buttonStyle(.reins(.icon)).accessibilityLabel("Remove")
            RowActionButton(title: "Remove from Claude Code", icon: .trash, kind: .danger, iconOnly: true, badge: .claude) {}
            RowActionButton(title: "Remove from Codex", icon: .trash, kind: .danger, iconOnly: true, badge: .codex) {}
            Button("Disabled") {}.buttonStyle(.reins(.normal)).disabled(true)
            Spacer(minLength: 0)
        }
        .environment(\.actionsConcealed, false)
    }

    private var tags: some View {
        HStack(spacing: Rhythm.tools) {
            Tag("plugin: neon", icon: .lock)
            Tag("added recently")
            Tag("running", tone: .success)
            Tag("waiting for you", tone: .warn)
            Tag("17 errors", tone: .warn)
            Tag("mixed", tone: .warn, icon: .info)
            Tag("script not found", tone: .danger, icon: .scriptMissing)
            Tag("Deny", tone: .danger)
            CLITag(.claude)
            CLITag(.codex)
            HStack(spacing: Space.s6) { CLIDot(.claude); CLIDot(.codex) }
            Kbd("\u{2318}K")
            Kbd("Esc")
            HStack(spacing: Space.s6) { Text("Skills").reinsText(.captionStrong, tone: .secondary); Count(10) }
            HStack(spacing: Space.s6) { Text("Activity").reinsText(.body); Count(2, alert: true) }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        HStack(spacing: Rhythm.tools) {
            SegmentedControl(label: "Rule", options: [
                SegmentOption("Allow", value: "allow"),
                SegmentOption("Ask", value: "ask"),
                SegmentOption("Deny", value: "deny"),
            ], selection: $segment)
            SegmentedControl(label: "Settings file", options: [
                SegmentOption("Shared", value: "shared"),
                SegmentOption("Local", value: "local", count: 3),
            ], selection: $file)
            ScopePicker(options: [ScopeOption(id: nil, label: "Global")], current: ScopeOption(id: nil, label: "Global"), minWidth: Metrics.scopePickerMinWidth) { _ in }
            HStack(spacing: Rhythm.chips) {
                FilterChip("All", count: 6, isOn: chip == "all") { chip = "all" }
                FilterChip("Never ran", count: 1, isOn: chip == "never") { chip = "never" }
                FilterChip(dismissible: "spacevibe-bench") {}
            }
            SearchField(placeholder: "Search or run a command", shortcut: "\u{2318}K", spokenShortcut: "Command K") {}
            Kbd("Esc")
            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel(title)
            content()
        }
    }
}

/// Every text role with its size, line box and weight, set in itself.
private struct TypeRoles: View {
    private let roles: [(String, ReinsType)] = [
        ("caption", .caption), ("captionStrong", .captionStrong), ("label", .label), ("count", .count),
        ("body", .body), ("bodyStrong", .bodyStrong), ("rowTitle", .rowTitle), ("number", .number),
        ("code", .code), ("codeTitle", .codeTitle), ("title", .title), ("figure", .figure), ("display", .display),
    ]

    var body: some View {
        GroupedList {
            ForEach(roles, id: \.0) { name, role in
                HStack(spacing: Metrics.rowSpacing) {
                    Text(name).reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth, alignment: .leading)
                    Text("\(Int(role.size)) / \(Int(role.lineBox))").reinsText(.count, tone: .tertiary).frame(width: Metrics.costWidth, alignment: .leading)
                    Text(role.code ? "Bash(rm -rf:*) 0O lI1" : role.size > ReinsType.figure.size ? "92%" : "ponytail \u{00B7} Add to Codex \u{00B7} 1,204")
                        .reinsText(role, tone: .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.rowHorizontalPadding)
                .frame(minHeight: Metrics.rowMinHeight)
            }
        }
    }
}

/// The gallery as a window: scrolls, offers the theme toggle, and fires real toasts.
struct ComponentGalleryWindow: View {
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Component gallery").reinsText(.title).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button("Toast with Undo") { toasts.show("Removed ponytail", undo: { toasts.show("Undone: removed ponytail") }) }
                        .buttonStyle(.reins(.normal))
                    Button("Error toast") { toasts.show("Could not write settings.json", tone: .danger) }
                        .buttonStyle(.reins(.normal))
                    ThemeToggle()
                }
                .padding(.leading, Metrics.pagePadding + 70)
                .padding(.trailing, Metrics.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 4)
                ReinsScrollView { ComponentGalleryContent() }
            }
            ToastHost()
        }
        .background(Palette.well)
        .ignoresSafeArea()
    }
}

private struct Swatches: View {
    private let tokens: [(String, Color)] = [
        ("background", Palette.background), ("well", Palette.well), ("surface", Palette.surface),
        ("surfaceRaised", Palette.surfaceRaised), ("border", Palette.border), ("divider", Palette.divider),
        ("selection", Palette.selection), ("hover", Palette.hover), ("accent", Palette.accent),
        ("accentSolid", Palette.accentSolid), ("text", Palette.text), ("textSecondary", Palette.textSecondary),
        ("textTertiary", Palette.textTertiary), ("claude", Palette.claude), ("codex", Palette.codex),
        ("success", Palette.success), ("warn", Palette.warn), ("danger", Palette.danger),
    ]

    var body: some View {
        let rows = stride(from: 0, to: tokens.count, by: 10).map { Array(tokens[$0..<min($0 + 10, tokens.count)]) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row, id: \.0) { token in
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(token.1)
                                .frame(height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                            Text(token.0).reinsText(.caption, tone: .tertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Every generated glyph at the four sizes, in the secondary tone and in a tag's warn ink, then the chevrons.
private struct IconSpecimens: View {
    private let sizes: [IconSize] = [.inline, .control, .row, .sidebar]

    var body: some View {
        GroupedList {
            ForEach(Array(ReinsGlyph.allCases.enumerated()), id: \.offset) { _, glyph in
                HStack(spacing: Metrics.rowSpacing) {
                    Text(glyph.iconName).reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth * 1.5, alignment: .leading)
                    ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                        ReinsIcon(glyph, size: size).frame(width: Metrics.iconLarge)
                    }
                    ReinsIcon(glyph, size: .control, ink: Palette.warnInk)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.rowHorizontalPadding)
            }
            HStack(spacing: Metrics.rowSpacing) {
                Text("chevron (drawn)").reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth * 1.5, alignment: .leading)
                ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                    Chevron(.right, size: size).frame(width: Metrics.iconLarge)
                }
                Chevron(.left, size: .row)
                Chevron(.down, size: .row)
                Chevron(.upDown, size: .control)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Metrics.rowHorizontalPadding)
        }
    }
}

/// The ruler at the usage cell's width (its number column beside it) and at a wider track: the cell is a tenth of the
/// track either way. Inside a card, where it always sits.
private struct RulerSpecimens: View {
    private let shares: [(String, Double?, LimitTone)] = [
        ("0%", 0, .normal), ("4%", 0.04, .normal), ("39%", 0.39, .normal), ("100%", 1, .normal),
        ("not known", nil, .normal), ("20% left", 0.2, .low), ("5% left", 0.05, .out),
    ]

    var body: some View {
        GroupedList {
            CardHeader("Ruler", count: shares.count, columns: {
                Text("at the usage cell's track").frame(width: Metrics.usageCellWidth, alignment: .leading)
                Text("at twice that").frame(width: Metrics.usageCellWidth * 2, alignment: .leading)
            })
            ForEach(shares, id: \.0) { label, share, tone in
                Row { RowText(label) }
                    .cells {
                        HStack(spacing: Metrics.rowSpacing) {
                            Ruler(share: share, fill: tone.barFill ?? Palette.claude)
                            Text(label).reinsText(.number, tone: .secondary).frame(width: Metrics.usageNumberWidth, alignment: .trailing)
                        }
                        .frame(width: Metrics.usageCellWidth)
                        Ruler(share: share, fill: tone.barFill ?? Palette.codex).frame(width: Metrics.usageCellWidth * 2)
                    }
            }
        }
    }
}

/// The Limits page's parts in every state, on the page well: window tiles (selected, low, out, passed, not in use, no
/// reading), the figure in each tone and unknown, the detail ruler and facts in a card, and the sidebar's tiles.
private struct LimitsSpecimens: View {
    var body: some View {
        HStack(alignment: .top, spacing: Rhythm.listDetail) {
            VStack(spacing: Rhythm.tiles) {
                LimitWindowTile(cli: .codex, title: "Weekly", subtitle: "Codex \u{00B7} resets in 1 d 3 h",
                                meter: .share(0.04, fill: Palette.danger), value: "4%", valueTone: .danger, selected: true, onActivate: {})
                LimitWindowTile(cli: .codex, title: "5-hour", subtitle: "Codex \u{00B7} reset passed", meter: .unknown,
                                value: "unknown", onActivate: {})
                LimitWindowTile(cli: .claude, title: "Weekly", subtitle: "Claude Code \u{00B7} resets in 2 d 22 h",
                                meter: .share(0.18, fill: Palette.warn), value: "18%", valueTone: .warn, onActivate: {})
                LimitWindowTile(cli: .claude, title: "Weekly \u{00B7} Fable", subtitle: "Claude Code \u{00B7} resets in 2 d 22 h",
                                meter: .share(0.92, fill: Palette.claude), value: "92%", onActivate: {}) { Tag("not in use") }
                LimitWindowTile(cli: .gemini, title: "Gemini CLI", subtitle: "Not measurable", meter: .none, value: "\u{2014}", onActivate: {})
            }
            .frame(width: Metrics.limitsListWidth)
            VStack(alignment: .leading, spacing: Rhythm.cards) {
                ContentCard {
                    VStack(alignment: .leading, spacing: Space.s16) {
                        LimitFigure(left: 92)
                        LimitFigure(left: 18, tone: .low)
                        LimitFigure(left: 4, tone: .out)
                        LimitFigure(left: nil)
                        Ruler(share: 0.04, fill: Palette.danger, height: Metrics.rulerDetailHeight)
                        Ruler(share: nil, fill: Palette.codex, height: Metrics.rulerDetailHeight)
                        HStack(alignment: .top, spacing: Rhythm.tiles) {
                            FactTile("Resets in", value: "1 d 3 h")
                            FactTile("Reset at", value: "17:34")
                            FactTile("Reading", value: "2 days ago", tone: .warn)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: Space.s6) {
                    LimitSidebarTile(cli: .claude, name: "Claude Code", value: "92% left")
                    LimitSidebarTile(cli: .codex, name: "Codex", value: "18% left", tone: .low)
                    LimitSidebarTile(cli: .codex, name: "Codex", value: "4% left", tone: .out)
                    LimitSidebarTile(cli: .gemini, name: "Gemini CLI", value: "not measurable", isMuted: true)
                }
                .padding(Space.s8)
                .frame(width: Metrics.sidebarWidth)
                .background(Palette.well)
            }
        }
    }
}

/// The Settings pieces in each state: the rail on the well, then the tiles, switches, mark and raised block in a card.
private struct SettingsSpecimens: View {
    @State private var section = SettingsSection.appearance
    @State private var theme = ThemeSetting.dark
    @State private var on = true
    @State private var off = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Space.s4) {
                ForEach(SettingsSection.allCases) { item in
                    RailTab(title: item.title, icon: item.icon, isActive: item == section) { section = item }
                }
            }
            GroupedList {
                HStack(spacing: Rhythm.tiles) {
                    ForEach(ThemeSetting.allCases, id: \.self) { item in
                        ThemeTile(title: item.title, icon: item.icon, appearance: item.fixed?.colorScheme, isSelected: item == theme) { theme = item }
                    }
                }
                .frame(width: Metrics.settingsColumnWidth)
                .padding(.horizontal, Metrics.rowInset)
                .padding(.top, Space.s8)
                .groupedListPart(.plain)
                HStack(spacing: Space.s16) {
                    ReinsSwitch(label: "On", isOn: $on)
                    ReinsSwitch(label: "Off", isOn: $off)
                    ReinsSwitch(label: "Disabled", isOn: .constant(false)).disabled(true)
                    ReinsMark()
                    RaisedBlock { Text("A raised block inside a card").reinsText(.body, tone: .secondary) }
                        .frame(width: Metrics.usageCellWidth * 2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.rowHorizontalPadding)
                .padding(.top, Space.s8)
                .groupedListPart(.plain)
            }
        }
    }
}

/// Every v5 glyph at 12, 14, 16 and 24 in the secondary tone, and at 16 in the tertiary tone (a lead icon) and in a warn ink,
/// two to a line: the category set, the content set, then the five verdict glyphs.
private struct V5IconSpecimens: View {
    private let sizes: [IconSize] = [.small, .inline, .control, .large]
    private let columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            GroupedList {
                specimenGrid(CategoryGlyph.allCases.map { glyph in
                    (glyph.iconName, { size, ink in ReinsIcon(category: glyph, size: size, ink: ink) })
                })
            }
            GroupedList {
                specimenGrid(ContentGlyph.allCases.map { glyph in
                    (glyph.iconName, { size, ink in ReinsIcon(content: glyph, size: size, ink: ink) })
                })
            }
            GroupedList {
                specimenGrid(VerdictGlyph.Kind.allCases.map { kind in
                    ("verdict \(kind)", { size, _ in VerdictGlyph(kind, size: size) })
                })
            }
        }
    }

    private func specimenGrid(_ items: [(String, (IconSize, Color?) -> some View)]) -> some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0 ..< min($0 + columns, items.count)]) }
        return VStack(alignment: .leading, spacing: Space.s8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .center, spacing: Space.s16) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: Space.s8) {
                            Text(item.0).reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth * 1.4, alignment: .leading)
                            ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                                item.1(size, nil).frame(width: Metrics.iconLarge)
                            }
                            item.1(.control, Palette.warnInk)
                            item.1(.control, Palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(0 ..< columns - row.count, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Metrics.rowHorizontalPadding)
    }
}
