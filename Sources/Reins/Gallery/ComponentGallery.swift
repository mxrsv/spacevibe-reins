import SwiftUI

/// Every shared view in every state. Reach it with `REINS_GALLERY=1`; the screenshot mode renders the same content.
struct ComponentGalleryContent: View {
    @State private var segment = "ask"
    @State private var file = "shared"
    @State private var scope = "global"
    @State private var chip = "all"
    @State private var draft = ""
    @State private var badDraft = "Bash(npm test"
    @FocusState private var draftFocused: Bool
    @FocusState private var badDraftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Colour tokens") { Swatches() }
            section("Text roles: Inter at 12, 14 and 16, plus figure") { TypeRoles() }
            section("Buttons") {
                HStack(spacing: Rhythm.tools) {
                    Button("Normal") {}.buttonStyle(.reins(.normal))
                    Button("Primary") {}.buttonStyle(.reins(.primary))
                    Button("Remove") {}.buttonStyle(.reins(.danger))
                    Button {} label: {
                        HStack(spacing: Space.s4) { Image(systemName: "plus").imageScale(.small); Text("Add to Codex") }
                    }
                    .buttonStyle(.reins(.ghost))
                    Button {} label: { Image(systemName: "trash").accessibilityLabel("Remove") }.buttonStyle(.reins(.icon))
                    RowActionButton(title: "Remove from Claude Code", systemImage: "trash", kind: .danger, iconOnly: true, badge: .claude) {}
                    RowActionButton(title: "Remove from Codex", systemImage: "trash", kind: .danger, iconOnly: true, badge: .codex) {}
                    Button("Disabled") {}.buttonStyle(.reins(.normal)).disabled(true)
                    Spacer(minLength: 0)
                }
                .environment(\.actionsConcealed, false)
            }
            section("Tags, counts, CLI tag and dot, key caps") {
                HStack(spacing: Rhythm.tools) {
                    Tag("plugin: neon", systemImage: "lock")
                    Tag("added recently")
                    Tag("running", tone: .success)
                    Tag("waiting for you", tone: .warn)
                    Tag("17 errors", tone: .warn)
                    Tag("mixed", tone: .warn, systemImage: "info.circle")
                    Tag("script not found", tone: .danger, systemImage: "questionmark.folder")
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
            section("Segmented control, filter chips, scope picker, search field: all 28 pt") {
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
                    Spacer(minLength: 0)
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
            section("Cards, rows and the five usage states") { DemoLoadoutList() }
            section("Rows") {
                GroupedList {
                    CardHeader("Rows", count: 5)
                    Row { RowText("Plain row", subtitle: "Second line in the muted colour") }
                        .lead { Image(systemName: "sparkles") }
                    Row(selected: true, revealActions: true, onActivate: {}) {
                        RowText("Selected row with actions", subtitle: "Actions stay visible while selected")
                    }
                    .lead { Image(systemName: "sparkles") }
                    .actions {
                        RowActionButton(title: "Copy to Codex", systemImage: "doc.on.doc") {}
                        RowActionButton(title: "Remove", systemImage: "trash", kind: .danger, iconOnly: true) {}
                    }
                    Row(onActivate: {}) { RowText("Session with a state", subtitle: "spacevibe-bench \u{00B7} just now") }
                        .lead { CLIDot(.codex) }
                        .cells { StateCell { Tag("not measurable", systemImage: "exclamationmark.triangle") }; NumberCell(text: "~$148.20") }
                    Row(onActivate: {}) { RowText("A row with nothing to change", subtitle: "Owned by a plugin") }
                        .lead { Image(systemName: "sparkles") }
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
                    VStack(spacing: Space.s2) {
                        SidebarItem(title: "Loadout", systemImage: "square.stack.3d.up", count: 22, isActive: true) {}
                        SidebarItem(title: "Rules", systemImage: "checkmark.shield", count: 11, isActive: false) {}
                        SidebarItem(title: "Activity", systemImage: "waveform.path.ecg", count: 2, alert: true, isActive: false) {}
                    }
                    .sidebarSurface()
                    .frame(height: Metrics.galleryOverlayHeight)
                    PaletteCard {
                        Text("Search skills, hooks, rules, or run an action").paletteField()
                        Hairline()
                        VStack(alignment: .leading, spacing: 0) {
                            PaletteSectionTitle(title: "Go to")
                            PaletteRow(entry: PaletteEntry(id: "g.loadout", title: "Loadout", systemImage: "square.stack.3d.up", trailing: "\u{2318}1") {}, isHighlighted: true) {}
                            PaletteRow(entry: PaletteEntry(id: "g.rules", title: "Rules", systemImage: "checkmark.shield", trailing: "\u{2318}2") {}, isHighlighted: false) {}
                            PaletteSectionTitle(title: "Skills")
                            PaletteRow(entry: PaletteEntry(id: "s.ponytail", title: "ponytail", subtitle: "Pick the laziest solution", systemImage: "sparkles") {}, isHighlighted: false) {}
                            PaletteEmptyRow(text: "No matches")
                        }
                        .paletteList()
                        Hairline()
                        PaletteFooter {
                            PaletteHint(text: "navigate") { Image(systemName: "arrow.up.arrow.down") }
                            PaletteHint(text: "close") { Kbd("Esc") }
                        }
                    }
                    Spacer(minLength: 0)
                }
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
                    EmptyState("No skills yet", message: "Skills you add to Claude Code or Codex show up here with how often they ran.", systemImage: "square.stack.3d.up") {
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
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, Metrics.pageBottomPadding)
        .background(Palette.well)
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
        ("code", .code), ("codeTitle", .codeTitle), ("title", .title), ("figure", .figure),
    ]

    var body: some View {
        GroupedList {
            ForEach(roles, id: \.0) { name, role in
                HStack(spacing: Metrics.rowSpacing) {
                    Text(name).reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth, alignment: .leading)
                    Text("\(Int(role.size)) / \(Int(role.lineBox))").reinsText(.count, tone: .tertiary).frame(width: Metrics.costWidth, alignment: .leading)
                    Text(role.code ? "Bash(rm -rf:*) 0O lI1" : "ponytail \u{00B7} Add to Codex \u{00B7} 1,204")
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
        ("background", Palette.background), ("well", Palette.well), ("sidebar", Palette.sidebar), ("surface", Palette.surface),
        ("surfaceRaised", Palette.surfaceRaised), ("border", Palette.border), ("track", Palette.track),
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
