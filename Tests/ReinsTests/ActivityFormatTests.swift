import Foundation
import Testing
@testable import Reins

@Suite("Activity wording")
struct ActivityFormatTests {
    private static let minute = 60_000.0
    private static let hour = 3_600_000.0

    // MARK: ActivityFormat

    @Test("span rounds down to minutes, hours with leftover minutes, then days")
    func span() {
        #expect(ActivityFormat.span(59_999) == "<1 min")
        #expect(ActivityFormat.span(18 * Self.minute) == "18 min")
        #expect(ActivityFormat.span(2 * Self.hour) == "2 h")
        #expect(ActivityFormat.span(2 * Self.hour + 5 * Self.minute) == "2 h 5 min")
        #expect(ActivityFormat.span(3 * 24 * Self.hour) == "3 d")
    }

    @Test("cost always carries the tilde, and a tiny cost reads as under one cent")
    func cost() {
        #expect(ActivityFormat.cost(0.004) == "~<$0.01")
        #expect(ActivityFormat.cost(1.5) == "~$1.50")
        #expect(ActivityFormat.cost(0) == "~$0.00")
    }

    // MARK: ActivityRows

    @Test("nextPage reveals one page and says how many stay hidden, or nil when everything is shown")
    func nextPage() throws {
        let first = try #require(ActivityRows.nextPage(shown: 8, total: 20, page: 8))
        #expect(first.reveal == 8)
        #expect(first.hiddenAfter == 4)
        let last = try #require(ActivityRows.nextPage(shown: 16, total: 20, page: 8))
        #expect(last.reveal == 4)
        #expect(last.hiddenAfter == 0)
        #expect(ActivityRows.nextPage(shown: 20, total: 20, page: 8) == nil)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func iso(hoursAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func failure(
        kind: CoreFailureKind = .command, cli: CoreCLI = .claude, count: Int = 3, reason: String = "", exit: Int? = nil,
        last: String?, laterPass: String? = nil, hook: CoreActivityHookRef? = nil
    ) -> CoreActivityFailure {
        CoreActivityFailure(
            kind: kind, cli: cli, key: "k", title: "demo-check --all", count: count, exit: exit, reason: reason,
            projects: [], sessions: 1, first: last, last: last, laterPass: laterPass, hook: hook
        )
    }

    private func report(_ failures: [CoreActivityFailure]) -> CoreActivityReport {
        CoreActivityReport(sessions: [], failures: failures, files: [], unmeasurable: [], stats: CoreActivityStats(logs: 0, truncated: 0))
    }

    @Test("only failures whose last one is under 24 hours old count toward the badge")
    func recentFailureCount() {
        let failures = [
            failure(last: iso(hoursAgo: 1)),
            failure(last: iso(hoursAgo: 23)),
            failure(last: iso(hoursAgo: 25)),
            failure(last: nil),
        ]
        #expect(ActivityRows.recentFailureCount(report(failures), now: now) == 2)
        #expect(ActivityRows.recentFailureCount(nil, now: now) == 0)
    }

    // MARK: FailureWording

    @Test("a reason that only repeats the exit code or says the hook failed is dropped", arguments: ["Exit 2", "Exit 137", "Hook failed", ""])
    func reasonDropped(reason: String) {
        let wording = FailureWording(failure(reason: reason, exit: 2, last: iso(hoursAgo: 1)), now: now)
        #expect(wording.reason == nil)
    }

    @Test("a reason that says more than the exit code is kept")
    func reasonKept() {
        let wording = FailureWording(failure(reason: "check failed", exit: 1, last: iso(hoursAgo: 1)), now: now)
        #expect(wording.reason == "check failed")
    }

    @Test("a hook failure names the hook event first; a command failure starts with the exit code")
    func howLine() {
        let hook = failure(kind: .hook, exit: 2, last: iso(hoursAgo: 1), hook: CoreActivityHookRef(hash: "abc123", event: "Stop"))
        #expect(FailureWording(hook, now: now).how.hasPrefix("Stop hook"))
        #expect(FailureWording(hook, now: now).how == "Stop hook \u{00B7} exit 2 \u{00B7} last 1 h ago")
        let command = failure(exit: 2, last: iso(hoursAgo: 1))
        #expect(FailureWording(command, now: now).how.hasPrefix("exit 2"))
    }

    // MARK: ActivityRows filters

    private func session(
        _ cli: CoreCLI = .claude, _ state: CoreSessionState = .running, id: String = "s1", project: String? = nil,
        reason: String = "log written 2 s ago", tool: CoreActivityTool? = nil, age: Double? = nil, lastWrite: Double? = nil
    ) -> CoreActivitySession {
        CoreActivitySession(
            cli: cli, id: id, title: "demo task", project: project, pid: 100, state: state, stateReason: reason,
            reasonCode: nil, currentTool: tool, ageMs: age, lastWriteAgoMs: lastWrite, cost: nil, costNote: nil
        )
    }

