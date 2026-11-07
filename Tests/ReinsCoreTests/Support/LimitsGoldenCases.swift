import Foundation
@testable import ReinsCore

/// The scenarios of LimitsTests and the read side of LimitsStatuslineTests, as data. The inputs are the ones those tests
/// write; the status line snapshots, which those tests produce by running the collector, are written out as the files it
/// leaves (`snapshotShapeMatchesCapture` holds the two together). Order does not matter, names must be unique.
extension LimitsGoldenCase {
    private static let weeklyReset = 1_794_000_000
    private static let defaultAccount = "synthetic-account"
    private static let claudeState = ".claude/.claude.json"

    // MARK: Claude Code inputs

    /// The shape seen in Claude Code 2.1.317's state file, with synthetic values and the account fields left out.
    static func claudeCache(fetchedAtMs: String = "1793500000250", limits: String) -> String {
        """
        {"numStartups": 3, "cachedUsageUtilization": {"fetchedAtMs": \(fetchedAtMs), "accountUuid": "synthetic",
          "utilization": {"five_hour": null, "seven_day": {"utilization": 8}, "limits": \(limits)}}}
        """
    }

    private static let twoWeekly = """
        [{"kind": "weekly_all", "group": "weekly", "percent": 8, "severity": "normal",
          "resets_at": "2026-11-06T16:00:00.803412+00:00", "scope": null, "is_active": true},
         {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
          "resets_at": "2026-11-06T15:59:59.803620+00:00",
          "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}]
        """

    private static let mixedKinds = """
        [{"kind": "weekly_all", "group": "weekly", "percent": 8, "resets_at": "2026-11-06T16:00:00Z"},
         {"kind": "five_hour", "percent": 30.5, "resets_at": "2026-11-05T20:00:00Z"},
         {"kind": "session", "group": "session", "percent": 1, "resets_at": "2026-11-05T21:00:00Z"},
         {"kind": "monthly_all", "group": "monthly", "percent": 4, "resets_at": "2026-12-01T00:00:00Z"}]
        """

    /// A state file with an account and a cached 62% weekly reading (LimitsStatuslineTests.account).
    static func accountState(_ name: String) -> String {
        """
        {"oauthAccount":{"accountUuid":"\(name)","organizationUuid":"synthetic-org"},
         "cachedUsageUtilization":{"fetchedAtMs":1793800000000,"utilization":{"limits":[
         {"kind":"weekly_all","group":"weekly","percent":62,"resets_at":"2026-11-06T16:00:00Z"}]}}}
        """
    }

