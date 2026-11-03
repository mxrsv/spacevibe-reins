import Foundation
import Testing
@testable import ReinsCore

/// AC10: usage limits come from synthetic files in a temporary home; nothing reaches the network.
@Suite("Limits")
struct LimitsTests {
    // MARK: Claude Code

    /// The shape seen in Claude Code 2.1.317's state file, with synthetic values and the account fields left out.
    private func claudeCache(fetchedAtMs: String = "1793500000250", limits: String) -> String {
        """
        {"numStartups": 3, "cachedUsageUtilization": {"fetchedAtMs": \(fetchedAtMs), "accountUuid": "synthetic",
          "utilization": {"five_hour": null, "seven_day": {"utilization": 8}, "limits": \(limits)}}}
        """
    }

    private let twoWeekly = """
        [{"kind": "weekly_all", "group": "weekly", "percent": 8, "severity": "normal",
          "resets_at": "2026-11-06T16:00:00.803412+00:00", "scope": null, "is_active": true},
         {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
          "resets_at": "2026-11-06T15:59:59.803620+00:00",
          "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}]
        """

    @Test("Claude Code: each cached limit becomes a window with its share, reset and fetch time")
    func claudeMeasured() throws {
        let home = try TempHome()
        try home.write(".claude/.claude.json", claudeCache(limits: twoWeekly))
        let result = LimitsClaudeCache.read(try home.roots)
        guard case .measured(let at, let windows) = result.state else {
            Issue.record("expected a reading, got \(result.state)")
            return
        }
        #expect(at == Date(timeIntervalSince1970: 1_793_500_000.25))
        #expect(windows.map(\.id) == ["weekly_all", "weekly_scoped:Fable"])
        #expect(windows.map(\.minutes) == [10080, 10080])
        #expect(windows.map(\.scope) == [nil, "Fable"])
        #expect(windows.map(\.usedPercent) == [8, 0])
        #expect(windows.map(\.active) == [true, false])
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1_793_980_800.803))
    }

    @Test("Claude Code: without CLAUDE_CONFIG_DIR the state file is the one in HOME")
    func claudeStateInHome() throws {
        let home = try TempHome()
        try FileManager.default.createDirectory(at: home.claude, withIntermediateDirectories: true)
        try home.write(".claude.json", claudeCache(limits: twoWeekly))
        var env = home.env
        env["CLAUDE_CONFIG_DIR"] = nil
        let result = LimitsClaudeCache.read(try Roots.resolve(env: env))
        guard case .measured = result.state else {
            Issue.record("expected a reading, got \(result.state)")
            return
        }
    }

    @Test("Claude Code: no cache, an empty list, and no install read differently")
    func claudeNotRecorded() throws {
        let home = try TempHome()
        #expect(LimitsClaudeCache.read(try home.roots).state == .notInstalled)

        try FileManager.default.createDirectory(at: home.claude, withIntermediateDirectories: true)
        #expect(LimitsClaudeCache.read(try home.roots).state == .notRecorded)

        try home.write(".claude/.claude.json", #"{"numStartups": 3}"#)
        #expect(LimitsClaudeCache.read(try home.roots).state == .notRecorded)

        try home.write(".claude/.claude.json", claudeCache(limits: "[]"))
        #expect(LimitsClaudeCache.read(try home.roots).state == .notRecorded)
    }

    @Test("Claude Code: a broken file or an unknown entry shape is unreadable, never a partial list")
    func claudeUnreadable() throws {
        let home = try TempHome()
        try home.write(".claude/.claude.json", "{not json")
        #expect(LimitsClaudeCache.read(try home.roots).state == .unreadable)

        let oneBad = """
            [{"kind": "weekly_all", "group": "weekly", "percent": 8, "resets_at": "2026-11-06T16:00:00Z"},
             {"kind": "five_hour", "percent": "93%", "resets_at": "2026-11-03T20:00:00Z"}]
            """
        try home.write(".claude/.claude.json", claudeCache(limits: oneBad))
        #expect(LimitsClaudeCache.read(try home.roots).state == .unreadable)

        try home.write(".claude/.claude.json", claudeCache(fetchedAtMs: "\"yesterday\"", limits: twoWeekly))
        #expect(LimitsClaudeCache.read(try home.roots).state == .unreadable)

        let badReset = #"[{"kind": "weekly_all", "percent": 8, "resets_at": "next week"}]"#
        try home.write(".claude/.claude.json", claudeCache(limits: badReset))
        #expect(LimitsClaudeCache.read(try home.roots).state == .unreadable)
    }

    @Test("Claude Code: window length comes from the group or kind, unknown names stay unknown")
    func claudeMinutes() {
        #expect(LimitsClaudeCache.minutes(kind: "weekly_all", group: "weekly") == 10080)
        #expect(LimitsClaudeCache.minutes(kind: "five_hour", group: nil) == 300)
        #expect(LimitsClaudeCache.minutes(kind: "session", group: "session") == 300)
        #expect(LimitsClaudeCache.minutes(kind: "monthly_all", group: "monthly") == nil)
    }

    // MARK: Codex

    private func tokenCount(_ timestamp: String, _ rateLimits: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":\#(rateLimits)}}"#
    }

    private let weekly = #"{"limit_id":"codex","limit_name":null,"primary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1794300000},"secondary":null,"credits":{"has_credits":false},"plan_type":"pro"}"#

    private func rollout(_ home: TempHome, _ name: String, _ lines: [String], modified: Date) throws {
        let url = try home.write(".codex/sessions/2026/11/03/\(name).jsonl", lines.joined(separator: "\n") + "\n")
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    @Test("Codex: the newest token_count event with limits is the reading")
    func codexMeasured() throws {
        let home = try TempHome()
        let older = #"{"primary":{"used_percent":40.5,"window_minutes":300,"resets_at":1794200000},"secondary":{"used_percent":1,"window_minutes":10080,"resets_at":1794300000},"plan_type":"plus"}"#
        try rollout(home, "rollout-a", [
            #"{"timestamp":"2026-11-03T10:00:00.000Z","type":"session_meta","payload":{"id":"a"}}"#,
            tokenCount("2026-11-03T10:01:00.000Z", older),
            tokenCount("2026-11-03T10:46:28.500Z", weekly),
            tokenCount("2026-11-03T10:47:00.000Z", "null"),
        ], modified: Date())
        let result = LimitsCodexLogs.read(try home.roots)
        #expect(result.plan == "pro")
        guard case .measured(let at, let windows) = result.state else {
            Issue.record("expected a reading, got \(result.state)")
            return
        }
        #expect(at == Date(timeIntervalSince1970: 1_793_702_788.5))
        #expect(windows == [LimitWindow(id: "primary", minutes: 10080, scope: nil, usedPercent: 2,
                                        resetsAt: Date(timeIntervalSince1970: 1_794_300_000), active: true)])
    }

    @Test("Codex: the most recently written log wins over the newest path")
    func codexNewestByModification() throws {
        let home = try TempHome()
        let fresh = #"{"primary":{"used_percent":70,"window_minutes":300,"resets_at":1794200000}}"#
        try rollout(home, "rollout-z-new-path", [tokenCount("2026-11-03T09:00:00Z", weekly)], modified: Date(timeIntervalSinceNow: -3600))
        try rollout(home, "rollout-a-resumed", [tokenCount("2026-11-03T11:00:00Z", fresh)], modified: Date())
        guard case .measured(_, let windows) = LimitsCodexLogs.read(try home.roots).state else {
            Issue.record("expected a reading")
            return
        }
        #expect(windows.map(\.usedPercent) == [70])
    }

    @Test("Codex: the older relative reset counts from the event time")
    func codexRelativeReset() throws {
        let home = try TempHome()
        let relative = #"{"primary":{"used_percent":12,"window_minutes":300,"resets_in_seconds":600}}"#
        try rollout(home, "rollout-a", [tokenCount("2026-11-03T10:00:00Z", relative)], modified: Date())
        guard case .measured(let at, let windows) = LimitsCodexLogs.read(try home.roots).state else {
            Issue.record("expected a reading")
            return
        }
        #expect(windows.first?.resetsAt == at.addingTimeInterval(600))
    }

    @Test("Codex: no install, no event and an unknown window shape read differently")
    func codexOtherStates() throws {
        let home = try TempHome()
        #expect(LimitsCodexLogs.read(try home.roots).state == .notInstalled)

        try rollout(home, "rollout-a", [#"{"timestamp":"2026-11-03T10:00:00Z","type":"session_meta","payload":{}}"#], modified: Date())
        #expect(LimitsCodexLogs.read(try home.roots).state == .notRecorded)

        let noReset = #"{"primary":{"used_percent":12,"window_minutes":300}}"#
        try rollout(home, "rollout-b", [tokenCount("2026-11-03T10:00:00Z", noReset)], modified: Date())
        #expect(LimitsCodexLogs.read(try home.roots).state == .unreadable)
    }

    // MARK: Gemini CLI and the whole read

    @Test("Gemini CLI keeps no limit on disk, so it is not measurable once installed")
    func gemini() throws {
        let home = try TempHome()
        #expect(Limits.gemini(try home.roots).state == .notInstalled)
        try FileManager.default.createDirectory(at: home.url(".gemini"), withIntermediateDirectories: true)
        #expect(Limits.gemini(try home.roots).state == .notMeasurable)
    }

    @Test("read reports Claude Code, Codex and Gemini CLI in order")
    func readAll() throws {
        let home = try TempHome()
        #expect(Limits.read(try home.roots).map(\.cli) == [.claude, .codex, .gemini])
    }

    @Test("a window whose reset has passed is no longer current")
    func passedReset() {
        let window = LimitWindow(id: "primary", minutes: 300, scope: nil, usedPercent: 90,
                                 resetsAt: Date(timeIntervalSince1970: 1000), active: true)
        #expect(window.isCurrent(at: Date(timeIntervalSince1970: 999)))
        #expect(!window.isCurrent(at: Date(timeIntervalSince1970: 1000)))
    }

    @Test("the Limits readers start no request and no process (S-R4, S-R5)")
    func noNetworkOrProcess() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ReinsCore")
        for name in ["Limits.swift", "LimitsClaudeCache.swift", "LimitsCodexLogs.swift"] {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for banned in ["URLSession", "URLRequest", "Process(", "posix_spawn", "ProcessAdapter"] {
                #expect(!text.contains(banned), "\(name) mentions \(banned)")
            }
        }
    }
}
