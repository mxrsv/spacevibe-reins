import SwiftUI

/// Draws the current toast over the window, above the hint bar. Mounted once by `ShellView`.
struct ToastHost: View {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                ToastView(toast: toast, undo: toasts.undoCurrent, dismiss: toasts.dismiss)
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

/// The toast itself: inverted surface, message, Undo (or a dismiss button when there is nothing to undo).
struct ToastView: View {
    let toast: Toast
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if toast.tone == .danger {
                Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            }
            Text(toast.message).font(ReinsFont.body)
            if toast.undo != nil {
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward").font(ReinsFont.bodyStrong)
                }
                .buttonStyle(.reins(.inverse))
            } else {
                Button(action: dismiss) { Image(systemName: "xmark").accessibilityLabel("Dismiss") }
                    .buttonStyle(.reins(.inverse))
            }
        }
        .foregroundStyle(Palette.background)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.text))
        .shadow(color: Palette.overlayShadow, radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
    }
}
