import SwiftUI

/// Draws the current toast over the window, above the hint bar. Mounted once by `ShellView`. In the v5 shell (`isV5`) it
/// is the v5 toast (`ToastBar`), 24 from the content panel's right edge and 48 above its bottom. `Z` runs the newest Undo of the
/// session (`ToastCenter.undoLast`) while the stack holds one, also after the toast that offered it has gone, unless the
/// palette, Settings, a confirmation or a menu holds the keyboard.
struct ToastHost: View {
    var isV5 = false

    @Environment(ToastCenter.self) private var toasts
    @Environment(ShellModel.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isV5 { panelToast } else { classic }
    }

    private var classic: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                ToastView(toast: toast, run: toasts.runCurrentAction, dismiss: toasts.dismiss)
                    .onHover { $0 ? toasts.hold() : toasts.release() }
                    .padding(.bottom, Metrics.toastBottomInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toasts.current?.id)
        .allowsHitTesting(toasts.current != nil)
    }

    private var panelToast: some View {
        ZStack {
            bar
            if isUndoKeyOn { undoKey }
        }
    }

    private var bar: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let toast = toasts.current {
                    ToastBar(toast: toast, run: toasts.runCurrentAction)
                        .onHover { $0 ? toasts.hold() : toasts.release() }
                        .padding(.trailing, Metrics.ContentPanel.inset + Metrics.Toast.trailingInset)
                        .padding(.bottom, Metrics.ContentPanel.inset + (toasts.isOverBottomBar ? Metrics.Toast.bottomInsetOverBar : Metrics.Toast.bottomInset))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.toast), value: toasts.current?.id)
        .allowsHitTesting(toasts.current != nil)
    }

    /// Not while the palette is open (its field takes plain keys), nor Settings, a confirmation or a menu: Undo writes a file.
    private var isUndoKeyOn: Bool {
        !toasts.undoStack.isEmpty && !shell.isPaletteOpen && !shell.isSettingsOpen && shell.activeTab.modal == nil && !shell.activeTab.isMenuOpen
    }

    private var undoKey: some View {
        Button("Undo", action: toasts.undoLast)
            .keyboardShortcut(KeyEquivalent(Character(ToastAction.undoKeyCap.lowercased())), modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
