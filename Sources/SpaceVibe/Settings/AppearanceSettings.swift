import SwiftUI

/// Settings > Appearance: Theme as three tiles, Font size over two Skills rows that show it, the Session widget switch and the
/// CLIs the app shows. No Language card while English is the only language (D69).
struct AppearanceSettings: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.openStateStore) private var store
    @Environment(\.glancePreferences) private var glancePreferences
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var appearance = appearance
        VStack(spacing: Rhythm.card) {
            Tile("Theme", isOpen: open("theme")) {
                HStack(spacing: Rhythm.tiles) {
                    ForEach(ThemeSetting.allCases, id: \.self) { theme in
                        ThemeTile(title: theme.title, glyph: theme.icon, appearance: theme.fixed?.colorScheme, isSelected: appearance.theme == theme) {
                            appearance.theme = theme
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Theme")
            }

            Tile("Font size", isOpen: open("fontSize")) {
                FontSizeSample()
            } actions: {
                SegmentedControl(label: "Font size", options: FontSizeChoice.allCases.map { SegmentOption($0.title, value: $0) },
                                 selection: $appearance.fontSize)
            }

            GlanceSettings(preferences: glancePreferences ?? .shared, isOpen: open("glanceWidget"))

            CLISettings(env: env, isOpen: open("clis"))
        }
    }

    private func open(_ id: String) -> Binding<Bool> {
        store.binding(page: SettingsScreen.page, id: id, byDefault: true)
    }
}

/// Two rows as the Skills list draws them (synthetic names from the fixture home), so the size is judged on real rows. They
/// show and take no click.
private struct FontSizeSample: View {
    var body: some View {
        ListRows {
            // One sample in every CLI, one in the first only.
            sampleRow("ponytail", in: Set(CLICatalog.current.inventoryCLIs))
            sampleRow("impeccable", in: Set(CLICatalog.current.inventoryCLIs.prefix(1)))
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample rows at this font size")
    }

    private func sampleRow(_ name: String, in clis: Set<CLIID>) -> some View {
        ListRow(name, lead: CategoryGlyph.skill) {
            LogoStrip {
                ForEach(CLICatalog.current.inventoryCLIs, id: \.self) { cli in
                    LogoToggle(cli: cli, isLit: clis.contains(cli), mode: .readOnly) {}
                }
            }
            WarningSlot()
        }
    }
}
