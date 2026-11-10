import SwiftUI

/// The v5 window (V5-R49 to V5-R51): the sidebar and the content panel on the window's ground, with Settings covering both,
/// the palette and the toast above, and the one `overlayHost()` that draws every menu and popover. As in the old shell every
/// tab's content stays mounted so a hidden tab keeps its filters and scroll position; only the active one is visible,
/// hit-testable, focusable and read by VoiceOver.
struct AppShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                AppSidebar()
                ContentPanel(hints: hints, source: shell.activeTab.source) {
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

            if let modal = shell.activeTab.modal {
                modal.transition(.opacity)
            }

            if shell.isPaletteOpen {
                AppCommandPalette()
                    .transition(.opacity)
            }
            ToastHost(isV5: true)
        }
        .pageBackground()
        .ignoresSafeArea()
        .overlayHost()
    }

    /// The active tab's keys, plus `Z undo` while the session holds an Undo.
    private var hints: [KeyHint] {
        let tabHints = shell.activeTab.hints
        return toasts.undoStack.isEmpty ? tabHints : tabHints + [KeyHint(keys: ToastAction.undoKeyCap, label: "undo")]
    }
}
