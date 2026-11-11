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
    let body: Body

    enum Body {
        /// In-memory, done when it returns (Dismiss in Activity): runs at once, even while a write's Undo is running.
        case sync(@MainActor () -> Void)
        /// A journal write: the center waits for it so Undos run one at a time.
        case async(@MainActor () async -> Void)
    }
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
/// `undoLast()`, so one Undo never runs twice. Undos run one at a time: while one is running (`isUndoing`), `Z`, the palette
/// and the toast button do nothing, so key repeat cannot drain the stack or race two journal writes.
/// `show(_:sessionUndo: false)` keeps the Undo on its own toast only, for a change that is not a write (Dismiss in Activity).
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    /// Undos not yet run, oldest first. The newest is the one `undoLast()` runs.
    private(set) var undoStack: [UndoItem] = []
    static let undoDepth = 20
    /// An Undo is running; no other starts until it completes.
    private(set) var isUndoing = false
    /// A page's bottom bar is on screen, so the v5 toast sits above it (V5-R32, 104 rather than 48). Set by `ListPaneLayout`.
    var isOverBottomBar = false

    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The Undo the toast showing now offers, if it offers one; `current` and this share an id while it is on screen.
    @ObservationIgnored private var currentUndo: UndoItem?
    private let announce: Bool

    /// `announce: false` for headless rendering, where there is no accessibility client.
    init(announce: Bool = true) { self.announce = announce }

    /// `undo` is in-memory and finishes when it returns; `sessionUndo: false` keeps it on its own toast only.
    func show(_ message: String, tone: ToastTone = .info, sessionUndo: Bool = true, undo: (@MainActor () -> Void)? = nil) {
        guard let undo else {
            present(Toast(message: message, tone: tone, action: nil))
            return
        }
        offer(message, tone: tone, sessionUndo: sessionUndo, body: .sync(undo))
    }

    /// An Undo that awaits a journal write: while it runs, no other Undo starts.
    func show(_ message: String, tone: ToastTone = .info, asyncUndo: @escaping @MainActor () async -> Void) {
        offer(message, tone: tone, sessionUndo: true, body: .async(asyncUndo))
    }

    private func offer(_ message: String, tone: ToastTone, sessionUndo: Bool, body: UndoItem.Body) {
        let id = UUID()
        let item = UndoItem(id: id, label: message, body: body)
        // The toast's button takes its item off the stack first, so a later `Z` cannot replay it.
        let action = ToastAction.undo { [weak self] in self?.run(item) }
        currentUndo = item
        if sessionUndo {
            undoStack.append(item)
            if undoStack.count > Self.undoDepth { undoStack.removeFirst(undoStack.count - Self.undoDepth) }
        }
        present(Toast(id: id, message: message, tone: tone, action: action))
    }

    /// Pops the newest Undo and runs it. A toast still showing for that item is hidden with it. Does nothing while an Undo runs.
    func undoLast() {
        guard !isUndoing, let item = undoStack.last else { return }
        dismiss(id: item.id)
        run(item)
    }

    /// The toast showing offers an Undo that is not on the session stack (Dismiss in Activity).
    private var isOffStackUndoShowing: Bool {
        guard let item = currentUndo, item.id == current?.id else { return false }
        return !undoStack.contains { $0.id == item.id }
    }

    /// Whether the `Z` key has an Undo to run: the session stack's newest, or the one on the toast showing.
    var canUndoByKey: Bool { !undoStack.isEmpty || isOffStackUndoShowing }

    /// The `Z` key. The Undo on the toast showing wins when it is not on the session stack, so the key runs what the toast
    /// names; otherwise the newest of the stack.
    func undoKey() {
        if isOffStackUndoShowing { runCurrentAction() } else { undoLast() }
    }

    /// Takes the item off the stack and runs it. An async item holds `isUndoing` until its closure returns.
    private func run(_ item: UndoItem) {
        switch item.body {
        case .sync(let work):
            removeUndo(id: item.id)
            work()
        case .async(let work):
            guard !isUndoing else { return }
            isUndoing = true
            removeUndo(id: item.id)
            Task { [weak self] in
                await work()
                self?.isUndoing = false
            }
        }
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

    /// Runs the action of the current toast, then hides it. A write's Undo that cannot start yet leaves the toast up.
    func runCurrentAction() {
        guard let toast = current else { return }
        // A write's Undo cannot start while another runs: the toast stays, so the button can be pressed again.
        if isUndoing, let item = currentUndo, item.id == toast.id, case .async = item.body { return }
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
