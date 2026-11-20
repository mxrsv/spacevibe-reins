import Foundation
import Testing
@testable import SpaceVibe

/// A core that serves only `activity.subscribe`, fed by hand: the test pushes reports into the open stream, or ends it with an
/// error, and counts the subscriptions opened and the streams that ended (the connection unsubscribes for each).
private final class FakeGlanceCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<CoreActivityReport, Error>.Continuation?
    private var _subscriptions = 0
    private var _ended = 0

    var subscriptions: Int { lock.withLock { _subscriptions } }
    var ended: Int { lock.withLock { _ended } }

    func push(_ report: CoreActivityReport) { lock.withLock { continuation }?.yield(report) }
    func fail(_ error: Error) { lock.withLock { continuation }?.finish(throwing: error) }

    override func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
                _subscriptions += 1
            }
            continuation.onTermination = { [self] _ in lock.withLock { _ended += 1 } }
        }
    }

    static func report(_ sessions: [CoreActivitySession]) -> CoreActivityReport {
        CoreActivityReport(sessions: sessions, failures: [], files: [], unmeasurable: [], stats: CoreActivityStats(logs: 1, truncated: 0))
    }

    static func session(_ id: String, state: CoreSessionState = .running, cli: CLIID = .claude) -> CoreActivitySession {
        CoreActivitySession(
            cli: cli, id: id, title: "task \(id)", project: nil, pid: 100, state: state, stateReason: "log written 2 s ago",
            reasonCode: nil, currentTool: nil, ageMs: nil, lastWriteAgoMs: 2_000, cost: nil, costNote: nil
        )
    }
}

