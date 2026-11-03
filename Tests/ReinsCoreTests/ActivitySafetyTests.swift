import Foundation
import Testing
@testable import ReinsCore

@Suite("Activity input and process identity safety")
struct ActivitySafetyTests {
    private static let originalStart = "Mon Nov  2 11:00:00 2026"
    private static let replacementStart = "Mon Nov  2 11:01:00 2026"
    private static let fast = StopOptions(waitMs: 0)

    @Test("a confirmed threadless row cannot stop a replacement process with the same pid")
    func reusedCodexPid() async throws {
        let sandbox = try ActivitySandbox()
        let threads = [CodexThread(pid: 71, threadId: nil)]
        let original = FakeProcess(alive: [71], starts: [71: Self.originalStart], threads: threads)
        let report = try await sandbox.read(original)
        let row = try #require(report.sessions.first { $0.pid == 71 })

        // The confirmation keeps the original row while the OS reuses its pid.
        let replacement = FakeProcess(alive: [71], starts: [71: Self.replacementStart], threads: threads)
        await expectRefusal(sandbox, id: row.id, proc: replacement)
        let missingStart = FakeProcess(alive: [71], threads: threads)
        await expectRefusal(sandbox, id: row.id, proc: missingStart)
        let malformedStart = FakeProcess(alive: [71], starts: [71: "unavailable"], threads: threads)
        await expectRefusal(sandbox, id: row.id, proc: malformedStart)

        // The same observed process remains stoppable, including ps whitespace variation.
        let same = FakeProcess(alive: [71], starts: [71: "Mon Nov  2  11:00:00  2026"], threads: threads)
        #expect(try await stopSession(roots: sandbox.roots, cli: .codex, id: row.id, proc: same, options: Self.fast).exited)
        #expect(same.killed == [71])
    }

    @Test("unknown and legacy bare pid rows never authorize Stop")
    func missingIdentity() async throws {
        let sandbox = try ActivitySandbox()
        let threads = [CodexThread(pid: 72, threadId: nil)]
        let unknown = FakeProcess(alive: [72], threads: threads)
        let report = try await sandbox.read(unknown)
        let row = try #require(report.sessions.first { $0.pid == 72 })
        #expect(row.ageMs == nil)
        let known = FakeProcess(alive: [72], starts: [72: Self.originalStart], threads: threads)
        for id in [row.id, "pid:72", "pid:72:unknown", "pid:72:invalid"] {
            await expectRefusal(sandbox, id: id, proc: known)
        }
    }

    private func expectRefusal(_ sandbox: ActivitySandbox, id: String, proc: FakeProcess) async {
        do {
            _ = try await stopSession(roots: sandbox.roots, cli: .codex, id: id, proc: proc, options: Self.fast)
            Issue.record("An unverified process identity must not authorize Stop")
        } catch {
            #expect((error as? ReinsError)?.status == 404)
        }
        #expect(proc.killed.isEmpty)
    }

    @Test("malformed numeric status timestamps produce an unknown title and safe ages")
    func invalidStatusTimestamps() async throws {
        let sandbox = try ActivitySandbox()
        for value in ["1e30", "-1e30", "1e309", "-1e309", "253402300800000", "-62167219200001"] {
            try sandbox.put(".claude/sessions/73.json", """
            {"pid":73,"sessionId":"timestamp-test","status":"idle","startedAt":\(value),"statusUpdatedAt":\(value)}
            """)
            let report = try await sandbox.read(FakeProcess(alive: [73]))
            let row = try #require(report.sessions.first { $0.pid == 73 })
            #expect(row.title == "unknown date · timestam")
            #expect(row.ageMs == nil)
            #expect(row.lastWriteAgoMs == 0)
            #expect(JSONSerialization.isValidJSONObject(report.jsonObject))
        }
        try sandbox.status(73)
        let valid = try await sandbox.read(FakeProcess(alive: [73]))
        let row = try #require(valid.sessions.first { $0.pid == 73 })
        #expect(row.ageMs == 3_600_000)
        #expect(row.lastWriteAgoMs == 3_000_000)
        #expect(row.title.hasPrefix("2026-11-02"))
    }

    @Test("time conversion rejects non-finite and out-of-domain inputs before integer arithmetic")
    func timeBounds() {
        for value in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, Double(Int64.max)] {
            #expect(ActivityText.isoString(value) == "unknown date")
            #expect(SessionTitles.pick([], startedAt: value, id: "test") == "unknown date · test")
        }
        #expect(ActivityText.isoString(0) == "1970-01-01T00:00:00.000Z")
        #expect(ActivityText.isoString(-62_167_219_200_000) == "0000-01-01T00:00:00.000Z")
        #expect(ActivityText.isoString(253_402_300_799_999) == "9999-12-31T23:59:59.999Z")
        for text in ["Mon Nov 2 9223372036854775807:00:00 2026", "Mon Nov 2 11:00:00 -9223372036854775808", "Mon Nov 2 25:00:00 2026", "Mon Nov 2 11:no:00:00 2026"] {
            #expect(ActivityText.parseProcessStart(text) == nil)
        }
        #expect(ActivityText.parseProcessStart(Self.originalStart) == activityNowMs - 3_600_000)
    }
}