    @Test("sessions keeps only the asked CLI and drops ended ones, while idle, waiting and unmeasurable stay")
    func sessionsFilter() {
        let all = CoreActivityReport(
            sessions: [
                session(.claude, .running, id: "a"), session(.claude, .ended, id: "b"), session(.claude, .waiting, id: "c"),
                session(.claude, .idle, id: "d"), session(.claude, .unmeasurable, id: "e"),
                session(.codex, .idle, id: "f"), session(.codex, .ended, id: "g"),
            ],
            failures: [], files: [], unmeasurable: [], stats: CoreActivityStats(logs: 0, truncated: 0)
        )
        #expect(ActivityRows.sessions(all, cli: .claude).map(\.id) == ["a", "c", "d", "e"])
        #expect(ActivityRows.sessions(all, cli: .codex).map(\.id) == ["f"])
    }

    @Test("failures and limits keep only the asked CLI")
    func failuresAndLimitsFilter() {
        let limit = { (cli: CoreCLI, code: String) in CoreActivityLimit(cli: cli, code: code, text: "text of \(code)") }
        let all = CoreActivityReport(
            sessions: [], failures: [failure(cli: .claude, last: nil), failure(cli: .codex, last: nil), failure(cli: .claude, last: nil)],
            files: [], unmeasurable: [limit(.claude, "claude-prompt-vs-busy"), limit(.codex, "codex-tool-silent"), limit(.codex, "codex-no-rollout")],
            stats: CoreActivityStats(logs: 0, truncated: 0)
        )
        #expect(ActivityRows.failures(all, cli: .claude).count == 2)
        #expect(ActivityRows.failures(all, cli: .codex).count == 1)
        #expect(ActivityRows.limits(all, cli: .claude).map(\.code) == ["claude-prompt-vs-busy"])
        #expect(ActivityRows.limits(all, cli: .codex).map(\.code) == ["codex-tool-silent", "codex-no-rollout"])
    }

    // MARK: SessionWording

    private static let dot = " \u{00B7} "

    @Test("a running session is tagged success whichever CLI it is; waiting is a warning; unmeasurable carries the triangle; idle is neutral")
    func tagPerState() {
        let running = SessionWording(session(.claude, .running), elapsedMs: 0)
        #expect((running.tagText, running.tagTone, running.tagIcon) == ("running", .success, nil))
        #expect(SessionWording(session(.codex, .running), elapsedMs: 0).tagTone == .success)
        let waiting = SessionWording(session(.claude, .waiting), elapsedMs: 0)
        #expect((waiting.tagText, waiting.tagTone, waiting.tagIcon) == ("waiting for you", .warn, nil))
        let unmeasurable = SessionWording(session(.codex, .unmeasurable), elapsedMs: 0)
        #expect((unmeasurable.tagText, unmeasurable.tagTone, unmeasurable.tagIcon) == ("not measurable", .neutral, .warning))
        let idle = SessionWording(session(.claude, .idle), elapsedMs: 0)
        #expect((idle.tagText, idle.tagTone, idle.tagIcon) == ("idle", .neutral, nil))
    }

    @Test("the help text is the engine's reason, for every state")
    func helpIsTheReason() {
        for state in [CoreSessionState.running, .waiting, .idle, .unmeasurable] {
            #expect(SessionWording(session(.claude, state, reason: "because of \(state)"), elapsedMs: 0).help == "because of \(state)")
        }
    }

    @Test("a running session reads project, tool with its target, then how long ago it wrote")
    func subtitleRunning() {
        let tool = CoreActivityTool(name: "Bash", target: "swift test")
        let wording = SessionWording(session(project: "demo-app", tool: tool, lastWrite: 5_000), elapsedMs: 0)
        #expect(wording.subtitle == ["demo-app", "Bash \u{00B7} swift test", "just now"].joined(separator: Self.dot))
        #expect(SessionWording(session(tool: CoreActivityTool(name: "Read", target: "")), elapsedMs: 0).subtitle == "Read")
    }

    @Test("a waiting session says it needs an answer, even while a tool call is open")
    func subtitleWaiting() {
        let tool = CoreActivityTool(name: "Bash", target: "swift test")
        let wording = SessionWording(session(.codex, .waiting, project: "demo-app", tool: tool, lastWrite: 2 * Self.minute), elapsedMs: 0)
        #expect(wording.subtitle == ["demo-app", "needs your answer", "2 min ago"].joined(separator: Self.dot))
    }