@Suite("Glance feed", .fixtureCLIs)
@MainActor
struct GlanceFeedTests {
    /// Spins the main actor until `done`, so the feed's loop can land.
    private func settle(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done(), "\(what) did not happen")
    }

    /// Longer than one retry wait, so a loop that had not stopped would have subscribed again.
    private static let pastOneRetry = GlanceFeed.retryInterval + .milliseconds(500)

    @Test("start: the snapshot becomes the entries, and each pushed report replaces them")
    func followsTheStream() async throws {
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        #expect(feed.entries == .empty && feed.report == nil && !feed.isRunning)
        feed.start()
        #expect(feed.isRunning)
        try await settle("the subscription") { core.subscriptions == 1 }
        let first = FakeGlanceCore.report([FakeGlanceCore.session("a")])
        core.push(first)
        try await settle("the snapshot") { feed.report == first }
        #expect(feed.entries == GlanceEntries(report: first) && feed.entries.all.map(\.sessionID) == ["a"])
        let second = FakeGlanceCore.report([FakeGlanceCore.session("a"), FakeGlanceCore.session("b", state: .waiting)])
        core.push(second)
        try await settle("the pushed report") { feed.report == second }
        #expect(feed.entries.all.map(\.sessionID) == ["b", "a"], "waiting sorts before working (GW-R3)")
        #expect(feed.failure == nil && core.subscriptions == 1)
        feed.stop()
    }

    @Test("a session of a CLI clis.list did not return, or of one turned off, never reaches the widget (MC-R16)")
    func dropsUnlistedCLIs() async throws {
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        feed.start()
        try await settle("the subscription") { core.subscriptions == 1 }
        core.push(FakeGlanceCore.report([FakeGlanceCore.session("a"), FakeGlanceCore.session("b", cli: CLIID("cursor")),
                                         FakeGlanceCore.session("c", cli: .codex)]))
        try await settle("the snapshot") { feed.report != nil }
        #expect(feed.entries.all.map(\.sessionID) == ["a", "c"])
        CLICatalog.$scoped.withValue(CLICatalog(list: CLICatalogFixture.list, disabled: [.codex])) {
            #expect(feed.entries.all.map(\.sessionID) == ["a"])
        }
        feed.stop()
    }

    @Test("a failed stream shows the core's sentence, keeps the last entries, subscribes again, and a snapshot clears it")
    func failureRetries() async throws {
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        feed.start()
        try await settle("the subscription") { core.subscriptions == 1 }
        let shown = FakeGlanceCore.report([FakeGlanceCore.session("a")])
        core.push(shown)
        try await settle("the snapshot") { feed.report == shown }
        core.fail(CoreError("The core could not start.", status: 500))
        try await settle("the failure") { feed.failure == "The core could not start." }
        #expect(feed.entries == GlanceEntries(report: shown) && feed.isRunning)
        try await settle("the second subscription") { core.subscriptions == 2 }
        core.push(FakeGlanceCore.report([]))
        try await settle("the recovery") { feed.failure == nil && feed.entries == .empty && feed.report != nil }
        feed.stop()
    }

    @Test("an error that is not the core's gets a fixed sentence, never its description (S-R3)")
    func fixedSentence() async throws {
        struct Leaky: Error, CustomStringConvertible { var description: String { "/Users/someone/secret" } }
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        feed.start()
        try await settle("the subscription") { core.subscriptions == 1 }
        core.fail(Leaky())
        try await settle("the failure") { feed.failure != nil }
        #expect(feed.failure == GlanceFeed.unreadable)
        feed.stop()
    }

    @Test("stop ends the stream, clears what was shown, and no subscription follows", .timeLimit(.minutes(1)))
    func stopEnds() async throws {
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        feed.start()
        try await settle("the subscription") { core.subscriptions == 1 }
        core.push(FakeGlanceCore.report([FakeGlanceCore.session("a")]))
        try await settle("the snapshot") { !feed.entries.isEmpty }
        feed.stop()
        #expect(!feed.isRunning && feed.entries == .empty && feed.report == nil && feed.failure == nil)
        try await settle("the stream's end") { core.ended == 1 }
        // A report the stream still delivers after stop is not shown.
        core.push(FakeGlanceCore.report([FakeGlanceCore.session("late")]))
        try await Task.sleep(for: Self.pastOneRetry)
        #expect(core.subscriptions == 1 && feed.entries == .empty && feed.report == nil)
        feed.stop()
        #expect(!feed.isRunning)
    }

    @Test("stop during the wait after a failure: no subscription follows", .timeLimit(.minutes(1)))
    func stopDuringRetryWait() async throws {
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        feed.start()
        try await settle("the subscription") { core.subscriptions == 1 }
        core.fail(CoreError("The core could not start.", status: 500))
        try await settle("the failure") { feed.failure != nil }
        feed.stop()
        #expect(feed.failure == nil)
        try await Task.sleep(for: Self.pastOneRetry)
        #expect(core.subscriptions == 1)
    }

    @Test("start twice opens one subscription; start after stop opens a new one")
    func startIsIdempotent() async throws {
        let core = FakeGlanceCore()
        let feed = GlanceFeed(core: core)
        feed.start()
        feed.start()
        try await settle("the subscription") { core.subscriptions == 1 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(core.subscriptions == 1)
        feed.stop()
        try await settle("the stream's end") { core.ended == 1 }
        feed.start()
        try await settle("the new subscription") { core.subscriptions == 2 }
        feed.stop()
    }

    @Test("against the fixture core: the snapshot arrives, and stop makes the connection unsubscribe", .timeLimit(.minutes(1)))
    func fixtureCore() async throws {
        let fixture = try await CoreFixtureHome.make()
        let client = try fixture.client()
        defer {
            client.shutdown()
            fixture.remove()
        }
        let feed = GlanceFeed(core: client)
        feed.start()
        try await settle("the fixture snapshot") { feed.report != nil }
        let report = try #require(feed.report)
        #expect(feed.entries == GlanceEntries(report: report) && feed.failure == nil)
        #expect(client.connection.sentCount("activity.subscribe") == 1)
        feed.stop()
        try await settle("the unsubscribe") { client.connection.sentCount("activity.unsubscribe") == 1 }
        #expect(feed.entries == .empty && feed.report == nil)
    }
}
