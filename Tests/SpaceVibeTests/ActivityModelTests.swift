import Foundation
import Testing
@testable import SpaceVibe

/// A `CoreService` that serves only Activity, for the model tests: the stream is fed by hand, and Stop answers what the test sets.
/// Every other method refuses.
private final class FakeActivityCore: CoreService, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<CoreActivityReport, Error>.Continuation?
    private var _subscriptions = 0
    private var _ended = 0
    private var _stops: [String] = []
    private var _reads = 0
    private var _stopResult: Result<CoreStopResult, Error> = .success(CoreStopResult(exited: true))
    var readResult: Result<CoreActivityReport, Error> = .success(FakeActivityCore.report([]))

    var subscriptions: Int { lock.withLock { _subscriptions } }
    /// Streams that were ended or cancelled: the core unsubscribes for each.
    var ended: Int { lock.withLock { _ended } }
    var stops: [String] { lock.withLock { _stops } }
    var reads: Int { lock.withLock { _reads } }
    func answerStop(_ result: Result<CoreStopResult, Error>) { lock.withLock { _stopResult = result } }

    func push(_ report: CoreActivityReport) { lock.withLock { continuation }?.yield(report) }
    func fail(_ error: Error) { lock.withLock { continuation }?.finish(throwing: error) }

    static func report(_ sessions: [CoreActivitySession], limits: [CoreActivityLimit] = []) -> CoreActivityReport {
        CoreActivityReport(sessions: sessions, failures: [], files: [], unmeasurable: limits, stats: CoreActivityStats(logs: 1, truncated: 0))
    }

    static func session(
        _ id: String, cli: CoreCLI = .claude, state: CoreSessionState = .running, reason: String = "log written 2 s ago", code: String? = nil
    ) -> CoreActivitySession {
        CoreActivitySession(
            cli: cli, id: id, title: "task \(id)", project: nil, pid: 100, state: state, stateReason: reason, reasonCode: code,
            currentTool: nil, ageMs: nil, lastWriteAgoMs: nil, cost: nil, costNote: nil
        )
    }

    func activityRead() async throws -> CoreActivityReport {
        lock.withLock { _reads += 1 }
        return try readResult.get()
    }

    func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
                _subscriptions += 1
            }
            continuation.onTermination = { [self] _ in lock.withLock { _ended += 1 } }
        }
    }

    func activityStop(cli: CoreCLI, id: String) async throws -> CoreStopResult {
        lock.withLock { _stops.append("\(cli.rawValue):\(id)") }
        return try lock.withLock { _stopResult }.get()
    }

    private func unused() -> CoreError { CoreError("not served by the Activity fake", status: 500) }
    func initialize() async throws -> CoreInitializeResult { throw unused() }
    func inventoryRead() async throws -> CoreInventorySnapshot { throw unused() }
    func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult { throw unused() }
    func loadoutRows() async throws -> CoreLoadoutRows { throw unused() }
    func loadoutCopyToOther(id: String) async throws -> CoreEntryResult { throw unused() }
    func loadoutRemoveItem(id: String) async throws -> CoreEntryResult { throw unused() }
    func loadoutRemoveDeadHooks(cli: CoreCLI) async throws -> CoreEntryResult { throw unused() }
    func journalUndo(id: String) async throws -> CoreUndoResult { throw unused() }
    func journalHistory() async throws -> CoreJournalHistory { throw unused() }
    func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot { throw unused() }
    func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview { throw unused() }
    func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult { throw unused() }
    func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw unused() }
    func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw unused() }
    func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult { throw unused() }
    func rulesChangeVerdicts(scope: CoreRuleScope, dir: String?, to: CoreVerdict, rules: [CoreRuleMove]) async throws -> CoreEntryResult { throw unused() }
    func rulesCheck(rule: String) async throws -> CoreRuleCheck { throw unused() }
    func limitsRead() async throws -> CoreLimitsResult { throw unused() }
}

