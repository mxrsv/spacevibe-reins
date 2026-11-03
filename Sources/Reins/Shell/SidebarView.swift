import SwiftUI

/// Left column: room for the traffic lights, the tabs with their counts, and a footer with scan status and the
/// theme toggle. Tabs are plain buttons; `⌘1`..`⌘3` (View menu) switch too.
struct SidebarView: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Space.s2) {
                ForEach(shell.tabs, id: \.id) { tab in
                    SidebarItem(
                        title: tab.title, systemImage: tab.systemImage, count: tab.badge?.value, alert: tab.badge?.alert ?? false,
                        spokenCount: tab.badge?.spoken, isActive: tab.id == shell.activeID
                    ) { shell.select(tab.id) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            Spacer(minLength: 0)
            HStack(spacing: Space.s8) {
                if let status = shell.statusMessage {
                    Text(status)
                        .reinsText(.caption, tone: .tertiary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer(minLength: 0)
                ThemeToggle()
            }
            .padding(.horizontal, Space.s4)
        }
        .sidebarSurface()
    }
}
