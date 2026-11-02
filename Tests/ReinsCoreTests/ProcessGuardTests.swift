import Foundation
import Testing
@testable import ReinsCore

/// The real adapter's guard on pids. `kill(0, sig)` signals the caller's whole process group and `kill(-1, sig)` every
/// process the user may signal, so a pid like that must never reach `kill`. These tests call the real adapter: if the
/// guard were missing, the second one would signal the test run itself, which is why they only use pids it refuses.
@Suite("Process adapter pid guard")
struct ProcessGuardTests {
    private static let unsafePids = [0, -1, -4242, Int(Int32.max) + 1, Int.max, Int.min]

    @Test("terminate refuses a pid that is zero, negative or does not fit in pid_t, before any signal")
    func terminateRefuses() async {
        let adapter = SystemProcessAdapter()
        for pid in Self.unsafePids {
            do {
                try await adapter.terminate(pid: pid)
                Issue.record("terminate(pid: \(pid)) returned without throwing")
            } catch {
                #expect(error as? ProcessSignalError == .noSuchProcess, "pid \(pid)")
            }
        }
    }

    @Test("isAlive is false for a pid that is zero, negative or too large, and startTime is nil")
    func isAliveRefuses() async {
        let adapter = SystemProcessAdapter()
        for pid in Self.unsafePids {
            #expect(await adapter.isAlive(pid: pid) == false, "pid \(pid)")
            #expect(await adapter.startTime(pid: pid) == nil, "pid \(pid)")
        }
    }

    @Test("stopSession with a status file that carries pid 0 or -1 finds no live session and signals nothing")
    func stopSessionWithUnsafePidInStatusFile() async throws {
        for (file, pid) in [("0.json", 0), ("1.json", -1)] {
            let home = try TempHome()
            let roots = try Roots.resolve(env: home.env)
            let id = "00000000-0000-4000-8000-00000000000a"
            try home.write(".claude/sessions/\(file)", "{\"pid\": \(pid), \"sessionId\": \"\(id)\", \"procStart\": \"Mon Nov  2 11:00:00 2026\", \"status\": \"idle\"}")
            do {
                _ = try await stopSession(roots: roots, cli: .claude, id: id, proc: SystemProcessAdapter(), options: StopOptions(waitMs: 30, pollMs: 5))
                Issue.record("stopSession for pid \(pid) returned without throwing")
            } catch {
                #expect((error as? ReinsError)?.status == 404, "pid \(pid)")
            }
        }
    }
}
