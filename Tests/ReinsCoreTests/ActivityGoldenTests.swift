import Foundation
import Testing
@testable import ReinsCore

/// Swift `readActivity` against what the Node core returned for the same logs (scripts/golden/activity.mjs).
/// Two cases: the shared fixture HOME, and the section-specific Fixtures/activity-home rebuilt in a TempHome.
/// Lists whose order is not part of the contract are sorted by the same keys the golden script used.
@Suite("Activity golden")
struct ActivityGoldenTests {
    private static var options: ActivityOptions {
        var options = ActivityOptions()
        options.maxHistoryFiles = 100_000 // the golden script lifts the cap so directory order cannot decide which logs are read
        return options
    }

    private func canonical(_ report: ActivityReport) -> [String: Any] {
        func sorted<T>(_ items: [T], _ key: (T) -> String) -> [T] { items.sorted { key($0) < key($1) } }
        return [
            "sessions": sorted(report.sessions) { "\($0.cli.rawValue)|\($0.id)" }.map(\.jsonObject),
            "failures": sorted(report.failures) { "\($0.cli.rawValue)|\($0.kind.rawValue)|\($0.key)" }.map(\.jsonObject),
            "files": sorted(report.files, { $0.path }).map(\.jsonObject),
            "unmeasurable": ActivityReport(sessions: [], failures: [], files: [], unmeasurable: report.unmeasurable, stats: report.stats).jsonObject["unmeasurable"] as Any,
            "stats": ["logs": report.stats.logs, "truncated": report.stats.truncated],
        ]
    }

    private func golden() throws -> (cases: [String: Any], procs: [String: Any]) {
        let all = try #require(try FixtureHome.golden("activity") as? [String: Any])
        let procs = try #require(try FixtureHome.golden("activity-proc") as? [String: Any])
        #expect((all["now"] as? NSNumber)?.doubleValue == activityNowMs)
        return (all, procs)
    }

    @Test("shared fixture HOME: sessions, failures and files match the Node report")
    func sharedHome() async throws {
        let (all, procs) = try golden()
        try FixtureHome.materialize()
        let roots = try Roots.resolve(env: FixtureHome.env)
        let proc = FakeProcess(spec: try #require(procs["shared"] as? [String: Any]))
        let report = await readActivity(roots: roots, now: try FixtureHome.now(), proc: proc, options: Self.options)
        let diff = FixtureHome.firstDifference(FixtureHome.normalize(canonical(report)), try #require(all["shared"]))
        #expect(diff == nil, Comment(rawValue: diff ?? ""))
        // the shared tree must keep covering the cases it was written for
        #expect(report.sessions.contains { $0.state == .running && $0.cli == .claude })
        #expect(report.sessions.contains { $0.state == .waiting })
        #expect(report.sessions.contains { $0.reasonCode == .codexToolSilent })
        #expect(report.sessions.contains { $0.reasonCode == .codexNoRollout })
        #expect(report.failures.contains { $0.count == 8 && $0.laterPass != nil })
    }

    @Test("section fixture HOME: ended, unknown, unpriced, compressed, child, hook and legacy cases match the Node report")
    func extraHome() async throws {
        let (all, procs) = try golden()
        let sb = try ActivitySandbox()
        let source = Fixtures.url("activity-home")
        let mtimes = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("mtimes.json"))) as? [String: Any])
        for (relative, value) in try #require(mtimes["mtimes"] as? [String: Any]) {
            let url = try sb.home.write(relative, try Data(contentsOf: source.appendingPathComponent(relative)))
            let ms = try #require((value as? NSNumber)?.doubleValue)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: ms / 1000)], ofItemAtPath: url.path)
        }
        let proc = FakeProcess(spec: try #require(procs["extra"] as? [String: Any]))
        let report = try await sb.read(proc, options: Self.options)
        let diff = FixtureHome.firstDifference(FixtureHome.normalize(canonical(report)), try #require(all["extra"]))
        #expect(diff == nil, Comment(rawValue: diff ?? ""))
        #expect(report.sessions.contains { $0.state == .ended })
        #expect(report.sessions.contains { $0.reasonCode == .claudeUnknownStatus })
        #expect(report.sessions.contains { $0.cost == nil && ($0.costNote ?? "").hasPrefix("No price for model") })
        #expect(report.failures.contains { $0.kind == .hook })
        // R4: the recorded `touch` command is listed as a failure and was never run
        #expect(report.failures.contains { $0.title.hasPrefix("touch /nonexistent-reins-marker/") })
        #expect(!FileManager.default.fileExists(atPath: "/nonexistent-reins-marker/must-not-exist"))
    }

    @Test("a compressed rollout is read once, and a tail cut is reported")
    func compressedRollouts() async throws {
        let sb = try ActivitySandbox()
        let source = Fixtures.url("activity-home")
        let mtimes = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("mtimes.json"))) as? [String: Any])
        for (relative, value) in try #require(mtimes["mtimes"] as? [String: Any]) where relative.hasSuffix(".jsonl.zst") || relative == ".codex/session_index.jsonl" {
            let url = try sb.home.write(relative, try Data(contentsOf: source.appendingPathComponent(relative)))
            let ms = try #require((value as? NSNumber)?.doubleValue)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: ms / 1000)], ofItemAtPath: url.path)
        }
        let engine = ActivityEngine()
        let threads = [CodexThread(pid: 4049, threadId: activityUuid(49)), CodexThread(pid: 4050, threadId: activityUuid(50))]
        let proc = FakeProcess(threads: threads)
        let first = await engine.readActivity(roots: try sb.roots, now: activityNow, proc: proc, options: Self.options)
        let build = try #require(first.failures.first { $0.title == "npm run build" })
        #expect(build.count == 2)
        #expect(first.files.map(\.path).contains("/work/app-a/src/rank.ts"))
        #expect(session(first, activityUuid(49))?.state == .running)
        #expect(session(first, activityUuid(50)) == nil, "a compressed child rollout is not a session")
        let second = await engine.readActivity(roots: try sb.roots, now: activityNow, proc: proc, options: Self.options)
        #expect(second == first, "a second read must not fold the same lines again")

        var cut = Self.options
        cut.historyTailBytes = 300
        cut.liveTailBytes = 300
        let small = await readActivity(roots: try sb.roots, now: activityNow, proc: proc, options: cut)
        #expect(small.stats.truncated >= 1)
        #expect(session(small, activityUuid(49))?.cost == nil)
    }
}
