import SwiftUI

/// The window: sidebar, top bar, the active tab, hint bar, and the overlays (palette, toast).
/// Every tab's content stays mounted so a hidden tab keeps its filters and scroll position; only the active
/// one is visible, hit-testable, focusable and read by VoiceOver.
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
                            let isActive = tab.id == shell.activeID
                            tab.content
                                .opacity(isActive ? 1 : 0)
                                .allowsHitTesting(isActive)
                                .accessibilityHidden(!isActive)
                                .disabled(!isActive)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HintBar(hints: shell.activeTab.hints)
                }
            }
            .accessibilityHidden(shell.isPaletteOpen)

            if shell.isPaletteOpen {
                CommandPalette()
                    .transition(.opacity)
            }
            ToastHost()
        }
        .background(Palette.background)
        .ignoresSafeArea()
    }
}