/// The Activity model reads and stops through `env.goCore`, the Go core (plan S.3).
@Suite("Activity model")
@MainActor
struct ActivityModelTests {
    private func model(_ core: FakeActivityCore) -> ActivityModel {
        ActivityModel(env: AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core }))
    }

    /// Spins the main actor until `done`, so a `Task` the model started can land.
    private func settle(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done(), "\(what) did not happen")
    }

    // MARK: The live feed

    @Test("a live tab follows the stream: the snapshot, then each pushed report replaces the last; leaving unsubscribes")
    func liveFeed() async throws {
        let core = FakeActivityCore()
        let model = model(core)
        let loop = Task { await model.run(active: true) }
        try await settle("the subscription") { core.subscriptions == 1 }
        #expect(model.isLoading)
        core.push(FakeActivityCore.report([FakeActivityCore.session("a")]))
        try await settle("the snapshot") { model.report?.sessions.map(\.id) == ["a"] }
        #expect(model.readAt != nil && model.failure == nil)
        core.push(FakeActivityCore.report([FakeActivityCore.session("a"), FakeActivityCore.session("b", cli: .codex)]))
        try await settle("the pushed report") { model.report?.sessions.map(\.id) == ["a", "b"] }
        #expect(core.reads == 0, "the stream replaces the 3 s poll: no read is made")
        loop.cancel()
        await loop.value
        try await settle("the unsubscribe") { core.ended == 1 }
    }

    @Test("a hidden tab takes the first report for the sidebar badge, then unsubscribes and stops")
    func hiddenTab() async throws {
        let core = FakeActivityCore()
        let model = model(core)
        let loop = Task { await model.run(active: false) }
        try await settle("the subscription") { core.subscriptions == 1 }
        core.push(FakeActivityCore.report([FakeActivityCore.session("a")]))
        await loop.value
        #expect(model.report?.sessions.map(\.id) == ["a"])
        #expect(core.ended == 1 && core.subscriptions == 1)
    }

    @Test("a hidden window with a report loaded makes no subscription at all (the canvas passes isActive && windowVisible)")
    func hiddenWindowDoesNotSubscribe() async {
        let core = FakeActivityCore()
        let model = model(core)
        await model.readOnce()
        #expect(model.report != nil)
        await model.run(active: false)
        #expect(core.subscriptions == 0 && core.ended == 0)
    }

    @Test("a stream that fails shows the core's sentence, subscribes again, and a snapshot clears the failure")
    func streamFailure() async throws {
        let core = FakeActivityCore()
        let model = model(core)
        let loop = Task { await model.run(active: true) }
        try await settle("the subscription") { core.subscriptions == 1 }
        core.fail(CoreError("The core could not start.", status: 500))
        try await settle("the failure") { model.failure == "The core could not start." }
        #expect(model.report == nil && !model.isLoading)
        try await settle("the second subscription") { core.subscriptions == 2 }
        core.push(FakeActivityCore.report([]))
        try await settle("the recovery") { model.report != nil && model.failure == nil }
        loop.cancel()
        await loop.value
    }

    @Test("an error that is not the core's gets a fixed sentence, never its description")
    func unexpectedFailure() async throws {
        struct Leaky: Error, CustomStringConvertible { var description: String { "/Users/someone/secret" } }
        let core = FakeActivityCore()
        core.readResult = .failure(Leaky())
        let model = model(core)
        await model.readOnce()
        #expect(model.failure == "The session logs could not be read.")
    }

    @Test("a single read applies the report and clears an earlier failure; Try again reads once")
    func singleRead() async throws {
        let core = FakeActivityCore()
        core.readResult = .failure(CoreError("No home here.", status: 500))
        let model = model(core)
        await model.readOnce()
        #expect(model.failure == "No home here.")
        core.readResult = .success(FakeActivityCore.report([FakeActivityCore.session("a")]))
        model.retry()
        try await settle("the retry") { model.report != nil && model.failure == nil }
    }

    // MARK: Open reason codes

    @Test("an unknown reasonCode and an unknown limit code are shown by their sentences: the code decides nothing")
    func unknownCodes() {
        let session = FakeActivityCore.session("x", cli: .codex, state: .unmeasurable, reason: "Codex has not shown its process.", code: "a-code-the-core-adds-later")
        let limit = CoreActivityLimit(cli: .codex, code: "another-new-code", text: "The core says this cannot be measured.")
        let report = FakeActivityCore.report([session], limits: [limit])
        let wording = SessionWording(session, elapsedMs: 0)
        #expect((wording.tagText, wording.tagTone, wording.tagIcon) == ("not measurable", .neutral, .warning))
        #expect(wording.help == "Codex has not shown its process.")
        #expect(wording.subtitle == "state not measurable")
        #expect(ActivityRows.sessions(report, cli: .codex).map(\.id) == ["x"])
        #expect(ActivityRows.limits(report, cli: .codex).map(\.text) == ["The core says this cannot be measured."])
        #expect(ActivityRows.limits(report, cli: .claude).isEmpty)
    }

    // MARK: Stop

    private func stop(_ core: FakeActivityCore, _ model: ActivityModel, _ session: CoreActivitySession) async throws {
        model.requestStop(session)
        model.confirmStop()
        try await settle("the stop") { model.pendingStop == nil && !model.isStopping && core.reads > 0 }
    }

    @Test("Stop sends the CLI and the id, says Stopped, and reads again")
    func stopExited() async throws {
        let core = FakeActivityCore()
        let model = model(core)
        try await stop(core, model, FakeActivityCore.session("s1", cli: .codex))
        #expect(core.stops == ["codex:s1"])
        #expect(model.env.toasts.current?.message == "Stopped task s1")
        #expect(model.env.toasts.current?.tone == .info)
    }

    @Test("a process that outlives the signal is a danger toast")
    func stopIgnored() async throws {
        let core = FakeActivityCore()
        core.answerStop(.success(CoreStopResult(exited: false)))
        let model = model(core)
        try await stop(core, model, FakeActivityCore.session("s1"))
        #expect(model.env.toasts.current?.message == "The process ignored the signal")
        #expect(model.env.toasts.current?.tone == .danger)
    }

    @Test("a refusal shows the core's own sentence: 409 could not be verified, 404 gone, 403 other user",
          arguments: [
            (409, "That session could not be verified, so nothing was stopped."),
            (404, "That session is no longer running."),
            (403, "This session belongs to another user, so it cannot be stopped."),
          ])
    func stopRefused(status: Int, message: String) async throws {
        let core = FakeActivityCore()
        core.answerStop(.failure(CoreError(message, status: status)))
        let model = model(core)
        try await stop(core, model, FakeActivityCore.session("s1"))
        #expect(model.env.toasts.current?.message == message)
        #expect(model.env.toasts.current?.tone == .danger)
    }

    @Test("an error that is not the core's gets the fixed Stop sentence")
    func stopUnexpected() async throws {
        struct Odd: Error {}
        let core = FakeActivityCore()
        core.answerStop(.failure(Odd()))
        let model = model(core)
        try await stop(core, model, FakeActivityCore.session("s1"))
        #expect(model.env.toasts.current?.message == "The session could not be stopped.")
    }

    @Test("Stop never runs without the confirmation, and Cancel closes it")
    func stopNeedsConfirmation() {
        let core = FakeActivityCore()
        let model = model(core)
        model.confirmStop()
        #expect(core.stops.isEmpty && !model.isStopping)
        model.requestStop(FakeActivityCore.session("s1"))
        model.cancelStop()
        #expect(model.pendingStop == nil && core.stops.isEmpty)
    }

    @Test("Stop closes the row detail first, so the dialog's first click is not swallowed")
    func stopClosesDetail() {
        let model = model(FakeActivityCore())
        let session = FakeActivityCore.session("s1")
        model.open("s1")
        #expect(model.detailID == "s1")
        model.requestStop(session)
        #expect(model.detailID == nil)
        #expect(model.pendingStop?.id == "s1")
    }

    @Test("The old Stop dialog says the pid, the CLI and the consequence")
    func oldDialogNamesPid() {
        let message = ActivityStopConfirmation.message(FakeActivityCore.session("s1"))
        #expect(message.contains("pid 100"))
        #expect(message.contains("Claude Code"))
        #expect(message.contains("cannot be undone"))
        #expect(message.contains(ActivityStopWording.note))
    }
}

