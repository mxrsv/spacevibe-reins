import Foundation
import Testing
@testable import Reins

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
    func rulesCheck(rule: String) async throws -> CoreRuleCheck { throw unused() }
    func limitsRead() async throws -> CoreLimitsResult { throw unused() }
}

/// The Activity model reads and stops through `env.core(for: .activity)` (plan S.1c).
@Suite("Activity model")
@MainActor
struct ActivityModelTests {
    private func model(_ core: FakeActivityCore) -> ActivityModel {
        ActivityModel(env: AppEnvironment(roots: nil, startupProblem: "No home here.", proc: FixtureProcessAdapter.empty, toasts: ToastCenter(announce: false), core: core))
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
}

/// The page and Stop give the same answers through the in-process engine and the Go core (plan S.1c, cut-over readiness).
/// Both run on a private copy of the synthetic fixture home with the fixture's fake process list (S-R1: nothing real is signalled).
@Suite("Activity model, both engines")
@MainActor
struct ActivityModelEngineTests {
    private static let procFixture = CoreTestData.directory.appendingPathComponent("fixtures/home/.reins/activity-proc.json").path

    private func model(_ fixture: CoreFixtureHome, viaCore: Bool) throws -> (ActivityModel, CoreClient?) {
        let client = viaCore ? try fixture.client() : nil
        let env = AppEnvironment(
            roots: try fixture.roots(), proc: try FixtureProcessAdapter.load(path: Self.procFixture),
            toasts: ToastCenter(announce: false), routing: CoreRouting(viaCore: viaCore ? [.activity] : []), makeCoreClient: { client ?? CoreClient() }
        )
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

    @Test("the in-process path and the Go core give the screen the same sessions, failures, files, limits and wording")
    func sameThroughBothEngines() async throws {
        let fixture = try CoreFixtureHome(extraEnvironment: ["SPACEVIBE_PROC_FIXTURE": Self.procFixture])
        defer { fixture.remove() }
        let (inProcess, _) = try model(fixture, viaCore: false)
        let (viaCore, client) = try model(fixture, viaCore: true)
        defer { client?.shutdown() }
        await inProcess.readOnce()
        await viaCore.readOnce()
        #expect(inProcess.failure == nil && viaCore.failure == nil)
        let expected = try #require(inProcess.report)
        let actual = try #require(viaCore.report)
        #expect(!expected.sessions.isEmpty && !expected.failures.isEmpty && !expected.files.isEmpty)
        #expect(masked(actual) == masked(expected))
        let now = Date()
        for cli in CoreCLI.allCases {
            #expect(ActivityRows.sessions(actual, cli: cli).map { SessionWording($0, elapsedMs: 0).tagText } == ActivityRows.sessions(expected, cli: cli).map { SessionWording($0, elapsedMs: 0).tagText })
            #expect(ActivityRows.failures(actual, cli: cli).map { FailureWording($0, now: now).how } == ActivityRows.failures(expected, cli: cli).map { FailureWording($0, now: now).how })
            #expect(ActivityRows.limits(actual, cli: cli).map(\.text) == ActivityRows.limits(expected, cli: cli).map(\.text))
        }
        #expect(inProcess.recentFailures == viaCore.recentFailures)
    }

    @Test("the live stream starts with the same snapshot through both engines")
    func sameStream() async throws {
        let fixture = try CoreFixtureHome(extraEnvironment: ["SPACEVIBE_PROC_FIXTURE": Self.procFixture])
        defer { fixture.remove() }
        let (inProcess, _) = try model(fixture, viaCore: false)
        let (viaCore, client) = try model(fixture, viaCore: true)
        defer { client?.shutdown() }
        // A hidden tab: one report, then the loop ends and unsubscribes.
        await inProcess.run(active: false)
        await viaCore.run(active: false)
        #expect(try masked(#require(viaCore.report)) == masked(#require(inProcess.report)))
    }

    @Test("Stop gives the same result, and the same refusal once the session is gone, through both engines")
    func sameStop() async throws {
        let fixture = try CoreFixtureHome(extraEnvironment: ["SPACEVIBE_PROC_FIXTURE": Self.procFixture])
        defer { fixture.remove() }
        var messages: [[String]] = []
        for viaCore in [false, true] {
            let (model, client) = try model(fixture, viaCore: viaCore)
            defer { client?.shutdown() }
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
            messages.append(seen)
        }
        #expect(messages[0].count == 2 && messages[0][0].hasPrefix("Stopped ") && messages[0][1] == "That session is no longer running.")
        #expect(messages[1] == messages[0])
    }
}
