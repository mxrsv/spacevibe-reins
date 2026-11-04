import SwiftUI

/// Settings over the whole window (spec `docs/specs/2026-11-04-reins-settings.md`, mock A2): the rail of sections at the
/// top with the back button after the window buttons, one centred column of cards, and a hint bar with only `Esc`.
struct SettingsScreen: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(spacing: 0) {
            rail
            ReinsScrollView {
                Group {
                    switch shell.settingsSection {
                    case .appearance: AppearanceSettings()
                    case .update: UpdateSettings()
                    }
                }
                .frame(width: Metrics.settingsColumnWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s16)
                .padding(.bottom, Metrics.pageBottomPadding)
            }
            HintBar(hints: [KeyHint(keys: "Esc", label: "Back to \(shell.title)")], shellKeys: false)
        }
        .pageBackground()
    }

    private var rail: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: Space.s4) {
                ForEach(SettingsSection.allCases) { section in
                    RailTab(title: section.title, icon: section.icon, isActive: section == shell.settingsSection) {
                        shell.settingsSection = section
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")

            Button { shell.closeSettings() } label: { Chevron(.left) }
                .buttonStyle(.reins(.plainIcon))
                // `Esc` belongs to the palette while it is open over Settings.
                .keyboardShortcut(shell.isPaletteOpen ? nil : .cancelAction)
                .help("Back to \(shell.title) (Esc)")
                .accessibilityLabel("Back to \(shell.title)")
                .padding(.leading, Metrics.trafficLightsWidth)
                .padding(.top, Space.s8)
        }
    }
}
