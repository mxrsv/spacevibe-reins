import Foundation
import Observation
import ReinsCore

/// The Activity screen's state: the latest report, the read loop, and the Stop flow.
///
/// Reads run in `ActivityEngine`, an actor, so no log is touched on the main actor. The engine keeps read offsets, so after
/// the first (possibly slow) read a repeat only reads appended bytes. The loop is driven by the view's `.task(id:)`:
/// every `liveInterval` while the Activity tab is the active one, every `firstReadInterval` until the first report has
/// landed (the sidebar badge needs it even when the tab is hidden), and not at all otherwise.
@MainActor
@Observable
final class ActivityModel {
    static let liveInterval: Duration = .seconds(3)
    static let firstReadInterval: Duration = .milliseconds(500)
    /// What `ActivityOptions` reads by default; the empty states name it.
    static let historyDays = ActivityOptions().historyDays

    let env: AppEnvironment

    private(set) var report: ActivityReport?
    /// When `report` was read. Ages in the report were computed then, so the screen adds the time since.
    private(set) var readAt: Date?
    /// A read that could not run. Cleared by the next successful read.
    private(set) var failure: String?
    /// The session whose Stop confirmation is open.
    var pendingStop: ActivitySession?
    private(set) var isStopping = false
    /// Screenshots only: show row actions without hover.
    var revealRowActions = false

    @ObservationIgnored private let engine = ActivityEngine()
    @ObservationIgnored private var isReading = false

    init(env: AppEnvironment) { self.env = env }

    var isLoading: Bool { report == nil && failure == nil }

    var recentFailures: Int { ActivityRows.recentFailureCount(report, now: Date()) }

    // MARK: Reading

    /// One read, unless one is already running. Never throws: the engine reports what it could not read inside the report.
    func readOnce() async {
        guard !isReading else { return }
        guard let roots = env.roots else {
            failure = env.startupProblem ?? "The config folders could not be resolved."
            return
        }
        isReading = true
        defer { isReading = false }
        let fresh = await engine.readActivity(roots: roots, now: Date(), proc: env.proc)
        report = fresh
        readAt = Date()
        failure = nil
    }

    /// The read loop. SwiftUI cancels it when the tab stops being active; a cancelled run ends without a further read.
    func run(active: Bool) async {
        while !Task.isCancelled {
            if report != nil || failure != nil, !active { return }
            await readOnce()
            try? await Task.sleep(for: report == nil ? Self.firstReadInterval : Self.liveInterval)
        }
    }

    func refreshNow() { Task { await readOnce() } }

    /// "Try again" after a failed read.
    func retry() {
        failure = nil
        refreshNow()
    }

    // MARK: Stop

    /// Opens the confirmation. Stop never runs without it.
    func requestStop(_ session: ActivitySession) { pendingStop = session }

    func cancelStop() {
        guard !isStopping else { return }
        pendingStop = nil
    }

    /// The only caller of `stopSession`, and only for the session the confirmation names. The engine looks the pid up again.
    func confirmStop() {
        guard let session = pendingStop, !isStopping else { return }
        guard let roots = env.roots else {
            pendingStop = nil
            env.toasts.show(env.startupProblem ?? "The config folders could not be resolved.", tone: .danger)
            return
        }
        isStopping = true
        let proc = env.proc
        Task {
            let message: String
            var tone = ToastTone.info
            do {
                let result = try await stopSession(roots: roots, cli: session.cli, id: session.id, proc: proc)
                message = result.exited ? "Stopped \(session.title)" : "The process ignored the signal"
                if !result.exited { tone = .danger }
            } catch {
                message = (error as? ReinsError)?.message ?? "The session could not be stopped."
                tone = .danger
            }
            isStopping = false
            pendingStop = nil
            env.toasts.show(message, tone: tone)
            await readOnce()
        }
    }

    // MARK: Screenshots

    /// Puts a prepared report on screen without reading, for the headless shots.
    func preview(report: ActivityReport?, readAt: Date = Date()) {
        self.report = report
        self.readAt = report == nil ? nil : readAt
        failure = nil
    }
}
