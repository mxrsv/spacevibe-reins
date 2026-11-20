import SwiftUI

/// Development-only specimens, split to stay below ImageRenderer's maximum image height.
struct ComponentGalleryContent: View {
    enum Part { case all, first, second, third, fourth, fifth }
    var part: Part = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if part == .all || part == .first {
                section("Colour tokens") { Swatches() }
                section("Text roles") { TypeRoles() }
                section("Settings controls") { SettingsSpecimens() }
            }
            if part == .all || part == .second {
                section("Category, content and verdict glyphs") { GlyphSpecimens() }
            }
            if part == .all || part == .third {
                section("Containers") { ContainerSpecimens() }
            }
            if part == .all || part == .fourth {
                section("Controls and overlays") { ControlSpecimens() }
                section("Sidebar and content panel") { ShellSpecimens() }
            }
            if part == .all || part == .fifth {
                section("Skills detail pane") { PaneSpecimens() }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text(title)
                .spaceVibeText(.cardTitle, tone: .primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.s24)
            content()
        }
        .padding(.horizontal, Space.s24)
    }
}

/// Every text role with its size, line box and weight, set in itself.
private struct TypeRoles: View {
    private let roles: [(String, SpaceVibeType)] = [
        ("micro", .micro), ("small", .small), ("smallLabel", .smallLabel), ("meta", .meta), ("metaLabel", .metaLabel),
        ("metaLine", .metaLine), ("prose", .prose), ("rowName", .rowName), ("control", .control), ("controlStrong", .controlStrong),
        ("field", .field), ("dialogTitle", .dialogTitle), ("keyCap", .keyCap), ("cardTitle", .cardTitle), ("heading", .heading),
        ("answer", .answer),
    ]

    var body: some View {
        SpecimenLayout.panel("Name, size / line box, sample") {
            ForEach(roles, id: \.0) { name, role in
                HStack(spacing: Space.s12) {
                    Text(name).spaceVibeText(.meta, tone: .tertiary).frame(width: 160, alignment: .leading)
                    Text("\(Int(role.size)) / \(Int(role.lineBox))").spaceVibeText(.meta, tone: .tertiary).frame(width: 72, alignment: .leading)
                    Text("ponytail \u{00B7} Add to Codex \u{00B7} 1,204")
                        .spaceVibeText(role, tone: .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
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
                    Text("Component gallery").spaceVibeText(.cardTitle).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button { toasts.show("Removed ponytail", undo: { toasts.show("Undone: removed ponytail") }) } label: {
                        ActionLabel("Toast with Undo")
                    }
                    .buttonStyle(ActionButtonStyle(size: .compact))
                    Button { toasts.show("Could not write settings.json", tone: .danger) } label: { ActionLabel("Error toast") }
                        .buttonStyle(ActionButtonStyle(size: .compact))
                    ThemeToggle()
                }
                .padding(.leading, Space.s24 + 70)
                .padding(.trailing, Space.s24)
                .padding(.top, 16)
                .padding(.bottom, 4)
                SpaceVibeScrollView { ComponentGalleryContent() }
            }
            ToastHost()
        }
        .overlayHost()
        .background(Palette.bgSide)
        .ignoresSafeArea()
    }
}

private struct Swatches: View {
    private let tokens: [(String, Color)] = [
        ("bgSide", Palette.bgSide), ("bgApp", Palette.bgApp), ("bgPanel", Palette.bgPanel), ("bgRaise", Palette.bgRaise),
        ("bgSunk", Palette.bgSunk), ("bgPop", Palette.bgPop), ("hair", Palette.hair), ("hair2", Palette.hair2),
        ("sel", Palette.sel), ("hover", Palette.hover), ("accent", Palette.accent), ("accentSolid", Palette.accentSolid),
        ("fg", Palette.fg), ("fg2", Palette.fg2), ("fg3", Palette.fg3), ("fg4", Palette.fg4),
        ("claude", CLIRegistry.look(.claude).tone.fill), ("codex", CLIRegistry.look(.codex).tone.fill), ("ok", Palette.ok), ("warn", Palette.warn), ("bad", Palette.bad),
    ]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        let rows = stride(from: 0, to: tokens.count, by: 7).map { Array(tokens[$0..<min($0 + 7, tokens.count)]) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row, id: \.0) { token in
                        VStack(alignment: .leading, spacing: 4) {
                            shape
                                .fill(token.1)
                                .frame(height: 28)
                                .overlay(shape.strokeBorder(Palette.hair2, lineWidth: Metrics.Radius.edge))
                            Text(token.0).spaceVibeText(.meta, tone: .tertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Settings' own blocks: the rail tabs, the Theme tiles, the segmented control, the switch on, off and disabled, and the mark.
private struct SettingsSpecimens: View {
    @State private var section = SettingsSection.appearance
    @State private var theme = ThemeSetting.dark
    @State private var size = FontSizeChoice.standard
    @State private var on = true
    @State private var off = false

    var body: some View {
        SpecimenLayout.panel("Rail tabs, Theme tiles, segmented control, switch (on, off, disabled), the SpaceVibe mark") {
            HStack(spacing: Space.s4) {
                ForEach(SettingsSection.allCases) { item in
                    RailTab(title: item.title, glyph: item.icon, isActive: item == section) { section = item }
                }
            }
            HStack(spacing: Rhythm.tiles) {
                ForEach(ThemeSetting.allCases, id: \.self) { item in
                    ThemeTile(title: item.title, glyph: item.icon, appearance: item.fixed?.colorScheme, isSelected: item == theme) { theme = item }
                }
            }
            .frame(width: Metrics.settingsColumnWidth)
            HStack(spacing: Space.s16) {
                SegmentedControl(label: "Font size", options: FontSizeChoice.allCases.map { SegmentOption($0.title, value: $0) }, selection: $size)
                SpaceVibeSwitch(label: "On", isOn: $on)
                SpaceVibeSwitch(label: "Off", isOn: $off)
                SpaceVibeSwitch(label: "Disabled", isOn: .constant(false)).disabled(true)
                SpaceVibeMark()
                Spacer(minLength: 0)
            }
        }
    }
}

/// Every glyph at 12, 14, 16 and 24 in the secondary tone, and at 16 in the warn colour and the tertiary tone (a lead icon),
/// two to a line: the category set, the content set, then the five verdict glyphs.
private struct GlyphSpecimens: View {
    private let sizes: [IconSize] = [.small, .inline, .control, .large]
    private let columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            SpecimenLayout.panel("Category glyphs (MingCute Line)") {
                specimenGrid(CategoryGlyph.allCases.map { glyph in
                    (glyph.iconName, { size, ink in SpaceVibeIcon(category: glyph, size: size, ink: ink) })
                })
            }
            SpecimenLayout.panel("Content glyphs (Phosphor Duotone)") {
                specimenGrid(ContentGlyph.allCases.map { glyph in
                    (glyph.iconName, { size, ink in SpaceVibeIcon(content: glyph, size: size, ink: ink) })
                })
            }
            SpecimenLayout.panel("Verdict glyphs") {
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
                            Text(item.0).spaceVibeText(.meta, tone: .tertiary).frame(width: 280, alignment: .leading)
                            ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                                item.1(size, nil).frame(width: Metrics.iconLarge)
                            }
                            item.1(.control, Palette.warn)
                            item.1(.control, Palette.fg3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(0 ..< columns - row.count, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .foregroundStyle(Palette.fg2)
    }
}
