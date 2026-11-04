import ReinsCore
import SwiftUI

/// Settings > Appearance: Theme as three tiles, Font size over two Loadout rows that show it, and the interface language.
struct AppearanceSettings: View {
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        VStack(spacing: Rhythm.cards) {
            GroupedList {
                CardHeader("Theme", lead: { PageIcon(.palette, size: .row) })
                HStack(spacing: Rhythm.tiles) {
                    ForEach(ThemeSetting.allCases, id: \.self) { theme in
                        ThemeTile(title: theme.title, icon: theme.icon, appearance: theme.fixed?.colorScheme, isSelected: appearance.theme == theme) {
                            appearance.theme = theme
                        }
                    }
                }
                .padding(.horizontal, Metrics.rowInset)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Theme")
                .groupedListPart(.plain)
            }

            GroupedList {
                CardHeader("Font size", lead: { PageIcon(.text, size: .row) }, columns: {
                    SegmentedControl(label: "Font size", options: FontSizeChoice.allCases.map { SegmentOption($0.title, value: $0) },
                                     selection: $appearance.fontSize)
                })
                FontSizeSample()
                    .padding(.horizontal, Metrics.rowHorizontalPadding)
                    .padding(.bottom, Space.s8)
                    .groupedListPart(.plain)
            }

            GroupedList {
                CardHeader("Language", lead: { PageIcon(.globe, size: .row) }, columns: {
                    Text(SettingsWording.language).reinsText(.body, tone: .secondary)
                })
            }
        }
    }
}

/// Two rows as Loadout draws them (synthetic names from the fixture home), so the size is judged on real rows.
private struct FontSizeSample: View {
    var body: some View {
        RaisedBlock(inset: EdgeInsets(top: Space.s4, leading: 0, bottom: Space.s4, trailing: 0)) {
            sampleRow("ponytail", "Pick the laziest solution that works", runs: 142)
            RowDivider()
            sampleRow("impeccable", "Design, critique and polish a frontend interface", runs: 87)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample rows at this font size")
    }

    private func sampleRow(_ name: String, _ description: String, runs: Int) -> some View {
        Row { RowText(name, subtitle: description) }
            .lead { PageIcon(.skill, size: .row) }
            .cells { UsageCell(cli: .claude, model: .counted(runs: runs), max: 142) }
    }
}
