import Foundation
import Testing
@testable import ReinsCore
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
        kind: ActivityFailure.Kind = .command, reason: String = "", exit: Int? = nil,
        last: String?, hook: ActivityFailure.Hook? = nil
    ) -> ActivityFailure {
        ActivityFailure(
            kind: kind, cli: .claude, key: "k", title: "demo-check --all", count: 3, exit: exit, reason: reason,
            projects: [], sessions: 1, first: last, last: last, laterPass: nil, hook: hook
        )
    }

    private func report(_ failures: [ActivityFailure]) -> ActivityReport {
        ActivityReport(sessions: [], failures: failures, files: [], unmeasurable: [], stats: ActivityStats(logs: 0, truncated: 0))
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
        let hook = failure(kind: .hook, exit: 2, last: iso(hoursAgo: 1), hook: ActivityFailure.Hook(hash: "abc123", event: "Stop"))
        #expect(FailureWording(hook, now: now).how.hasPrefix("Stop hook"))
        #expect(FailureWording(hook, now: now).how == "Stop hook \u{00B7} exit 2 \u{00B7} last 1 h ago")
        let command = failure(exit: 2, last: iso(hoursAgo: 1))
        #expect(FailureWording(command, now: now).how.hasPrefix("exit 2"))
    }
}
