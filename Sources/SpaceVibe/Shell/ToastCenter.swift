import Observation
import SwiftUI

enum ToastTone { case info, danger }

/// The one button a toast can carry. Undo is the common case; without an action the toast offers only dismiss.
struct ToastAction {
    let title: String
    let icon: SpaceVibeGlyph
    /// The key that runs it, shown as a cap in the v5 toast: `Z` for Undo (V5-R38).
    var keyCap: String?
    let run: @MainActor () -> Void

    /// The key cap Undo carries; the v5 toast host binds the same key (lowercased) while the toast shows.
    static let undoKeyCap = "Z"

    static func undo(_ run: @escaping @MainActor () -> Void) -> ToastAction {
        ToastAction(title: "Undo", icon: .undo, keyCap: undoKeyCap, run: run)
    }
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let tone: ToastTone
    let action: ToastAction?
}

/// The one toast the app shows, bottom centre. Every write calls `show` with an Undo closure.
///
///     @Environment(ToastCenter.self) private var toasts
///     toasts.show("Removed ponytail") { journal.undo(entry) }          // trailing closure is `undo`
///     toasts.show("Could not write settings.json", tone: .danger)
///     toasts.show("SpaceVibe 0.2.0 is available", action: viewUpdate)      // any other single action
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
        present(Toast(message: message, tone: tone, action: undo.map(ToastAction.undo)))
    }

    /// Returns the toast's id, for `dismiss(id:)`.
    @discardableResult
    func show(_ message: String, tone: ToastTone = .info, action: ToastAction) -> UUID {
        let toast = Toast(message: message, tone: tone, action: action)
        present(toast)
        return toast.id
    }

    func dismiss() {
        timer?.cancel()
        current = nil
    }

    /// Hides that toast only: one that replaced it stays.
    func dismiss(id: UUID) {
        if current?.id == id { dismiss() }
    }

    /// Runs the action of the current toast, then hides it.
    func runCurrentAction() {
        guard let toast = current else { return }
        dismiss()
        toast.action?.run()
    }

    /// While the pointer rests on the toast the countdown stops; leaving restarts it.
    func hold() { timer?.cancel() }

    func release() {
        if let id = current?.id { schedule(for: id) }
    }

    private func present(_ toast: Toast) {
        current = toast
        schedule(for: toast.id)
        if announce {
            AccessibilityNotification.Announcement(toast.action.map { "\(toast.message). \($0.title) available." } ?? toast.message).post()
        }
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
