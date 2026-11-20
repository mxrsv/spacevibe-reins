import Foundation
import Testing
@testable import SpaceVibe

/// The widget's switch driven through `GlanceController` (spec `docs/specs/2026-11-19-session-glance-widget.md`, GW-R10; spec
/// `docs/specs/2026-11-19-limit-reset-countdown.md`, LC-R8): turned off, the activity stream ends, the limit reads stop and
/// the panels leave. The controller runs against a fake core and throwaway defaults, on one screen placed far off every
/// display, so its panels never appear where anyone can see them.
@Suite("Glance controller switch", .fixtureCLIs)
@MainActor
struct GlanceControllerSwitchTests {
    /// Off every display: the panels order in there, not on a real screen.
    private static let farScreen = GlanceScreen(id: GlanceScreenID(displayID: 0, name: "test screen"),
                                                visibleFrame: CGRect(x: -40_000, y: -40_000, width: 1440, height: 900))

    private func settle(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done(), "\(what) did not happen")
    }

    @Test("switch off: the stream ends, no limit read follows, the feeds stop and the panels hide", .timeLimit(.minutes(1)))
    func switchOff() async throws {
        let suite = "dev.spacevibe.tests.glance-switch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlancePreferences(defaults: defaults)
        let core = SwitchCore()
        let limits = LimitsModel(env: AppEnvironment(makeCoreClient: { core }))
        let controller = GlanceController(preferences: preferences, countdown: LimitsCountdownPreferences(defaults: defaults),
                                          makeCore: { core }, makeLimits: { limits },
                                          limitsReadInterval: .milliseconds(40), screens: { [Self.farScreen] })
        #expect(preferences.isEnabled, "on by default (GW16)")

        controller.startSkippingLaunchGateForTests()
        try await settle("the subscription") { core.subscriptions == 1 }
        try await settle("the limit reads") { core.reads >= 2 }
        core.push(SwitchCore.report(["a"]))
        let feed = try #require(controller.feed)
        let limitsFeed = try #require(controller.limitsFeed)
        try await settle("the snapshot") { !feed.entries.isEmpty }
        #expect(feed.isRunning && limitsFeed.isRunning)
        try await settle("the strip") { controller.isShowingForTests }

        preferences.isEnabled = false
        try await settle("the feeds' stop") { !feed.isRunning && !limitsFeed.isRunning }
        try await settle("the stream's end (the connection unsubscribes)") { core.ended == 1 }
        #expect(!controller.isShowingForTests, "every panel is ordered out")
        #expect(feed.entries == .empty)
        // A read already running may finish; none starts after it.
        try await Task.sleep(for: .milliseconds(100))
        let stopped = core.reads
        try await Task.sleep(for: .milliseconds(300))
        #expect(core.reads == stopped, "no limits.read after the switch is off")
        #expect(core.subscriptions == 1, "no new subscription")
        // A report the stream still delivers draws nothing.
        core.push(SwitchCore.report(["late"]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.isShowingForTests && feed.entries == .empty)
    }
}

/// Serves `activity.subscribe` (fed by hand, counting the streams opened and ended) and `limits.read` (counting the reads);
/// the same shape as the fakes of `GlanceFeedTests` and `GlanceCountdownTests`, in one core as the controller needs.
private final class SwitchCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<CoreActivityReport, Error>.Continuation?
    private var _subscriptions = 0
    private var _ended = 0
    private var _reads = 0

    var subscriptions: Int { lock.withLock { _subscriptions } }
    var ended: Int { lock.withLock { _ended } }
    var reads: Int { lock.withLock { _reads } }

    func push(_ report: CoreActivityReport) { lock.withLock { continuation }?.yield(report) }

    override func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
                _subscriptions += 1
            }
            continuation.onTermination = { [self] _ in lock.withLock { _ended += 1 } }
        }
    }

    override func limitsRead() async throws -> CoreLimitsResult {
        lock.withLock { _reads += 1 }
        return CoreLimitsResult(limits: [CoreLimitsEntry(cli: .claude, state: .notRecorded, plan: nil, source: nil, at: nil, windows: [])])
    }

    static func report(_ ids: [String]) -> CoreActivityReport {
        let sessions = ids.map { id in
            CoreActivitySession(cli: .claude, id: id, title: "task \(id)", project: nil, pid: 100, state: .running,
                                stateReason: "log written 2 s ago", reasonCode: nil, currentTool: nil, ageMs: nil,
                                lastWriteAgoMs: 2_000, cost: nil, costNote: nil)
        }
        return CoreActivityReport(sessions: sessions, failures: [], files: [], unmeasurable: [],
                                  stats: CoreActivityStats(logs: sessions.count, truncated: 0))
    }
}
