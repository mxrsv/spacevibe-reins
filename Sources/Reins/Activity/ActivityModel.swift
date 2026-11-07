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

    @ObservationIgnored private var isReading = false

    init(env: AppEnvironment) { self.env = env }

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

    /// Opens the confirmation. Stop never runs without it.
    func requestStop(_ session: CoreActivitySession) { pendingStop = session }

    func cancelStop() {
        guard !isStopping else { return }
        pendingStop = nil
    }

    /// The only caller of `activityStop`, and only for the session the confirmation names. The core looks the pid up again.
    func confirmStop() {
        guard let session = pendingStop, !isStopping else { return }
        isStopping = true
        Task {
            let message: String
            var tone = ToastTone.info
            do {
                let result = try await core.activityStop(cli: session.cli, id: session.id)
                message = result.exited ? "Stopped \(session.title)" : "The process ignored the signal"
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

    // MARK: Screenshots

    /// Puts a prepared report on screen without reading, for the headless shots.
    func preview(report: CoreActivityReport?, readAt: Date = Date()) {
        self.report = report
        self.readAt = report == nil ? nil : readAt
        failure = nil
    }
}
