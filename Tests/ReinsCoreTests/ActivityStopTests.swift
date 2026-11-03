import Foundation
import Testing
@testable import ReinsCore

/// stopSession through a fake adapter: nothing is signalled for real, and the pid always comes from the live system.
@Suite("Activity stop")
struct ActivityStopTests {
    private static let start = "Mon Nov  2 11:00:00 2026"
    private static let fast = StopOptions(waitMs: 30, pollMs: 5)

    private func status(_ sb: ActivitySandbox, _ pid: Int) throws {
        try sb.status(pid, ["procStart": Self.start])
    }

    private func status(of error: Error) -> Int? { (error as? ReinsError)?.status }

    @Test("signals the Claude process that the status file names, and reports that it exited")
    func claudeStop() async throws {
        let sb = try ActivitySandbox()
        try status(sb, 11)
        let proc = FakeProcess(alive: [11], starts: [11: "Mon Nov  2  11:00:00  2026"])
        let result = try await stopSession(roots: try sb.roots, cli: .claude, id: activitySid(11), proc: proc, options: Self.fast)
        #expect(result == StopResult(exited: true))
        #expect(proc.killed == [11])
    }

    @Test("refuses a reused pid, a dead process and an unknown session, and signals nothing")
    func refuses() async throws {
        let sb = try ActivitySandbox()
        try status(sb, 12)
        try status(sb, 13)
        let roots = try sb.roots
        let cases: [(InventoryCLI, String, FakeProcess)] = [
            (.claude, activitySid(12), FakeProcess(alive: [12], starts: [12: "Tue Nov  3 01:00:00 2026"])), // pid reused
            (.claude, activitySid(12), FakeProcess(alive: [12])), // start time unknown: not proven to be the same process
            (.claude, activitySid(13), FakeProcess(starts: [13: Self.start])), // dead
            (.codex, activitySid(99), FakeProcess()),
        ]
        for (cli, id, proc) in cases {
            do {
                _ = try await stopSession(roots: roots, cli: cli, id: id, proc: proc, options: Self.fast)
                Issue.record("expected a 404 for \(cli) \(id)")
            } catch {
                #expect(status(of: error) == 404)
            }
            #expect(proc.killed.isEmpty)
        }
    }

    @Test("finds a Codex process by its thread lock, or by pid and start identity before the first prompt")
    func codexStop() async throws {
        let sb = try ActivitySandbox()
        let threads = [CodexThread(pid: 21, threadId: activitySid(21)), CodexThread(pid: 22, threadId: nil)]
        let byThread = FakeProcess(alive: [21, 22], threads: threads)
        #expect(try await stopSession(roots: try sb.roots, cli: .codex, id: activitySid(21), proc: byThread, options: Self.fast) == StopResult(exited: true))
        #expect(byThread.killed == [21])
        let byPid = FakeProcess(alive: [21, 22], starts: [22: Self.start], threads: threads)
        let id = try #require(codexProcessID(pid: 22, start: Self.start))
        #expect(try await stopSession(roots: try sb.roots, cli: .codex, id: id, proc: byPid, options: Self.fast) == StopResult(exited: true))
        #expect(byPid.killed == [22])
        // A pid that holds a thread is not reachable through the bare-pid form.
        let held = FakeProcess(alive: [21], threads: threads)
        do {
            _ = try await stopSession(roots: try sb.roots, cli: .codex, id: "pid:21", proc: held, options: Self.fast)
            Issue.record("expected a 404")
        } catch {
            #expect(status(of: error) == 404)
        }
        #expect(held.killed.isEmpty)
    }

    @Test("says when the process ignored the signal, and turns a permission error into a plain message")
    func signalOutcomes() async throws {
        let sb = try ActivitySandbox()
        try status(sb, 14)
        let stubborn = FakeProcess(alive: [14], starts: [14: Self.start], ignoresSignal: true)
        #expect(try await stopSession(roots: try sb.roots, cli: .claude, id: activitySid(14), proc: stubborn, options: Self.fast) == StopResult(exited: false))
        let denied = FakeProcess(alive: [14], starts: [14: Self.start], terminateError: .notPermitted)
        do {
            _ = try await stopSession(roots: try sb.roots, cli: .claude, id: activitySid(14), proc: denied, options: Self.fast)
            Issue.record("expected a 403")
        } catch {
            #expect(status(of: error) == 403)
            #expect((error as? ReinsError)?.message == "This session belongs to another user, so it cannot be stopped.")
        }
        let gone = FakeProcess(alive: [14], starts: [14: Self.start], terminateError: .noSuchProcess)
        #expect(try await stopSession(roots: try sb.roots, cli: .claude, id: activitySid(14), proc: gone, options: Self.fast) == StopResult(exited: true))
    }

    @Test("the real adapter ends a child process this test spawned, matched by its real start time")
    func realAdapter() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        let pid = Int(child.processIdentifier)
        let proc = SystemProcessAdapter()
        let sb = try ActivitySandbox()
        let start = try #require(await proc.startTime(pid: pid))
        #expect(await proc.isAlive(pid: pid))
        try sb.status(pid, ["sessionId": activitySid(50), "procStart": start])
        let result = try await stopSession(roots: try sb.roots, cli: .claude, id: activitySid(50), proc: proc)
        #expect(result == StopResult(exited: true))
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGTERM)
    }
}
