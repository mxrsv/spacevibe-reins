import SwiftUI

/// The confirmation in front of Stop, the one action with no Undo. A scrim over the page and a card in the palette's
/// style; Cancel holds the focus and Esc cancels. It is a view rather than a system sheet so the same view renders in
/// the headless screenshots. The text says plainly what happens and that it cannot be undone.
struct ActivityStopConfirmation: View {
    let title: String
    let isStopping: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    @FocusState private var cancelFocused: Bool

    var body: some View {
        ZStack {
            Palette.overlay
                .ignoresSafeArea()
                .onTapGesture { if !isStopping { cancel() } }
                .accessibilityHidden(true)
            card
        }
        .onAppear { cancelFocused = true }
        .onExitCommand { if !isStopping { cancel() } }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.paletteRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Stop \(title)?")
                .font(ReinsFont.bodyStrong)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
            Text("The current turn ends and work already done stays. This cannot be undone.")
                .font(ReinsFont.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.reins(.normal))
                    .focused($cancelFocused)
                    .focusEffectDisabled()
                    .focusRing(cancelFocused, cornerRadius: Metrics.controlRadius)
                    .disabled(isStopping)
                    .keyboardShortcut(.cancelAction)
                Button(isStopping ? "Stopping\u{2026}" : "Stop", action: confirm)
                    .buttonStyle(.reins(.danger))
                    .disabled(isStopping)
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(width: 420)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.overlayShadow, radius: 30, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Stop \(title)? This cannot be undone.")
    }
}