/// The page and Stop against the real Go core (plan S.3): a private copy of the synthetic fixture home with the fixture's fake
/// process list, named by `SPACEVIBE_PROC_FIXTURE` and read by the core's own fixture adapter (S-R1: nothing real is signalled).
@Suite("Activity model, Go core")
@MainActor
struct ActivityModelCoreTests {
    private static let procFixture = CoreTestData.directory.appendingPathComponent("fixtures/home/.reins/activity-proc.json").path

    private func model(_ fixture: CoreFixtureHome) throws -> (ActivityModel, CoreClient) {
        let client = try fixture.client()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
        return (ActivityModel(env: env), client)
    }

    /// Ages move with the clock between two reads; everything else must match.
    private func masked(_ report: CoreActivityReport) -> CoreActivityReport {
        var copy = report
        copy.sessions = copy.sessions.map { session in
            var s = session
            s.ageMs = s.ageMs == nil ? nil : 0
            s.lastWriteAgoMs = s.lastWriteAgoMs == nil ? nil : 0
            return s
        }
        return copy
    }

    @Test("a read gives the screen the fixture home's sessions, failures, files and limits, with their wording", .timeLimit(.minutes(1)))
    func fixtureHome() async throws {
        let fixture = try await CoreFixtureHome.make(extraEnvironment: ["SPACEVIBE_PROC_FIXTURE": Self.procFixture])
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        await model.readOnce()
        #expect(model.failure == nil)
        let report = try #require(model.report)
        #expect(!report.sessions.isEmpty && !report.failures.isEmpty && !report.files.isEmpty)
        #expect(Set(CoreCLI.allCases).isSubset(of: Set(report.sessions.map(\.cli))))
        #expect(report.sessions.contains { $0.cli == .codex && $0.state == .running })
        #expect(report.sessions.contains { $0.state == .unmeasurable })
        let now = Date()
        for cli in CoreCLI.allCases {
            #expect(!ActivityRows.sessions(report, cli: cli).isEmpty)
            #expect(ActivityRows.sessions(report, cli: cli).allSatisfy { !SessionWording($0, elapsedMs: 0).tagText.isEmpty })
            #expect(ActivityRows.failures(report, cli: cli).allSatisfy { !FailureWording($0, now: now).how.isEmpty })
        }
        #expect(model.recentFailures == ActivityRows.recentFailureCount(report, now: Date()))
    }