    /// The file the collector leaves for one session: `windows` are (status line key, used_percentage text, resets_at).
    static func snapshot(session: String, account: String, observed: Double, windows: [(String, String, Int)]) -> File {
        let members = windows.map { #""\#($0.0)":{"used_percentage":\#($0.1),"resets_at":\#($0.2)}"# }.joined(separator: ",")
        let text = #"{"account":"$ACCOUNT_KEY(\#(account),synthetic-org)","observedAt":\#(String(observed)),"rate_limits":{\#(members)}}"#
        return File(path: ".spacevibe/claude-limits/\(session).json", text: text, mtime: observed)
    }

    private static func weeklySnapshot(_ session: String, _ used: String, observed: Double, account: String = defaultAccount,
                                       reset: Int = weeklyReset) -> File {
        snapshot(session: session, account: account, observed: observed, windows: [("seven_day", used, reset)])
    }

    // MARK: Codex inputs

    private static func tokenCount(_ timestamp: String, _ rateLimits: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":\#(rateLimits)}}"#
    }

    private static let weekly = #"{"limit_id":"codex","limit_name":null,"primary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1794300000},"secondary":null,"credits":{"has_credits":false},"plan_type":"pro"}"#

    private static func rollout(_ name: String, _ lines: [String], mtime: Double = defaultNow) -> File {
        File(path: ".codex/sessions/2026/11/03/\(name).jsonl", text: lines.joined(separator: "\n") + "\n", mtime: mtime)
    }

    // MARK: Cases

    static func all() throws -> [LimitsGoldenCase] {
        let now = defaultNow
        let state = claudeState
        let sessionMeta = #"{"timestamp":"2026-11-03T10:00:00.000Z","type":"session_meta","payload":{"id":"a"}}"#
        let older = #"{"primary":{"used_percent":40.5,"window_minutes":300,"resets_at":1794200000},"secondary":{"used_percent":1,"window_minutes":10080,"resets_at":1794300000},"plan_type":"plus"}"#
        let fresh = #"{"primary":{"used_percent":70,"window_minutes":300,"resets_at":1794200000}}"#
        let relative = #"{"primary":{"used_percent":12,"window_minutes":300,"resets_in_seconds":600}}"#
        let noReset = #"{"primary":{"used_percent":12,"window_minutes":300}}"#
        let passed = #"{"primary":{"used_percent":90,"window_minutes":300,"resets_at":\#(Int(now) - 1)},"secondary":{"used_percent":10,"window_minutes":10080,"resets_at":\#(Int(now))},"plan_type":"pro"}"#
        let oneBad = """
            [{"kind": "weekly_all", "group": "weekly", "percent": 8, "resets_at": "2026-11-06T16:00:00Z"},
             {"kind": "five_hour", "percent": "93%", "resets_at": "2026-11-03T20:00:00Z"}]
            """
        let cacheTime = now + 10
        let newerCacheState = try String(decoding: OrderedJSON(text: accountState(defaultAccount))
            .setting(["cachedUsageUtilization", "fetchedAtMs"], to: .number(String(cacheTime * 1000))).data, as: UTF8.self)

        return [
            // Claude Code cache
            LimitsGoldenCase(name: "empty-home"),
            LimitsGoldenCase(name: "claude-cache-measured", files: [File(path: state, text: claudeCache(limits: twoWeekly))]),
            LimitsGoldenCase(name: "claude-cache-window-minutes", files: [File(path: state, text: claudeCache(limits: mixedKinds))]),
            LimitsGoldenCase(name: "claude-state-in-home", unsetClaudeConfigDir: true, dirs: [".claude"],
                             files: [File(path: ".claude.json", text: claudeCache(limits: twoWeekly))]),
            LimitsGoldenCase(name: "claude-not-recorded-no-state-file", dirs: [".claude"]),
            LimitsGoldenCase(name: "claude-not-recorded-no-cache-key", files: [File(path: state, text: #"{"numStartups": 3}"#)]),
            LimitsGoldenCase(name: "claude-not-recorded-empty-limits", files: [File(path: state, text: claudeCache(limits: "[]"))]),
            LimitsGoldenCase(name: "claude-unreadable-broken-json", files: [File(path: state, text: "{not json")]),
            LimitsGoldenCase(name: "claude-unreadable-one-bad-entry", files: [File(path: state, text: claudeCache(limits: oneBad))]),
            LimitsGoldenCase(name: "claude-unreadable-bad-fetched-at",
                             files: [File(path: state, text: claudeCache(fetchedAtMs: "\"yesterday\"", limits: twoWeekly))]),
            LimitsGoldenCase(name: "claude-unreadable-bad-reset",
                             files: [File(path: state, text: claudeCache(limits: #"[{"kind": "weekly_all", "percent": 8, "resets_at": "next week"}]"#))]),
            // Codex rollouts
            LimitsGoldenCase(name: "codex-token-count-measured", files: [rollout("rollout-a", [
                sessionMeta,
                tokenCount("2026-11-03T10:01:00.000Z", older),
                tokenCount("2026-11-03T10:46:28.500Z", weekly),
                tokenCount("2026-11-03T10:47:00.000Z", "null"),
            ])]),
            LimitsGoldenCase(name: "codex-newest-log-by-modification", files: [
                rollout("rollout-z-new-path", [tokenCount("2026-11-03T09:00:00Z", weekly)], mtime: now - 3600),
                rollout("rollout-a-resumed", [tokenCount("2026-11-03T11:00:00Z", fresh)], mtime: now),
            ]),
            LimitsGoldenCase(name: "codex-relative-reset", files: [rollout("rollout-a", [tokenCount("2026-11-03T10:00:00Z", relative)])]),
            LimitsGoldenCase(name: "codex-not-recorded-no-event", files: [rollout("rollout-a", [sessionMeta])]),
            LimitsGoldenCase(name: "codex-unreadable-window-without-reset", files: [
                rollout("rollout-a", [sessionMeta], mtime: now - 60),
                rollout("rollout-b", [tokenCount("2026-11-03T10:00:00Z", noReset)], mtime: now),
            ]),
            LimitsGoldenCase(name: "codex-passed-reset", files: [rollout("rollout-a", [tokenCount("2026-11-03T10:00:00Z", passed)])]),
            // Gemini CLI
            LimitsGoldenCase(name: "gemini-not-measurable", dirs: [".gemini"]),
            // Claude Code status line snapshots
            LimitsGoldenCase(name: "statusline-supersedes-cache", files: [
                File(path: state, text: accountState(defaultAccount)),
                weeklySnapshot("test-session", "76", observed: now),
            ]),
            LimitsGoldenCase(name: "statusline-idle-session-keeps-highest", now: now + 2, files: [
                File(path: state, text: accountState(defaultAccount)),
                weeklySnapshot("active", "76", observed: now),
                weeklySnapshot("idle", "62", observed: now + 1),
            ]),
            LimitsGoldenCase(name: "statusline-new-reset-window", now: now + 4, files: [
                File(path: state, text: accountState(defaultAccount)),
                weeklySnapshot("active", "76", observed: now),
                weeklySnapshot("idle", "62", observed: now + 1),
                weeklySnapshot("new-window", "1", observed: now + 3, reset: weeklyReset + 604_800),
            ]),
            LimitsGoldenCase(name: "statusline-both-windows-merge", now: now + 2, files: [
                File(path: state, text: accountState(defaultAccount)),
                snapshot(session: "both", account: defaultAccount, observed: now,
                         windows: [("five_hour", "95.5", weeklyReset - 1000), ("seven_day", "76.25", weeklyReset)]),
                weeklySnapshot("partial", "62", observed: now + 1),
            ]),
            LimitsGoldenCase(name: "statusline-stale-session-outside-merge-age", now: now + 1, files: [
                File(path: state, text: accountState(defaultAccount)),
                weeklySnapshot("older", "90", observed: now - 4000),
                weeklySnapshot("newer", "50", observed: now),
            ]),
            LimitsGoldenCase(name: "statusline-newer-cache-supersedes", now: now + 20, files: [
                File(path: state, text: newerCacheState),
                weeklySnapshot("test-session", "76", observed: now),
            ]),
            LimitsGoldenCase(name: "statusline-account-change-keeps-cache", now: now + 2, files: [
                File(path: state, text: accountState("another-account")),
                weeklySnapshot("test-session", "76", observed: now),
            ]),
            LimitsGoldenCase(name: "statusline-account-change-new-login", now: now + 4, files: [
                File(path: state, text: accountState("another-account")),
                weeklySnapshot("test-session", "76", observed: now),
                weeklySnapshot("new-login", "5", observed: now + 3, account: "another-account"),
            ]),
            LimitsGoldenCase(name: "statusline-invalid-files-fall-back", files: [
                File(path: state, text: accountState(defaultAccount)),
                File(path: ".spacevibe/claude-limits/invalid.json", text: "{bad"),
                File(path: ".spacevibe/claude-limits/large.json", repeating: (" ", 5000)),
                weeklySnapshot("test-session", "76", observed: now + 60),
            ], fifos: [".spacevibe/claude-limits/fifo.json"]),
        ]
    }
}
