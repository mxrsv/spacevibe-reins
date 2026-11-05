import Foundation
import Testing
@testable import ReinsCore
@testable import Reins

/// AC10, wording half: share left, tone, resets, reading age, the short states and the stale marker, against fixed dates.
@Suite("Limits wording")
struct LimitsWordingTests {
    private static let hour = 3600.0
    /// 2026-11-03 18:00 at UTC+7, the clock of the mock.
    private static let now = Date(timeIntervalSince1970: 1_793_703_600)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }()

    private func window(_ id: String = "primary", minutes: Int? = 300, scope: String? = nil, used: Double, resets: TimeInterval = 3600, active: Bool = true) -> LimitWindow {
        LimitWindow(id: id, minutes: minutes, scope: scope, usedPercent: used, resetsAt: Self.now.addingTimeInterval(resets), active: active)
    }

    private func measured(_ cli: LimitsCLI, at: TimeInterval, _ windows: [LimitWindow]) -> CLILimits {
        CLILimits(cli: cli, state: .measured(at: Self.now.addingTimeInterval(at), windows: windows))
    }

    @Test("share left is the complement of used, never below 0, and the tone tints at 20% and 5% left")
    func shareAndTone() {
        #expect(LimitsWording.shareLeft(window(used: 23)) == 77)
        #expect(LimitsWording.shareLeft(window(used: 130)) == 0)
        #expect(LimitsWording.tone(window(used: 79.9)) == .normal)
        #expect(LimitsWording.tone(window(used: 80)) == .low)
        #expect(LimitsWording.tone(window(used: 94.9)) == .low)
        #expect(LimitsWording.tone(window(used: 95)) == .out)
    }

    @Test("a plan reads capitalised in its tag")
    func planName() {
        #expect(LimitsWording.planName("pro") == "Pro")
        #expect(LimitsWording.planName("plus") == "Plus")
        #expect(LimitsWording.planName("") == "")
    }

    @Test("window names: known lengths, a scope, whole hours or days, and the record's own name")
    func names() {
        #expect(LimitsWording.name(window(minutes: 300, used: 0, resets: 1)) == "5-hour")
        #expect(LimitsWording.name(window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", used: 0, resets: 1)) == "Weekly · Fable")
        #expect(LimitsWording.name(window(minutes: 1440, used: 0, resets: 1)) == "1-day")
        #expect(LimitsWording.name(window(minutes: 120, used: 0, resets: 1)) == "2-hour")
        #expect(LimitsWording.name(window("monthly_cap", minutes: nil, used: 0, resets: 1)) == "Monthly cap")
    }

    @Test("a list line names the CLI and the time to the reset, or that the reset has passed")
    func entryLine() {
        let soon = window(used: 23, resets: 3 * Self.hour + 12 * 60)
        #expect(LimitsWording.entryLine(soon, cli: .codex, now: Self.now) == "Codex · resets in 3 h 12 min")
        let week = window(minutes: 10080, used: 8, resets: 2 * 86_400 + 22 * Self.hour)
        #expect(LimitsWording.entryLine(week, cli: .claude, now: Self.now) == "Claude Code · resets in 2 d 22 h")
        let passed = window(used: 88, resets: -26 * 60)
        #expect(LimitsWording.entryLine(passed, cli: .codex, now: Self.now) == "Codex · reset passed")
    }

    @Test("the first fact counts down to the reset, then says how long ago it passed")
    func resetFact() {
        let soon = window(used: 23, resets: 3 * Self.hour + 12 * 60)
        #expect(LimitsWording.resetFact(soon, now: Self.now).label == "Resets in")
        #expect(LimitsWording.resetFact(soon, now: Self.now).value == "3 h 12 min")
        let passed = window(used: 88, resets: -26 * 60)
        #expect(LimitsWording.resetFact(passed, now: Self.now).label == "Reset was")
        #expect(LimitsWording.resetFact(passed, now: Self.now).value == "26 min ago")
    }

    @Test("the tightest window is the current, active one with the least left; a passed reset never leads")
    func tightest() {
        let five = window("primary", used: 23, resets: 3 * Self.hour)
        let week = window("secondary", minutes: 10080, used: 61, resets: 6 * 86_400)
        #expect(LimitsWording.tightest([five, week], now: Self.now)?.id == "secondary")
        let passed = window("primary", used: 88, resets: -60)
        let current = window("secondary", minutes: 10080, used: 96, resets: 86_400)
        #expect(LimitsWording.tightest([passed, current], now: Self.now)?.id == "secondary")
        #expect(LimitsWording.tightest([passed], now: Self.now) == nil)
        let idle = window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", used: 99, resets: 86_400, active: false)
        #expect(LimitsWording.tightest([idle], now: Self.now) == nil)
        #expect(LimitsWording.visible([five, idle], showInactive: false).map(\.id) == ["primary"])
        #expect(LimitsWording.visible([five, idle], showInactive: true).count == 2)
    }

    @Test("the page lists every shown window CLI by CLI, and one entry for a CLI without a window to show")
    func pageEntries() {
        let claude = measured(.claude, at: -2 * 86_400, [
            window("weekly_all", minutes: 10080, used: 8, resets: 2 * 86_400),
            window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", used: 0, resets: 2 * 86_400, active: false),
        ])
        let codex = measured(.codex, at: -240, [window("primary", used: 23, resets: 3 * Self.hour), window("secondary", minutes: 10080, used: 61, resets: 6 * 86_400)])
        let gemini = CLILimits(cli: .gemini, state: .notMeasurable)
        let results = [claude, codex, gemini]
        let entries = LimitsWording.entries(results, showInactive: false)
        #expect(entries.map(\.id) == ["claude:weekly_all", "codex:primary", "codex:secondary", "gemini:state"])
        #expect(LimitsWording.entries(results, showInactive: true).count == 5)
        // Only inactive windows and none shown: the CLI is one entry, which says no window applies.
        let idle = measured(.claude, at: 0, [window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", used: 0, resets: 86_400, active: false)])
        #expect(LimitsWording.entries([idle], showInactive: false).map(\.id) == ["claude:state"])
        #expect(LimitsWording.entryNote(idle).title == "No current window")
        #expect(LimitsWording.entryNote(gemini).title == "Not measurable")
    }

    @Test("the page first selects the window with the least left across CLIs, never a passed one, else the first entry")
    func firstSelection() {
        let claude = measured(.claude, at: -60, [window("weekly_all", minutes: 10080, used: 8, resets: 86_400)])
        let codex = measured(.codex, at: -60, [window("primary", used: 23, resets: 3 * Self.hour), window("secondary", minutes: 10080, used: 61, resets: 86_400)])
        var results = [claude, codex, CLILimits(cli: .gemini, state: .notMeasurable)]
        var entries = LimitsWording.entries(results, showInactive: false)
        #expect(LimitsWording.firstSelection(results, entries: entries, now: Self.now) == "codex:secondary")
        let passed = measured(.codex, at: -5 * Self.hour, [window("primary", used: 99, resets: -60)])
        results = [CLILimits(cli: .claude, state: .notRecorded), passed]
        entries = LimitsWording.entries(results, showInactive: false)
        #expect(LimitsWording.firstSelection(results, entries: entries, now: Self.now) == "claude:state")
    }

    @Test("the facts: time to the reset until it passes, and the reset's clock")
    func facts() {
        let soon = window(used: 23, resets: 3 * Self.hour + 12 * 60)
        #expect(LimitsWording.resetsIn(soon, now: Self.now) == "3 h 12 min")
        #expect(LimitsWording.resetsAt(soon, now: Self.now, calendar: Self.calendar) == "21:12")
        let passed = window(used: 88, resets: -26 * 60)
        #expect(LimitsWording.resetsIn(passed, now: Self.now) == nil)
        #expect(LimitsWording.resetsAt(passed, now: Self.now, calendar: Self.calendar) == "17:34")
    }

    @Test("a reading is stale after six hours, and its age reads in minutes, hours, then days")
    func readingAge() {
        #expect(!LimitsWording.isStale(at: Self.now.addingTimeInterval(-6 * Self.hour), now: Self.now))
        #expect(LimitsWording.isStale(at: Self.now.addingTimeInterval(-6 * Self.hour - 1), now: Self.now))
        #expect(LimitsWording.readAge(at: Self.now.addingTimeInterval(-4 * 60), now: Self.now) == "4 min ago")
        #expect(LimitsWording.readAge(at: Self.now.addingTimeInterval(-5 * Self.hour), now: Self.now) == "5 h ago")
        #expect(LimitsWording.readAge(at: Self.now.addingTimeInterval(-2 * 86_400 - 2 * Self.hour), now: Self.now) == "2 days ago")
    }

    @Test("sidebar summary: the lead window's share, unknown after every reset, and the short state words")
    func sidebarSummary() {
        let codex = measured(.codex, at: -240, [window("primary", used: 23, resets: 3 * Self.hour), window("secondary", minutes: 10080, used: 61, resets: 6 * 86_400)])
        #expect(LimitsWording.summary(codex, now: Self.now) == .share(left: 39, tone: .normal, stale: false))
        let old = measured(.claude, at: -2 * 86_400, [window("weekly_all", minutes: 10080, used: 96, resets: 86_400)])
        #expect(LimitsWording.summary(old, now: Self.now) == .share(left: 4, tone: .out, stale: true))
        let passed = measured(.codex, at: -5 * Self.hour, [window(used: 88, resets: -26 * 60)])
        #expect(LimitsWording.summary(passed, now: Self.now) == .unknown)
        #expect(LimitsWording.summary(CLILimits(cli: .claude, state: .notRecorded), now: Self.now) == .state("no reading"))
        #expect(LimitsWording.summary(CLILimits(cli: .gemini, state: .notInstalled), now: Self.now) == .state("not installed"))
        #expect(LimitsWording.summary(CLILimits(cli: .gemini, state: .notMeasurable), now: Self.now) == .state("not measurable"))
        #expect(LimitsWording.summary(CLILimits(cli: .codex, state: .unreadable), now: Self.now) == .state("unreadable"))
    }

    @Test("the detail's state notes name the cause, and only Claude Code is pointed at /usage")
    func stateNotes() {
        #expect(LimitsWording.stateNote(CLILimits(cli: .gemini, state: .notMeasurable))?.body == "Gemini CLI keeps no usage limit on disk, and Reins does not go online for it.")
        #expect(LimitsWording.stateNote(CLILimits(cli: .claude, state: .notRecorded))?.body.contains("/usage") == true)
        #expect(LimitsWording.stateNote(CLILimits(cli: .codex, state: .notRecorded))?.body == "No Codex turn has logged limits yet.")
        #expect(LimitsWording.stateNote(CLILimits(cli: .gemini, state: .notInstalled))?.body == "No Gemini CLI folder on this Mac.")
        #expect(LimitsWording.stateNote(measured(.codex, at: 0, []))  == nil)
        #expect(LimitsWording.source(.gemini) == nil)
        let captured = CLILimits(cli: .claude, state: .notRecorded, source: .claudeStatusline)
        #expect(LimitsWording.source(captured)?.title == "From Claude Code's status line")
        #expect(LimitsWording.source(.claude)?.body.contains("fallback") == true)
    }
}
