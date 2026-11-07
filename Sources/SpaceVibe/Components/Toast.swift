import SwiftUI

/// The toast itself: inverted surface, message, its action (or a dismiss button when it has none). 40 pt: 6 around a 28 pt button.
struct ToastView: View {
    let toast: Toast
    let run: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s12) {
            if toast.tone == .danger {
                SpaceVibeIcon(.warning)
            }
            Text(toast.message).spaceVibeText(.body)
            if let action = toast.action {
                Button(action: run) {
                    HStack(spacing: Space.s6) {
                        SpaceVibeIcon(action.icon)
                        Text(action.title)
                    }
                    .spaceVibeText(.bodyStrong)
                }
                .buttonStyle(.spaceVibe(.inverse))
            } else {
                Button(action: dismiss) { SpaceVibeIcon(.close) }
                    .buttonStyle(.spaceVibe(.inverse))
                    .accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(TextTone.inverse.color)
        .padding(.leading, Space.s16)
        .padding(.trailing, Space.s6)
        .padding(.vertical, Space.s6)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.text))
        .shadow(color: Palette.overlayShadow, radius: Metrics.toastShadowRadius, y: Metrics.toastShadowOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
    }
}
