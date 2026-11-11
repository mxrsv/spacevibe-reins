import AppKit
import Foundation
import Observation

/// The Activity screen's state: the latest report, the live feed, and the Stop flow.
///
/// Reads go through the Go core (`env.goCore`). The live page
/// follows `activitySubscribe`: a full snapshot first, then a full report whenever it changed (the core polls every 3 s,
/// so nothing here does). The loop is driven by the view's `.task(id:)`: subscribed while the Activity tab is the active one,
/// subscribed until the first report has landed otherwise (the sidebar badge needs it even when the tab is hidden), and not
/// at all after that. `readOnce` is a single `activity.read` for Refresh, Try again and the shots.
@MainActor
@Observable
final class ActivityModel {
    /// The wait before subscribing again after a failed or ended subscription.
    static let liveInterval: Duration = .seconds(3)
    static let firstReadInterval: Duration = .milliseconds(500)
    /// What the engine reads by default (the core's `HistoryDays`); the empty states name it.
    static let historyDays = 14
    private static let unreadable = "The session logs could not be read."

    let env: AppEnvironment

    private(set) var report: CoreActivityReport?
    /// When `report` arrived. Ages in the report were computed then, so the screen adds the time since.
    private(set) var readAt: Date?
    /// A read that could not run. Cleared by the next successful read.
    private(set) var failure: String?
    /// The session whose Stop confirmation is open.
    var pendingStop: CoreActivitySession?
    private(set) var isStopping = false
    /// Screenshots only: show row actions without hover.
    var revealRowActions = false

    // MARK: The v5 page's state (V5-R69 to V5-R72)

    /// The page the v5 shell draws; the old screen has none of this. Only the toast after a stop depends on it.
    let isV5: Bool
    var pane = ActivityPane.running
    var filter = ActivityFilter()
    var isFilterOpen = false
    /// The row the keys act on and the row whose detail popover is open, by `ActivityQuery` ids.
    var currentID: String?
    var detailID: String?
    /// Failures the user dismissed, by `ActivityFailureItem.dismissKey`. In memory for the session (G13): the core keeps no store.
    private(set) var dismissed: Set<String> = []

    @ObservationIgnored var now: () -> Date = { Date() }
    /// The CLI readings the page's bands and Answer use: the shell's `limits.read`, which a shot or a test replaces.
    @ObservationIgnored var limitsResults: () -> [CoreLimitsEntry]
    /// What `Copy` and `Open` do. A test or a shot replaces them so nothing leaves the process.
    @ObservationIgnored var copyToPasteboard: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    /// Shows a file in Finder (it never opens or runs it: a path from a log can be anything). False when it is not there.
    @ObservationIgnored var revealFile: (URL) -> Bool = { url in
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    @ObservationIgnored private var isReading = false

    init(env: AppEnvironment, isV5: Bool = false) {
        self.env = env
        self.isV5 = isV5
        limitsResults = { env.limits.results }
    }

    var isLoading: Bool { report == nil && failure == nil }

    var recentFailures: Int { ActivityRows.recentFailureCount(report, now: Date()) }

    private var core: any CoreService { env.goCore }

    // MARK: Reading

    /// One `activity.read`, unless one is already running. Never throws: a failure is shown as the banner.
    func readOnce() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        do {
            apply(try await core.activityRead())
        } catch is CancellationError {
            // The tab went away mid-read: keep what is shown.
        } catch {
            failure = Self.message(error)
        }
    }

