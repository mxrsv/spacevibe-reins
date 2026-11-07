import SwiftUI

/// The v5 controls and overlays in every state of the spec's Components table, on the content panel's ground, as
/// `system/components.html` shows them. Open menus and popovers are drawn in place (the kit's `.stage`); one framed demo
/// puts popovers through `overlayHost()` to show placement below, above and clamped; the live gallery also opens the real
/// Filter and View menus. Hover, focus and press are drawn with `.specimen(_:)`. Synthetic names only.
struct ControlSpecimens: View {
    @State private var tabs = "skills"
    @State private var filterOpen = false
    @State private var viewOpen = false
    @State private var picks: Set<String> = ["status:never", "status:heavy"]
    @State private var group = "group:none"
    @State private var order = "order:sessions"
    @State private var codexLit = false
    @State private var stopShown = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            SpecimenLayout.panel("Tab head: chips inactive, hover, focus and active per category; Activity's active chip in the accent; toolbar buttons (scope with its caret, Filter, View) at rest, hover and focus. The live gallery opens Filter and View.") { tabHeads }
            SpecimenLayout.panel("Filter chip row: field | value | x, the close hovered and focused, then Clear") { chipRow }
            SpecimenLayout.panel("Menus: Filter with a field open (two levels, the count of picks, a hovered field), Filter with one field (one level), View (radio), a keyboard-highlighted line") { menus }
            SpecimenLayout.panel("Logo toggle and strip: lit, dim, hover on dim, hover on lit (danger badge), pressed, focus, read-only, only copy; a row with the strip and the warning slot") { logos }
            SpecimenLayout.panel("Warning slot (empty, warn, danger, clock, lock, hover, focus) and its popover; the row-detail popover; placement through the overlay host: below, above near the bottom edge, clamped 8 inside") { warnings }
            SpecimenLayout.panel("Bottom bar (one CLI lit, a mixed selection) and the toast: Undo with its Z cap, Undo hovered, a bulk write, the Stop toast without Undo, an error") { bars }
            SpecimenLayout.panel("Stop confirmation: 400 wide on the scrim, focus starts on Cancel") { dialog }
            SpecimenLayout.panel("Buttons 32 (normal, primary, danger, solid danger, icon) at rest, hover, pressed, focus and disabled, with key caps; 28 in a popover and in the bottom bar; key caps plain, on the accent and on solid danger") { buttons }
            SpecimenLayout.panel("Command palette: open with a selected row and key caps, then nothing found; the status bar with its keys and the data source") { palette }
        }
    }

    // MARK: - Tab head

    private var tabHeads: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            headCard {
                TabHead {
                    TabChip(title: "Skills", glyph: CategoryGlyph.skill, count: 13, tone: .skill, isActive: tabs == "skills") { tabs = "skills" }
                    TabChip(title: "Subagents", glyph: CategoryGlyph.subagent, count: 6, tone: .subagent, isActive: tabs == "subagents") { tabs = "subagents" }
                        .specimen(.hover)
                    TabChip(title: "Hooks", glyph: CategoryGlyph.hook, count: 21, tone: .hook, isActive: tabs == "hooks") { tabs = "hooks" }
                        .specimen(.focus)
                    TabChip(title: "Rules", glyph: ContentGlyph.rule, count: 36, tone: .rule, isActive: tabs == "rules") { tabs = "rules" }
                } actions: {
                    ToolbarButton("Global", trailingCaret: true) {}
                    ToolbarMenuButton("Filter", glyph: .filter, isOpen: $filterOpen, id: "gallery.filter") { close in
                        FilterMenu(fields: filterFields, onToggle: toggle, onClose: close)
                    }
                    .specimen(.hover)
                    ToolbarMenuButton("View", glyph: .sliders, isOpen: $viewOpen, id: "gallery.view") { close in
                        RadioMenu(entries: viewEntries, onPick: pick, onClose: close)
                    }
                    .specimen(.focus)
                }
            }
            ForEach(["Subagents", "Hooks", "Rules"], id: \.self) { active in
                headCard {
                    TabHead {
                        TabChip(title: "Skills", glyph: CategoryGlyph.skill, count: 13, tone: .skill, isActive: false) {}
                        TabChip(title: "Subagents", glyph: CategoryGlyph.subagent, count: 6, tone: .subagent, isActive: active == "Subagents") {}
                        TabChip(title: "Hooks", glyph: CategoryGlyph.hook, count: 21, tone: .hook, isActive: active == "Hooks") {}
                        TabChip(title: "Rules", glyph: ContentGlyph.rule, count: 36, tone: .rule, isActive: active == "Rules") {}
                            .specimen(active == "Rules" ? .focus : [])
                    } actions: {
                        ToolbarButton("Filter", glyph: .filter) {}
                    }
                }
            }
            headCard {
                TabHead {
                    TabChip(title: "Running", glyph: ContentGlyph.pulse, count: 6, tone: .accent, isActive: true) {}
                    TabChip(title: "Failed", glyph: ContentGlyph.bug, count: 4, tone: .accent, isActive: false) {}.specimen(.hover)
                    TabChip(title: "Files", glyph: ContentGlyph.file, count: 7, tone: .accent, isActive: false) {}
                } actions: {
                    ToolbarButton("Filter", glyph: .filter) {}
                }
            }
            headCard {
                TabHead {
                    EmptyView()
                } actions: {
                    ToolbarButton("Refresh", glyph: .enter) {}
                }
            }
            SpecimenLayout.caption("Rows: Skills active, Subagents hover, Hooks focus, Filter hover, View focus; Subagents, Hooks, Rules (focused) active; Activity with the accent; Limits' head with Refresh only.")
        }
    }

    private func headCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: Self.panelWidth)
            .blockSurface(Palette.bgPanel)
    }

    /// The content panel at 1440 x 900: the window less the sidebar (220) and the panel's 12 inset at the right.
    private static let panelWidth: CGFloat = Metrics.ContentPanel.widthAt1440

    // MARK: - Chips

    private var chipRow: some View {
        FilterChipRow(onClear: {}) {
            FilterFieldChip(field: "Status is", value: "Never ran") {}
            FilterFieldChip(field: "CLI is", value: "Codex") {}.specimen(.hover)
            FilterFieldChip(field: "Rank is", value: "Top 10 most used") {}.specimen(.focus)
        }
        .frame(width: Self.panelWidth)
        .blockSurface(Palette.bgPanel)
    }

    // MARK: - Menus

    private var filterFields: [FilterMenuField] {
        func value(_ field: String, _ id: String, _ title: String, _ verdict: VerdictGlyph.Kind? = nil) -> MenuEntry {
            MenuEntry(id: id, title: title, kind: .check(isOn: picks.contains("\(field):\(id)")), lead: verdict.map { .verdict($0) })
        }
        return [
            FilterMenuField(id: "status", title: "Status", lead: .verdict(.used),
                            values: [value("status", "never", "Never ran", .never), value("status", "heavy", "Heavily used", .heavy)]),
            FilterMenuField(id: "cli", title: "CLI", lead: .glyph(.terminal),
                            values: [value("cli", "claude", "In Claude Code"), value("cli", "codex", "In Codex"), value("cli", "both", "In both"),
                                     value("cli", "one", "In one only")]),
            FilterMenuField(id: "owner", title: "Owner", lead: .glyph(.lock), values: [value("owner", "mine", "Mine"), value("owner", "plugin", "Plugin")]),
            FilterMenuField(id: "rank", title: "Rank", lead: .glyph(.rank),
                            values: [value("rank", "top10", "Top 10 most used"), value("rank", "top25", "Top 25 most used"),
                                     value("rank", "least10", "Least used 10"), value("rank", "never", "Never ran"),
                                     MenuEntry(id: "tiers", title: "Tiers", kind: .heading), value("rank", "top20", "Top 20%"),
                                     value("rank", "middle", "Middle"), value("rank", "bottom20", "Bottom 20%")]),
            FilterMenuField(id: "last", title: "Last ran", lead: .glyph(.clock),
                            values: [value("last", "today", "Today"), value("last", "week", "This week"), value("last", "old", "Over 30 days ago"),
                                     value("last", "never", "Never")]),
        ]
    }

    private var viewEntries: [MenuEntry] {
        func radio(_ section: String, _ id: String, _ title: String) -> MenuEntry {
            let key = "\(section):\(id)"
            return MenuEntry(id: key, title: title, kind: .radio(isOn: section == "group" ? group == key : order == key))
        }
        return [
            MenuEntry(id: "h.group", title: "Group by", kind: .heading),
            radio("group", "none", "None"), radio("group", "status", "Status"), radio("group", "cli", "CLI presence"),
            radio("group", "owner", "Owner"), radio("group", "rank", "Rank tier"),
            MenuEntry(id: "h.order", title: "Order by", kind: .heading),
            radio("order", "name", "Name"), radio("order", "sessions", "Sessions"), radio("order", "last", "Last run"),
        ]
    }

    private func toggle(_ field: String, _ value: String) {
        let key = "\(field):\(value)"
        if picks.contains(key) { picks.remove(key) } else { picks.insert(key) }
    }

    private func pick(_ entry: String) {
        if entry.hasPrefix("group:") { group = entry } else { order = entry }
    }

    private var menus: some View {
        HStack(alignment: .top, spacing: Space.s24) {
            VStack(alignment: .leading, spacing: Space.s8) {
                SpecimenLayout.caption("two levels: Status open, Rank hovered")
                HStack(alignment: .top, spacing: Metrics.Menu.gap) {
                    MenuSurface(width: Metrics.Menu.submenuWidth) {
                        ForEach(filterFields[0].values) { MenuLine(entry: $0) }
                    }
                    .offset(y: -Metrics.Menu.submenuRise)
                    MenuSurface {
                        ForEach(Array(filterFields.enumerated()), id: \.element.id) { index, field in
                            MenuLine(entry: field.entry, isHighlighted: index == 3, isExpanded: index == 0)
                        }
                    }
                }
                .padding(.top, Metrics.Menu.submenuRise)
            }
            VStack(alignment: .leading, spacing: Space.s8) {
                SpecimenLayout.caption("one level (Activity: CLI), keyboard on Codex")
                MenuSurface {
                    MenuLine(entry: MenuEntry(id: "claude", title: "Claude Code", kind: .check(isOn: true)))
                    MenuLine(entry: MenuEntry(id: "codex", title: "Codex", kind: .check(isOn: false)), isHighlighted: true)
                }
            }
            VStack(alignment: .leading, spacing: Space.s8) {
                SpecimenLayout.caption("View: radio, Status hovered")
                MenuSurface {
                    ForEach(Array(viewEntries.enumerated()), id: \.element.id) { index, entry in
                        MenuLine(entry: entry, isHighlighted: index == 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Logos

    private var logos: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(alignment: .top, spacing: Space.s32) {
                logoState("dim, lit") { LogoToggle(cli: .claude, isLit: false) {}; LogoToggle(cli: .codex, isLit: true) {} }
                logoState("lit, lit") { LogoToggle(cli: .claude, isLit: true) {}; LogoToggle(cli: .codex, isLit: true) {} }
                logoState("hover on dim (add)") { LogoToggle(cli: .claude, isLit: false) {}.specimen(.hover); LogoToggle(cli: .codex, isLit: false) {} }
                logoState("hover on lit (remove)") { LogoToggle(cli: .claude, isLit: true) {}.specimen(.hover); LogoToggle(cli: .codex, isLit: true) {} }
                logoState("pressed") { LogoToggle(cli: .claude, isLit: true) {}.specimen(.press); LogoToggle(cli: .codex, isLit: false) {} }
                logoState("focus") { LogoToggle(cli: .claude, isLit: true) {}.specimen(.focus); LogoToggle(cli: .codex, isLit: false) {} }
                logoState("read-only (plugin)") {
                    LogoToggle(cli: .claude, isLit: true, mode: .readOnly) {}; LogoToggle(cli: .codex, isLit: false, mode: .readOnly) {}
                }
                logoState("only copy") { LogoToggle(cli: .claude, isLit: true, mode: .onlyCopy) {}; LogoToggle(cli: .codex, isLit: false) {} }
                logoState("just changed (live: press Codex)") {
                    LogoToggle(cli: .claude, isLit: true) {}
                    LogoToggle(cli: .codex, isLit: codexLit, justChanged: codexLit) { codexLit.toggle() }
                }
                Spacer(minLength: 0)
            }
            ListRows {
                ListRow("review-change", lead: CategoryGlyph.skill) {
                    LogoStrip { LogoToggle(cli: .claude, isLit: true, mode: .onlyCopy) {}; LogoToggle(cli: .codex, isLit: false) {} }
                    WarningSlot(mark: StateMark(.warn, label: "Never ran"), detail: "Never ran in Claude Code. Added 3 weeks ago.",
                                id: "gallery.row.review-change") { PopoverSentence("Never ran in Claude Code. Added 3 weeks ago.") }
                }
                ListRow("neon-postgres", lead: CategoryGlyph.skill) {
                    LogoStrip { LogoToggle(cli: .claude, isLit: true, mode: .readOnly) {}; LogoToggle(cli: .codex, isLit: false, mode: .readOnly) {} }
                    WarningSlot(mark: StateMark(.lock, label: "Plugin-owned"), detail: "Owned by the neon plugin. Read only.",
                                id: "gallery.row.neon") { PopoverNote("Owned by the neon plugin. Remove it by uninstalling the plugin.", glyph: .lock) }
                }
            }
            .frame(width: SpecimenLayout.halfCanvas)
        }
    }

    private func logoState<Content: View>(_ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            SpecimenLayout.caption(caption)
            LogoStrip { content() }
        }
    }

    // MARK: - Warning slot and popovers

    private var warnings: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            HStack(alignment: .top, spacing: Space.s32) {
                slotState("empty") { WarningSlot() }
                slotState("warn: never ran") { slot(.warn, "Never ran") }
                slotState("danger: can't run") { slot(.danger, "Can't run") }
                slotState("clock: unmeasurable, new") { slot(.clock, "Unmeasurable") }
                slotState("lock: plugin-owned") { slot(.lock, "Plugin-owned") }
                slotState("hover") { slot(.warn, "Never ran").specimen(.hover) }
                slotState("focus") { slot(.danger, "Can't run").specimen(.focus) }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    SpecimenLayout.caption("warning popover")
                    PopoverSurface {
                        PopoverSentence("Never ran in Claude Code. Added 3 weeks ago.")
                        PopoverActions {
                            Button {} label: { ActionLabel("Remove", glyph: .trash) }.buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
                            Button {} label: { ActionLabel("Open file", glyph: .open) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Space.s8) {
                    SpecimenLayout.caption("row detail popover")
                    PopoverSurface {
                        PopoverHead(name: "Fix leaderboard 500", sub: "Claude Code, spacevibe-api") { CLIMark(CoreLimitsCLI.claude, size: .logo) }
                        PopoverSentence("Asks: Allow Bash? pnpm test --filter api")
                        PopoverSentence("Answer in the terminal. SpaceVibe only shows the question.")
                        PopoverActions {
                            Button {} label: { ActionLabel("Open", key: "O") }
                            Button {} label: { ActionLabel("Stop\u{2026}", key: "S") }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Space.s8) {
                    SpecimenLayout.caption("detail with a path and a note, hover on the danger button")
                    PopoverSurface {
                        PopoverHead(name: "format-on-save", sub: "PostToolUse", subIsReading: true) {
                            SpaceVibeIcon(category: .hook, ink: Palette.fg3).frame(width: Metrics.LogoToggle.logo, height: Metrics.LogoToggle.logo)
                        }
                        PopoverSentence("Claude Code: command, matcher Edit|Write, 41 runs.")
                        PopoverPath("~/.claude/hooks/format-on-save.sh")
                        PopoverNote("Tool names in a matcher can differ between the CLIs (unverified).", glyph: .warning)
                        PopoverActions {
                            Button {} label: { ActionLabel("Copy to Codex", key: "A") }
                            Button {} label: { ActionLabel("Remove", key: "R") }
                                .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact)).specimen(.hover)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Space.s8) {
                SpecimenLayout.caption("placement in a 760 x 300 window: below the left anchor, above the anchor near the bottom, clamped 8 from the right edge")
                placementDemo
            }
        }
    }

    private func slot(_ kind: StateMark.Kind, _ label: String) -> some View {
        WarningSlot(mark: StateMark(kind, label: label), detail: label, id: "gallery.slot.\(label)") { PopoverSentence(label) }
    }

    private func slotState<Content: View>(_ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            SpecimenLayout.caption(caption)
            content()
        }
    }

    /// Three anchors with their popovers open, placed by an `overlayHost()` of their own, so the frame stands in for the
    /// window.
    private var placementDemo: some View {
        ZStack(alignment: .topLeading) {
            anchor("below").position(x: 120, y: 40)
            anchor("above").position(x: 380, y: 270)
            anchor("clamped").position(x: 744, y: 40)
        }
        .frame(width: 760, height: 300)
        .background(Palette.bgPanel)
        .overlayHost()
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle))
        .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle).strokeBorder(Palette.hair2))
    }

    private func anchor(_ name: String) -> some View {
        StateMarkIcon(mark: StateMark(.warn, label: name))
            .frame(width: Metrics.WarningSlot.size, height: Metrics.WarningSlot.size)
            .background(RoundedRectangle(cornerRadius: Metrics.Radius.control).fill(Palette.hover))
            .anchoredOverlay(isPresented: true, id: "placement.\(name)", placement: .popover) {
                PopoverSurface { PopoverSentence("Placed \(name) its anchor.") }
            }
    }

    // MARK: - Bottom bar and toast

    private var bars: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(alignment: .top, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    SpecimenLayout.caption("shown: every picked skill is in both CLIs")
                    bulkBar(codexLit: true)
                }
                VStack(alignment: .leading, spacing: Space.s8) {
                    SpecimenLayout.caption("mixed: some picked skills are in Codex (dim, press to add)")
                    bulkBar(codexLit: false)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: Space.s16) {
                ToastBar(toast: Toast(message: "Added ponytail to Codex", tone: .info, action: .undo {}), run: {})
                ToastBar(toast: Toast(message: "Removed explain", tone: .info, action: .undo {}), run: {}).specimen(.hover)
                ToastBar(toast: Toast(message: "Added 2 skills to Codex", tone: .info, action: .undo {}), run: {})
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: Space.s16) {
                ToastBar(toast: Toast(message: "Sent SIGTERM to pid 40137. \u{201C}Fix leaderboard 500\u{201D} is stopped.", tone: .info, action: nil), run: {})
                ToastBar(toast: Toast(message: "Could not write settings.json", tone: .danger, action: nil), run: {})
                Spacer(minLength: 0)
            }
        }
    }

    private func bulkBar(codexLit: Bool) -> some View {
        BulkBar("3 selected", stripLabel: "Add to") {
            LogoStrip {
                LogoToggle(cli: .claude, isLit: true, spokenValue: "all picked skills are in Claude Code, press to remove them") {}
                LogoToggle(cli: .codex, isLit: codexLit,
                           spokenValue: codexLit ? "all picked skills are in Codex, press to remove them" : "press to add the picked skills") {}
            }
        } actions: {
            Button {} label: { ActionLabel("Remove", key: "R") }.buttonStyle(ActionButtonStyle(kind: .danger, size: .bar))
            Button {} label: { ActionLabel("Clear", key: "esc") }
        }
    }

    // MARK: - Dialog

    private var dialog: some View {
        ZStack {
            Palette.bgPanel
            if stopShown {
                ConfirmationPanel(
                    title: "Stop \u{201C}Fix leaderboard 500\u{201D}?",
                    message: Text("Sends SIGTERM to pid ") + Text("40137").bold() + Text(" (Claude Code, spacevibe-api). Unsaved work in that session may be lost. This cannot be undone."),
                    note: "SpaceVibe checks that the pid still belongs to this session before it sends anything.",
                    confirmTitle: "Stop session", confirmGlyph: .stop,
                    cancel: { stopShown = false }, confirm: { stopShown = false })
            } else {
                Button { stopShown = true } label: { ActionLabel("Show the Stop confirmation again") }
                    .buttonStyle(ActionButtonStyle())
            }
        }
        .frame(width: 760, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle))
    }

    // MARK: - Buttons and key caps

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            buttonLine("normal", kind: .normal, title: "Open", glyph: .open, key: "O")
            buttonLine("primary", kind: .primary, title: "Add to Codex", glyph: nil, key: "A")
            buttonLine("danger", kind: .danger, title: "Remove", glyph: .trash, key: "R")
            buttonLine("solid danger", kind: .solidDanger, title: "Stop session", glyph: .stop, key: nil)
            HStack(spacing: Space.s16) {
                SpecimenLayout.caption("icon").frame(width: 96, alignment: .leading)
                ForEach(states, id: \.0) { name, state in
                    VStack(spacing: Space.s4) {
                        Button {} label: { SpaceVibeIcon(content: .enter) }
                            .buttonStyle(ActionButtonStyle(kind: .icon)).specimen(state).disabled(name == "disabled")
                            .accessibilityLabel("Refresh")
                        SpecimenLayout.caption(name)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s16) {
                SpecimenLayout.caption("28: popover, bar").frame(width: 96, alignment: .leading)
                Button {} label: { ActionLabel("Remove", glyph: .trash) }.buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
                Button {} label: { ActionLabel("Open file", glyph: .open, key: "O") }.buttonStyle(ActionButtonStyle(size: .compact))
                Button {} label: { ActionLabel("Copy /usage", key: "C") }.buttonStyle(ActionButtonStyle(size: .compact)).specimen(.hover)
                Button {} label: { ActionLabel("Clear", key: "esc") }.buttonStyle(ActionButtonStyle(size: .bar))
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s16) {
                SpecimenLayout.caption("key caps").frame(width: 96, alignment: .leading)
                KeyCap("\u{2318}K")
                KeyCap("esc")
                KeyCap("Z")
                KeyCap("\u{21B5}")
                Button {} label: { ActionLabel("on the accent", key: "A") }.buttonStyle(ActionButtonStyle(kind: .primary))
                Button {} label: { ActionLabel("on solid danger", key: "S") }.buttonStyle(ActionButtonStyle(kind: .solidDanger))
                Spacer(minLength: 0)
            }
        }
    }

    private let states: [(String, SpecimenInteraction)] = [("rest", []), ("hover", .hover), ("pressed", .press), ("focus", .focus), ("disabled", [])]

    private func buttonLine(_ caption: String, kind: ActionButtonKind, title: String, glyph: ContentGlyph?, key: String?) -> some View {
        HStack(spacing: Space.s16) {
            SpecimenLayout.caption(caption).frame(width: 96, alignment: .leading)
            ForEach(states, id: \.0) { name, state in
                VStack(alignment: .leading, spacing: Space.s4) {
                    Button {} label: { ActionLabel(title, glyph: glyph, key: key) }
                        .buttonStyle(ActionButtonStyle(kind: kind))
                        .specimen(state)
                        .disabled(name == "disabled")
                    SpecimenLayout.caption(name)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Palette and status bar

    private var palette: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            HStack(alignment: .top, spacing: Space.s24) {
                PalettePanel {
                    PaletteSearchLine { Text("go") }
                    PaletteCommandList {
                        PaletteGroupTitle("Navigate")
                        PaletteCommandRow(title: "Go to Agents", glyph: ContentGlyph.stack, keyCap: "\u{2318}1", isSelected: true) {}
                        PaletteCommandRow(title: "Go to Activity", glyph: ContentGlyph.pulse, keyCap: "\u{2318}2", isSelected: false) {}
                        PaletteCommandRow(title: "Go to Limits", glyph: ContentGlyph.gauge, keyCap: "\u{2318}3", isSelected: false) {}
                        PaletteGroupTitle("Selection")
                        PaletteCommandRow(title: "Add to Codex", glyph: ContentGlyph.plus, keyCap: "A", isSelected: false) {}
                    }
                    PaletteKeysFooter(hints: paletteHints)
                }
                PalettePanel {
                    PaletteSearchLine { Text("zzz") }
                    PaletteNoMatch()
                    PaletteKeysFooter(hints: paletteHints)
                }
            }
            StatusBar(hints: [KeyHint(keys: "J K", label: "move"), KeyHint(keys: "X", label: "select"), KeyHint(keys: "\u{21B5}", label: "focus actions"),
                              KeyHint(keys: "/", label: "filter"), KeyHint(keys: "1 2 3 4", label: "tabs")],
                      source: "Sessions counted from local logs")
                .frame(width: Self.panelWidth)
                .blockSurface(Palette.bgPanel)
        }
    }

    private let paletteHints = [KeyHint(keys: "\u{2191} \u{2193}", label: "move"), KeyHint(keys: "\u{21B5}", label: "run"),
                                KeyHint(keys: "esc", label: "close")]
}
