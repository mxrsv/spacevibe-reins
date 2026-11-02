import Observation
import SwiftUI

enum ToastTone { case info, danger }

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let tone: ToastTone
    let undo: (@MainActor () -> Void)?
}

/// The one toast the app shows, bottom centre. Every write calls `show` with an Undo closure.
///
///     @Environment(ToastCenter.self) private var toasts
///     toasts.show("Removed ponytail") { journal.undo(entry) }          // trailing closure is `undo`
///     toasts.show("Could not write settings.json", tone: .danger)
///
/// A new toast replaces the current one. It disappears after about 7 seconds, paused while the pointer is on it.
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?

    @ObservationIgnored private var timer: Task<Void, Never>?
    private let announce: Bool

    /// `announce: false` for headless rendering, where there is no accessibility client.
    init(announce: Bool = true) { self.announce = announce }

    func show(_ message: String, tone: ToastTone = .info, undo: (@MainActor () -> Void)? = nil) {
        let toast = Toast(message: message, tone: tone, undo: undo)
        current = toast
        schedule(for: toast.id)
        if announce {
            AccessibilityNotification.Announcement(undo == nil ? message : "\(message). Undo available.").post()
        }
    }

    func dismiss() {
        timer?.cancel()
        current = nil
    }

    /// Runs the Undo closure of the current toast, then hides it.
    func undoCurrent() {
        guard let toast = current else { return }
        dismiss()
        toast.undo?()
    }

    /// While the pointer rests on the toast the countdown stops; leaving restarts it.
    func hold() { timer?.cancel() }

    func release() {
        if let id = current?.id { schedule(for: id) }
    }

    private func schedule(for id: UUID) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: Metrics.toastDuration)
            guard !Task.isCancelled, let self, self.current?.id == id else { return }
            self.current = nil
        }
    }
}