    @Test("an unmeasurable session says so unless a tool call is known")
    func subtitleUnmeasurable() {
        #expect(SessionWording(session(.claude, .unmeasurable, project: "demo-app"), elapsedMs: 0).subtitle == "demo-app\(Self.dot)state not measurable")
        let tool = CoreActivityTool(name: "Edit", target: "a.swift")
        #expect(SessionWording(session(.claude, .unmeasurable, tool: tool), elapsedMs: 0).subtitle == "Edit \u{00B7} a.swift")
    }

    @Test("the time part adds the time since the report, and falls back to the start age when no log write is known")
    func subtitleElapsed() {
        #expect(SessionWording(session(lastWrite: 30_000), elapsedMs: 0).subtitle == "just now")
        #expect(SessionWording(session(lastWrite: 30_000), elapsedMs: 40_000).subtitle == "1 min ago")
        #expect(SessionWording(session(age: 18 * Self.minute), elapsedMs: 2 * Self.minute).subtitle == "started 20 min ago")
        #expect(SessionWording(session(age: 18 * Self.minute, lastWrite: 3 * Self.minute), elapsedMs: 0).subtitle == "3 min ago")
        #expect(SessionWording(session(), elapsedMs: 0).subtitle == "")
    }

    // MARK: ActivityFormat wording

    private func isoAgo(seconds: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-seconds))
    }

    @Test("a later pass is worded as a fact about the log: counts the failures, says one pass is not proof, never says fixed")
    func laterPassWording() throws {
        let pass = isoAgo(seconds: 2 * 3600)
        let clock = ActivityFormat.clock(pass, now: now)
        let many = try #require(ActivityFormat.laterPass(failure(count: 3, last: iso(hoursAgo: 3), laterPass: pass), now: now))
        #expect(many == "passed once at \(clock) after 3 failures; one pass is not proof")
        let single = try #require(ActivityFormat.laterPass(failure(count: 1, last: iso(hoursAgo: 3), laterPass: pass), now: now))
        #expect(single == "passed once at \(clock) after 1 failure; one pass is not proof")
        for text in [many, single] {
            #expect(text.contains("not proof"))
            #expect(!text.lowercased().contains("fix"))
        }
    }

    @Test("no later pass means no sentence")
    func laterPassAbsent() {
        #expect(ActivityFormat.laterPass(failure(last: iso(hoursAgo: 1), laterPass: nil), now: now) == nil)
    }

    @Test("projects: nothing for none, the names for one or two, a count for more")
    func projectsWording() {
        #expect(ActivityFormat.projects([]) == nil)
        #expect(ActivityFormat.projects(["app-a"]) == "app-a")
        #expect(ActivityFormat.projects(["app-a", "app-b"]) == "app-a, app-b")
        #expect(ActivityFormat.projects(["app-a", "app-b", "app-c"]) == "3 projects")
    }

    @Test("the engine's fallback title is recognised, a real request is not",
          arguments: [("2026-11-02 \u{00B7} 1a2b3c4d", true), ("unknown date \u{00B7} 1a2b3c4d", true), ("2026-11-02 \u{00B7} ", true),
                      ("Fix the login form", false), ("2026-11-02 \u{00B7} 1a2b3c4d5", false), ("2026-11-02 \u{00B7} two words", false),
                      ("2026-1-02 \u{00B7} 1a2b3c4d", false), ("", false)])
    func fallbackTitle(title: String, expected: Bool) {
        #expect(ActivityFormat.isFallbackTitle(title) == expected)
    }

    @Test("ago: just now under a minute, minutes and hours, yesterday up to two days, then a date")
    func agoWording() {
        #expect(ActivityFormat.ago(isoAgo(seconds: 30), now: now) == "just now")
        #expect(ActivityFormat.ago(isoAgo(seconds: -30), now: now) == "just now")
        #expect(ActivityFormat.ago(isoAgo(seconds: 4 * 60), now: now) == "4 min ago")
        #expect(ActivityFormat.ago(isoAgo(seconds: 3600), now: now) == "1 h ago")
        #expect(ActivityFormat.ago(isoAgo(seconds: 23 * 3600), now: now) == "23 h ago")
        #expect(ActivityFormat.ago(isoAgo(seconds: 30 * 3600), now: now) == "yesterday")
        let dated = ActivityFormat.ago(isoAgo(seconds: 3 * 86_400), now: now)
        #expect(dated.range(of: #"^[A-Z][a-z]{2} \d{1,2}$"#, options: .regularExpression) != nil)
    }

    @Test("ago says unknown when the time is missing or not a date")
    func agoUnknown() {
        #expect(ActivityFormat.ago(nil, now: now) == "unknown")
        #expect(ActivityFormat.ago("not a date", now: now) == "unknown")
    }
}
