import SwiftUI

/// The v5 sidebar (V5-R49, V5-R50): room for the window buttons, the product row, the search row that opens the palette, the
/// page items (Agents with its item count, Activity, Limits), the CLI status rows and the footer (Settings and the appearance
/// toggle). `⌘1` to `⌘3` (the View menu) pick the pages too. It also drives the Limits reads, which the CLI status rows
/// derive from, while the window is active.
struct AppSidebar: View {
    @Environment(ShellModel.self) private var shell
    @Environment(LimitsModel.self) private var limits
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: Metrics.AppSidebar.windowButtonsHeight)
            SidebarProductRow(name: SpaceVibeMark.productName)
            SidebarSearchRow(keyCap: "\u{2318}K", spokenKey: "Command K") { shell.openPalette() }
                .padding(.top, Metrics.AppSidebar.searchAbove)
                .padding(.bottom, Metrics.AppSidebar.searchBelow)
            VStack(spacing: Metrics.AppSidebar.itemSpacing) {
                ForEach(shell.tabs, id: \.id) { tab in
                    SidebarPageItem(
                        title: tab.title, glyph: tab.glyph, count: tab.badge?.value, spokenCount: tab.badge?.spoken,
                        isCurrent: tab.id == shell.activeID
                    ) { shell.select(tab.id) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            Spacer(minLength: 0)
            SidebarCLIStatusGroup {
                ForEach(CoreLimitsCLI.allCases, id: \.self) { cli in
                    SidebarCLIStatusRow(name: cli.label, cli: cli, state: CLIStatusDerivation.state(of: limits.limits(for: cli)))
                }
            }
            HStack(spacing: Metrics.AppSidebar.itemSpacing) {
                SidebarFooterButton(title: "Settings", glyph: ContentGlyph.sliders, keyHint: "\u{2318},") { shell.openSettings() }
                ThemeToggle()
            }
        }
        .appSidebarSurface()
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await limits.run()
        }
    }
}
