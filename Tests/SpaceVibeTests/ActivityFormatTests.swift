import Foundation
import Testing
@testable import SpaceVibe

@Suite("Activity wording", .fixtureCLIs)
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

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func iso(hoursAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func failure(
        kind: CoreFailureKind = .command, cli: CLIID = .claude, count: Int = 3, reason: String = "", exit: Int? = nil,
        last: String?, laterPass: String? = nil, hook: CoreActivityHookRef? = nil
    ) -> CoreActivityFailure {
        CoreActivityFailure(
            kind: kind, cli: cli, key: "k", title: "demo-check --all", count: count, exit: exit, reason: reason,
            projects: [], sessions: 1, first: last, last: last, laterPass: laterPass, hook: hook
        )
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
