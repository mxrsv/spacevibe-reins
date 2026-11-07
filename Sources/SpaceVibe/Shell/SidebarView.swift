import SwiftUI

/// Left column: room for the traffic lights, the tabs with their counts and the Limits entry after them, the Limits tiles
/// above the footer, and a footer with scan status, the Settings button and the theme toggle. Tabs are plain buttons; `⌘1`..`⌘3` (View menu)
/// switch too, and `⌘L` opens Limits.
struct SidebarView: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Metrics.sidebarItemSpacing) {
                ForEach(shell.tabs, id: \.id) { tab in
                    SidebarItem(
                        title: tab.title, icon: tab.icon, count: tab.badge?.value, alert: tab.badge?.alert ?? false,
                        spokenCount: tab.badge?.spoken, isActive: tab.id == shell.activeID && !shell.isLimitsOpen
                    ) { shell.select(tab.id) }
                }
                LimitsSidebarItem()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            Spacer(minLength: 0)
            LimitsSidebarBlock()
                .padding(.bottom, Space.s12)
            HStack(spacing: Space.s8) {
                if let status = shell.statusMessage {
                    Text(status)
                        .spaceVibeText(.caption, tone: .tertiary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer(minLength: 0)
                Button { shell.openSettings() } label: { SpaceVibeIcon(.settings) }
                    .buttonStyle(.spaceVibe(.plainIcon))
                    .help("Settings (\u{2318},)")
                    .accessibilityLabel("Settings")
                ThemeToggle()
            }
            .padding(.horizontal, Metrics.sidebarItemPadding)
        }
        .sidebarSurface()
    }
}