    @Test("the live stream starts with the same snapshot a read gives, and the first report arrives promptly (H10)", .timeLimit(.minutes(1)))
    func stream() async throws {
        let fixture = try await CoreFixtureHome.make(extraEnvironment: ["SPACEVIBE_PROC_FIXTURE": Self.procFixture])
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        _ = try await client.initialize()
        // The core is already up, so this times the subscription alone: its request, the first full report and its decode.
        let started = ContinuousClock.now
        var iterator = client.activitySubscribe().makeAsyncIterator()
        let first = try #require(try await iterator.next())
        let elapsed = ContinuousClock.now - started
        print("activity.subscribe time to first report on the fixture home: \(elapsed)")
        #expect(elapsed < .seconds(2))
        // A hidden tab takes that one report, then the loop ends and unsubscribes.
        await model.run(active: false)
        #expect(masked(try #require(model.report)) == masked(first))
    }

    @Test("Stop signals a session, and says so once it is gone", .timeLimit(.minutes(1)))
    func stop() async throws {
        let fixture = try await CoreFixtureHome.make(extraEnvironment: ["SPACEVIBE_PROC_FIXTURE": Self.procFixture])
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        await model.readOnce()
        let running = try #require(model.report?.sessions.first { $0.cli == .codex && $0.state == .running })
        var seen: [String] = []
        // A Codex thread names its own id; the fixture has no start time for the Claude pids, which Claude needs.
        for _ in 0..<2 {
            model.requestStop(running)
            model.confirmStop()
            let deadline = Date().addingTimeInterval(30)
            while model.pendingStop != nil || model.isStopping, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            seen.append(try #require(model.env.toasts.current?.message))
        }
        #expect(seen.count == 2 && seen[0].hasPrefix("Stopped ") && seen[1] == "That session is no longer running.")
    }

    @Test("when the helper is missing, the screen shows the fixed startup sentence and nothing else")
    func helperMissing() async {
        let client = CoreClient(binary: URL(fileURLWithPath: "/nonexistent/spacevibe"))
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
        let model = ActivityModel(env: env)
        await model.readOnce()
        #expect(model.failure == CoreWire.startFailedMessage)
        #expect(model.report == nil && !model.isLoading)
        // The live loop reports the same sentence (a hidden tab ends once there is a failure to show).
        let live = ActivityModel(env: env)
        await live.run(active: false)
        #expect(live.failure == CoreWire.startFailedMessage)
    }
}
