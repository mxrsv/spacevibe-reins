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
                .buttonStyle(.spaceVibe(.normal))
                .spaceVibeFocusable(cornerRadius: Metrics.controlRadius, focusOnAppear: true)
                .disabled(isStopping)
                .keyboardShortcut(.cancelAction)
            Button(isStopping ? "Stopping\u{2026}" : "Stop", action: confirm)
                .buttonStyle(.spaceVibe(.danger))
                .disabled(isStopping)
        }
    }
}

/// The words of the v5 Stop confirmation and of the toast after it (V5-R59). The pid is the session's real one; the core
/// looks it up again before it sends anything, and the dialog says so.
enum ActivityStopWording {
    static func title(_ session: CoreActivitySession) -> String { "Stop \(quoted(session.title, limit: nil))?" }

    /// "Sends SIGTERM to pid 41002 (Claude Code, spacevibe-academy). ..." with the pid in bold.
    static func message(_ session: CoreActivitySession) -> Text {
        let who = [session.cli.label, session.project].compactMap { $0 }.joined(separator: ", ")
        return Text("Sends SIGTERM to pid ") + Text(String(session.pid)).bold()
            + Text(" (\(who)). Unsaved work in that session may be lost. This cannot be undone.")
    }

    /// The same sentence as plain text, for VoiceOver and the tests.
    static func plainMessage(_ session: CoreActivitySession) -> String {
        let who = [session.cli.label, session.project].compactMap { $0 }.joined(separator: ", ")
        return "Sends SIGTERM to pid \(session.pid) (\(who)). Unsaved work in that session may be lost. This cannot be undone."
    }

    static let note = "SpaceVibe checks that the pid still belongs to this session before it sends anything."
    static let confirmTitle = "Stop session"

    /// After the core answered: what was sent, and whether the process went away. No Undo.
    static func toast(_ session: CoreActivitySession, exited: Bool) -> String {
        exited ? "Sent SIGTERM to pid \(session.pid). \(quoted(session.title, limit: nil)) is stopped."
            : "Sent SIGTERM to pid \(session.pid), but \(quoted(session.title, limit: nil)) is still running."
    }

    /// A title in curly quotes; a long one is cut for a toast.
    static func quoted(_ text: String, limit: Int? = 48) -> String {
        let shown = limit.map { text.count > $0 ? String(text.prefix($0 - 1)) + "\u{2026}" : text } ?? text
        return "\u{201C}\(shown)\u{201D}"
    }
}

/// The v5 Stop confirmation: `ConfirmationPanel` with the V5-R59 words, for the session the model's `pendingStop` names.
struct StopSessionPanel: View {
    let session: CoreActivitySession
    let isStopping: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ConfirmationPanel(
            title: ActivityStopWording.title(session), message: ActivityStopWording.message(session), note: ActivityStopWording.note,
            confirmTitle: ActivityStopWording.confirmTitle, confirmGlyph: .stop, isWorking: isStopping, cancel: cancel, confirm: confirm)
    }
}
