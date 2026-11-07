import SwiftUI

/// The confirmation in front of Stop, the one action with no Undo. Cancel holds the focus and Esc cancels; neither works
/// while the stop runs. The text says plainly what happens and that it cannot be undone.
struct ActivityStopConfirmation: View {
    let title: String
    let isStopping: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ConfirmationDialog(
            "Stop \(title)?",
            message: "The current turn ends and work already done stays. This cannot be undone.",
            spokenLabel: "Stop \(title)? This cannot be undone.",
            canCancel: !isStopping,
            cancel: cancel
        ) {
            Button("Cancel", action: cancel)
                .buttonStyle(.reins(.normal))
                .reinsFocusable(cornerRadius: Metrics.controlRadius, focusOnAppear: true)
                .disabled(isStopping)
                .keyboardShortcut(.cancelAction)
            Button(isStopping ? "Stopping\u{2026}" : "Stop", action: confirm)
                .buttonStyle(.reins(.danger))
                .disabled(isStopping)
        }
    }
}
