import SwiftUI

/// The window: sidebar, top bar, the active tab (or the Limits page in its place), hint bar, and the overlays (palette,
/// toast). Every tab's content stays mounted so a hidden tab keeps its filters and scroll position; only the active
/// one is visible, hit-testable, focusable and read by VoiceOver, and none is while the Limits page shows. Settings
/// covers all of it, sidebar included, and leaves it mounted under itself.
struct ShellView: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                VStack(spacing: 0) {
                    TopBarView()
                    ZStack {
                        ForEach(shell.tabs, id: \.id) { tab in
                            let isActive = tab.id == shell.activeID && !shell.isLimitsOpen
                            tab.content
                                .opacity(isActive ? 1 : 0)
                                .allowsHitTesting(isActive)
                                .accessibilityHidden(!isActive)
                                .disabled(!isActive)
                        }
                        if shell.isLimitsOpen { LimitsScreen() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HintBar(hints: shell.hints)
                }
            }
            .opacity(shell.isSettingsOpen ? 0 : 1)
            .allowsHitTesting(!shell.isSettingsOpen)
            .disabled(shell.isSettingsOpen)
            .accessibilityHidden(shell.isPaletteOpen || shell.isSettingsOpen)

            if shell.isSettingsOpen {
                SettingsScreen()
                    .accessibilityHidden(shell.isPaletteOpen)
            }

            if shell.isPaletteOpen {
                CommandPalette()
                    .transition(.opacity)
            }
            ToastHost()
        }
        .pageBackground()
        .ignoresSafeArea()
    }
}