    /// The live loop. SwiftUI cancels it when the tab stops being active; a cancelled run ends without a further read.
    func run(active: Bool) async {
        while !Task.isCancelled {
            if report != nil || failure != nil, !active { return }
            await follow(active: active)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: report == nil ? Self.firstReadInterval : Self.liveInterval)
        }
    }

    /// One subscription. Leaving the loop ends the stream, which unsubscribes.
    private func follow(active: Bool) async {
        do {
            for try await fresh in core.activitySubscribe() {
                apply(fresh)
                // Hidden tab: the first report was all the badge needed.
                if !active { return }
            }
        } catch is CancellationError {
            // Cancelled with the tab: nothing to show.
        } catch {
            failure = Self.message(error)
        }
    }

    private func apply(_ fresh: CoreActivityReport) {
        report = fresh
        readAt = Date()
        failure = nil
    }

    /// The core's own sentence when it sent one, a fixed one otherwise (S-R3: never an error's description).
    private static func message(_ error: Error) -> String {
        (error as? CoreError)?.message ?? unreadable
    }

    func refreshNow() { Task { await readOnce() } }

    /// "Try again" after a failed read.
    func retry() {
        failure = nil
        refreshNow()
    }

    // MARK: Stop

    /// Opens the confirmation. Stop never runs without it. The row detail closes first: its outside-tap layer would swallow the
    /// first click on the dialog.
    func requestStop(_ session: CoreActivitySession) {
        detailID = nil
        pendingStop = session
    }

    func cancelStop() {
        guard !isStopping else { return }
        pendingStop = nil
    }

    /// The only caller of `activityStop`, and only for the session the confirmation names. The core looks the pid up again.
    /// The v5 toast says what was sent (V5-R59) and has no Undo: a stopped process cannot be brought back.
    func confirmStop() {
        guard let session = pendingStop, !isStopping else { return }
        isStopping = true
        let isV5 = isV5
        Task {
            let message: String
            var tone = ToastTone.info
            do {
                let result = try await core.activityStop(cli: session.cli, id: session.id)
                if isV5 {
                    message = ActivityStopWording.toast(session, exited: result.exited)
                } else {
                    message = result.exited ? "Stopped \(session.title)" : "The process ignored the signal"
                }
                if !result.exited { tone = .danger }
            } catch {
                // The core's sentence (404, 403, 409 "could not be verified", 500) is shown as it is.
                message = (error as? CoreError)?.message ?? "The session could not be stopped."
                tone = .danger
            }
            isStopping = false
            pendingStop = nil
            env.toasts.show(message, tone: tone)
            await readOnce()
        }
    }

    // MARK: The v5 page

    /// What the three tabs list at `now`: one derivation, read by the canvas, the tab head's counts and the keys.
    func query(at date: Date? = nil) -> ActivityQuery {
        ActivityQuery(report: report, filter: filter, dismissed: dismissed, limits: limitsResults(), readAt: readAt, now: date ?? now())
    }

    /// A head menu holds the keyboard, so the page's plain keys are off; so does the Stop confirmation.
    var isMenuOpen: Bool { isFilterOpen || pendingStop != nil }

    func select(_ pane: ActivityPane) {
        self.pane = pane
        detailID = nil
        isFilterOpen = false
    }

    /// `1` is index 0; an index outside the three tabs does nothing.
    func select(index: Int) {
        guard ActivityPane.allCases.indices.contains(index) else { return }
        select(ActivityPane.allCases[index])
    }

    func toggleFilter(_ value: String) {
        filter.toggle(.cli, value)
        detailID = nil
    }

    func clearFilters() {
        filter.clear()
        detailID = nil
    }

    /// The row the keys act on: the chosen one while it is listed, else the first listed.
    func current(in visible: [String]) -> String? { CurrentRow.resolve(currentID, in: visible) }

    /// A click on a row: it becomes current and its detail opens (V5-R57).
    func open(_ id: String) {
        currentID = id
        detailID = id
    }

    func move(by step: Int, in visible: [String]) {
        guard let next = CurrentRow.step(currentID, by: step, in: visible) else { return }
        currentID = next
        detailID = nil
    }

    func toggleDetail(of id: String?) {
        guard let id else { return }
        currentID = id
        detailID = detailID == id ? nil : id
    }

    // MARK: Copy, open and dismiss

    /// Puts the failed command on the pasteboard, whole: a title the core cut is refused with a sentence, never copied short.
    func copy(_ item: ActivityFailureItem) {
        detailID = nil
        guard !item.isCut else {
            env.toasts.show("That command is longer than \(ActivityRows.failureTitleLimit) characters and SpaceVibe only has its start, so it was not copied.")
            return
        }
        copyToPasteboard(item.failure.title)
        env.toasts.show("Copied the command.")
    }

    /// Shows the file in Finder (V5-R72). Sessions and failed commands have no folder to open: the report names a project, not a path (G11).
    func reveal(_ item: ActivityFileItem) {
        detailID = nil
        guard revealFile(URL(fileURLWithPath: item.file.path)) else {
            env.toasts.show("\(item.name) is no longer at \(item.file.path).", tone: .danger)
            return
        }
    }

    func dismiss(_ item: ActivityFailureItem) {
        detailID = nil
        let before = dismissed
        dismissed.insert(item.dismissKey)
        env.toasts.show("Dismissed \(ActivityStopWording.quoted(item.failure.title))", sessionUndo: false, undo: { [weak self] in
            self?.dismissed = before
            self?.env.toasts.show("Restored the failed command.")
        })
    }

    /// `Dismiss passed`: every command listed that failed and then passed. One Undo restores them all.
    func dismissPassed() {
        let passed = query().failures.filter { !$0.stillFailing }
        guard !passed.isEmpty else { return }
        detailID = nil
        let before = dismissed
        dismissed.formUnion(passed.map(\.dismissKey))
        env.toasts.show(ActivityFigures.dismissedPassedLabel(passed.count), sessionUndo: false, undo: { [weak self] in
            self?.dismissed = before
            self?.env.toasts.show("Restored \(ActivityFormat.plural(passed.count, "command")).")
        })
    }

    // MARK: Screenshots

    /// Puts a prepared report on screen without reading, for the headless shots.
    func preview(report: CoreActivityReport?, failure: String? = nil, readAt: Date = Date()) {
        self.report = report
        self.readAt = report == nil ? nil : readAt
        self.failure = failure
    }
}
