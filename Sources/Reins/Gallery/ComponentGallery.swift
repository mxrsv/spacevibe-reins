import SwiftUI

/// Every shared view in every state. Reach it with `REINS_GALLERY=1`; the screenshot mode renders the same content.
struct ComponentGalleryContent: View {
    @State private var segment = "ask"
    @State private var scope = "global"
    @State private var chip = "all"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Colour tokens") { Swatches() }
            section("Buttons") {
                HStack(spacing: 10) {
                    Button("Normal") {}.buttonStyle(.reins(.normal))
                    Button("Primary") {}.buttonStyle(.reins(.primary))
                    Button("Remove") {}.buttonStyle(.reins(.danger))
                    Button("Add to Codex") {}.buttonStyle(.reins(.dashed))
                    Button { } label: { Image(systemName: "trash").accessibilityLabel("Remove") }.buttonStyle(.reins(.icon))
                    Button("Disabled") {}.buttonStyle(.reins(.normal)).disabled(true)
                    Spacer(minLength: 0)
                }
            }
            section("Tags, CLI tag and dot, key caps") {
                HStack(spacing: 10) {
                    Tag("neutral")
                    Tag("never ran", tone: .warn)
                    Tag("17 errors", tone: .danger)
                    Tag("synced", tone: .success)
                    Tag("plugin: neon", systemImage: "lock")
                    CLITag(.claude)
                    CLITag(.codex)
                    HStack(spacing: 6) { CLIDot(.claude); CLIDot(.codex) }
                    Kbd("\u{2318}K")
                    Kbd("Esc")
                    Spacer(minLength: 0)
                }
            }
            section("Segmented control and filter chips") {
                HStack(spacing: 16) {
                    SegmentedControl(label: "Rule", options: [
                        SegmentOption("Allow", value: "allow"),
                        SegmentOption("Ask", value: "ask"),
                        SegmentOption("Deny", value: "deny"),
                    ], selection: $segment)
                    SegmentedControl(label: "Scope", options: [
                        SegmentOption("Global", value: "global"),
                        SegmentOption("Project", value: "project", count: 3),
                    ], selection: $scope)
                    HStack(spacing: 6) {
                        FilterChip("All", count: 6, isOn: chip == "all") { chip = "all" }
                        FilterChip("In one CLI only", count: 4, isOn: chip == "one") { chip = "one" }
                        FilterChip("Never ran", count: 1, isOn: chip == "never") { chip = "never" }
                    }
                    Spacer(minLength: 0)
                }
            }
            section("Grouped list, rows and the five usage states") { DemoLoadoutList() }
            section("Rows") {
                GroupedList {
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
                    Row(onActivate: {}) { RowText("PostToolUse \u{00B7} Edit|Write", subtitle: "prettier --write \"$FILE\"", mono: true) }
                        .lead { Image(systemName: "bolt") }
                        .cells { CLIDot(.claude); CLIDot(.codex) }
                    EmptyRow("Nothing matches this filter.")
                }
            }
            section("Banner") {
                VStack(spacing: 10) {
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
                HStack(spacing: 14) {
                    ToastView(toast: Toast(message: "Removed ponytail", tone: .info, action: .undo {}), run: {}, dismiss: {})
                    ToastView(toast: Toast(message: "Could not write settings.json", tone: .danger, action: nil), run: {}, dismiss: {})
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, 28)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel(title)
            content()
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
                    Text("Component gallery").font(ReinsFont.title).accessibilityAddTraits(.isHeader)
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
        .background(Palette.background)
        .ignoresSafeArea()
    }
}

private struct Swatches: View {
    private let tokens: [(String, Color)] = [
        ("background", Palette.background), ("sidebar", Palette.sidebar), ("surface", Palette.surface),
        ("surfaceRaised", Palette.surfaceRaised), ("border", Palette.border), ("track", Palette.track),
        ("selection", Palette.selection), ("hover", Palette.hover), ("accent", Palette.accent),
        ("accentSolid", Palette.accentSolid), ("text", Palette.text), ("textSecondary", Palette.textSecondary),
        ("textTertiary", Palette.textTertiary), ("claude", Palette.claude), ("codex", Palette.codex),
        ("success", Palette.success), ("warn", Palette.warn), ("danger", Palette.danger),
    ]

    var body: some View {
        let rows = stride(from: 0, to: tokens.count, by: 9).map { Array(tokens[$0..<min($0 + 9, tokens.count)]) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row, id: \.0) { token in
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(token.1)
                                .frame(height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                            Text(token.0).font(ReinsFont.tiny).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
