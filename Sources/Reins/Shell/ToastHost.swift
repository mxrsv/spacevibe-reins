import SwiftUI

/// Draws the current toast over the window, above the hint bar. Mounted once by `ShellView`.
struct ToastHost: View {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
}
