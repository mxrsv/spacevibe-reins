import SwiftUI

/// Draws the current toast over the window, above the hint bar. Mounted once by `ShellView`. In the v5 shell (`isV5`) it
/// is the v5 toast (`ToastBar`), 24 from the content panel's right edge and 48 above its bottom, and its action's key, `Z` for
/// Undo, runs it from anywhere while the toast shows.
struct ToastHost: View {
    var isV5 = false

    @Environment(ToastCenter.self) private var toasts
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
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let toast = toasts.current {
                    ZStack {
                        ToastBar(toast: toast, run: toasts.runCurrentAction)
                        if toast.action?.keyCap == ToastAction.undoKeyCap {
                            Button("Undo", action: toasts.runCurrentAction)
                                .keyboardShortcut(KeyEquivalent(Character(ToastAction.undoKeyCap.lowercased())), modifiers: [])
                                .opacity(0)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .onHover { $0 ? toasts.hold() : toasts.release() }
                    .padding(.trailing, Metrics.ContentPanel.inset + Metrics.Toast.trailingInset)
                    .padding(.bottom, Metrics.ContentPanel.inset + Metrics.Toast.bottomInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.toast), value: toasts.current?.id)
        .allowsHitTesting(toasts.current != nil)
    }
}
