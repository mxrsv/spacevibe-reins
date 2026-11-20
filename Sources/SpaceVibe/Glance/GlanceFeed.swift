import Foundation
import Observation

/// The glance widget's own live feed (GW-R1): one `activity.subscribe` kept open from `start()` to `stop()`, whether or not the
/// main window or the Activity tab is open. It is a second sink on the same core connection, so the core still polls once; the
/// connection unsubscribes only when the last sink leaves (`CoreConnection.removeSink`).
///
/// A subscription that ends or fails (the core restarted, or could not start) is opened again after `retryInterval`, and its
/// first report is a full snapshot (resync). `stop()` ends the stream, which lets the connection unsubscribe, so the core stops
/// polling when the widget's switch turns off (GW-R10). It also drops what was shown: a widget turned on again never shows
/// an old state.
@MainActor
@Observable
final class GlanceFeed {
    /// The wait before subscribing again after a failed or ended subscription: the Activity page's, so both recover alike.
    static let retryInterval: Duration = ActivityModel.liveInterval
    /// Shown for an error that is not the core's own (S-R3: never an error's description).
    static let unreadable = "The session logs could not be read."

    /// The sessions the widget shows, from `report`.
    var entries: GlanceEntries { report.map(GlanceEntries.init(report:)) ?? .empty }
    /// The latest report as the core sent it.
    private(set) var rawReport: CoreActivityReport?
    /// The latest report, for the CLIs the catalog shows (MC-R16); the click fallback needs its session ids.
    var report: CoreActivityReport? { rawReport.map { CLICatalog.current.shown($0) } }
    /// The core's sentence, or `unreadable`. Cleared by the next report. While it is set, `entries` are the last read, and
    /// the views say so (`GlanceStripView.failure`, `GlanceListView.failure`).
    private(set) var failure: String?
    private(set) var isRunning = false

    private let core: any CoreService
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(core: any CoreService) {
        self.core = core
    }

    /// Opens the subscription and keeps it open until `stop()`. A second call while running does nothing.
    func start() {
        guard loop == nil else { return }
        isRunning = true
        let core = core
        // The loop holds the feed weakly, so a feed released without `stop()` ends at its next report or retry.
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    for try await fresh in core.activitySubscribe() {
                        guard !Task.isCancelled, let self else { return }
                        self.apply(fresh)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.failure = Self.message(error)
                }
                guard !Task.isCancelled, self != nil else { return }
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
    }

    /// Ends the loop and its stream, and clears what was shown. A second call does nothing more.
    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
        rawReport = nil
        failure = nil
    }

    private func apply(_ fresh: CoreActivityReport) {
        rawReport = fresh
        failure = nil
    }

    /// The core's own sentence when it sent one, a fixed one otherwise (S-R3).
    private static func message(_ error: Error) -> String {
        (error as? CoreError)?.message ?? unreadable
    }
}
