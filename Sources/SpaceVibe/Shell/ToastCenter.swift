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
    let id: UUID
    let message: String
    let tone: ToastTone
    let action: ToastAction?

    init(id: UUID = UUID(), message: String, tone: ToastTone, action: ToastAction?) {
        self.id = id
        self.message = message
        self.tone = tone
        self.action = action
    }
}

/// One Undo the session can still run: the toast that offered it, its message ("Removed ponytail") and the closure.
struct UndoItem: Identifiable {
    let id: UUID
    let label: String
    let run: @MainActor () -> Void
}

/// The one toast the app shows, bottom centre. Every write calls `show` with an Undo closure.
///
///     @Environment(ToastCenter.self) private var toasts
///     toasts.show("Removed ponytail") { journal.undo(entry) }          // trailing closure is `undo`
///     toasts.show("Could not write settings.json", tone: .danger)
///     toasts.show("SpaceVibe 0.2.0 is available", action: viewUpdate)      // any other single action
///
/// A new toast replaces the current one. It disappears after 5 seconds (`Metrics.toastDuration`), paused while the pointer is on it.
///
/// Every `undo:` also goes onto a session stack (`undoStack`, newest last, `undoDepth` deep), so a toast that replaced the
/// one carrying an Undo does not lose it: `undoLast()`, the `Z` key and the palette run the newest item. The stack lives
/// for this session only and never reads the Journal. An item leaves the stack when it runs, from the toast or from
/// `undoLast()`, so one Undo never runs twice.
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    /// Undos not yet run, oldest first. The newest is the one `undoLast()` runs.
    private(set) var undoStack: [UndoItem] = []
    static let undoDepth = 20
    /// A page's bottom bar is on screen, so the v5 toast sits above it (V5-R32, 104 rather than 48). Set by `ListPaneLayout`.
    var isOverBottomBar = false

    @ObservationIgnored private var timer: Task<Void, Never>?
    private let announce: Bool

    /// `announce: false` for headless rendering, where there is no accessibility client.
    init(announce: Bool = true) { self.announce = announce }

    func show(_ message: String, tone: ToastTone = .info, undo: (@MainActor () -> Void)? = nil) {
        guard let undo else {
            present(Toast(message: message, tone: tone, action: nil))
            return
        }
        let id = UUID()
        // The toast's button takes its item off the stack first, so a later `Z` cannot replay it.
        let action = ToastAction.undo { [weak self] in
            self?.removeUndo(id: id)
            undo()
        }
        undoStack.append(UndoItem(id: id, label: message, run: undo))
        if undoStack.count > Self.undoDepth { undoStack.removeFirst(undoStack.count - Self.undoDepth) }
        present(Toast(id: id, message: message, tone: tone, action: action))
    }

    /// Pops the newest Undo and runs it. A toast still showing for that item is hidden with it.
    func undoLast() {
        guard let item = undoStack.popLast() else { return }
        dismiss(id: item.id)
        item.run()
    }

    private func removeUndo(id: UUID) {
        undoStack.removeAll { $0.id == id }
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
