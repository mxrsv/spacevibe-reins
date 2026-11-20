import Foundation
import Testing
@testable import SpaceVibe

/// The reset countdown (spec `docs/specs/2026-11-19-limit-reset-countdown.md`): which windows count and when (LC-R1), the
/// clock text (LC-R2), the Next resets rows that carry it (LC-R3) and the saved weekly lead (LC-R4).
@Suite("Limits countdown", .fixtureCLIs)
struct LimitsCountdownTests {
    private static let now = Date(timeIntervalSince1970: 1_793_703_600)
    private static let minute = 60.0, hour = 3600.0

    private func window(_ id: String, minutes: Int?, scope: String? = nil, resets: TimeInterval, active: Bool = true) -> CoreLimitWindow {
        CoreLimitWindow(id: id, minutes: minutes, scope: scope, usedPercent: 40, resetsAt: Self.now.addingTimeInterval(resets).timeIntervalSince1970,
                        active: active, current: resets > 0)
    }

    /// Whether `window` of `cli` counts at `now` under `weekly`.
    private func counts(_ window: CoreLimitWindow, cli: CLIID = .claude, weekly: WeeklyCountdownLead = .standard) -> Bool {
        let lead = LimitsCountdown.lead(window, cli: cli, weekly: weekly)
        return LimitsCountdown.remaining(until: window.resetsAtDate, lead: lead, now: Self.now) != nil
    }

    @Test("a 5-hour window counts its last hour, the edge included, whatever the weekly lead")
    func fiveHour() {
        #expect(!counts(window("five_hour", minutes: 300, resets: 61 * Self.minute)))
        #expect(counts(window("five_hour", minutes: 300, resets: 60 * Self.minute)))
        #expect(counts(window("five_hour", minutes: 300, resets: 59 * Self.minute)))
        #expect(counts(window("session", minutes: 300, resets: 10 * Self.minute)))
        #expect(counts(window("primary", minutes: 300, resets: 10 * Self.minute), cli: .codex))
        #expect(!counts(window("five_hour", minutes: 300, resets: 2 * Self.hour), weekly: .hours24))
    }

    @Test("a weekly window counts within the chosen lead", arguments: WeeklyCountdownLead.allCases)
    func weekly(lead: WeeklyCountdownLead) {
        #expect(counts(window("weekly_all", minutes: 10080, resets: lead.seconds), weekly: lead))
        #expect(!counts(window("weekly_all", minutes: 10080, resets: lead.seconds + 1), weekly: lead))
        #expect(counts(window("secondary", minutes: 10080, resets: lead.seconds - Self.minute), cli: .codex, weekly: lead))
    }

    @Test("inactive, scoped, monthly, passed and Gemini CLI windows never count")
    func never() {
        #expect(!counts(window("weekly_all", minutes: 10080, resets: 10 * Self.minute, active: false)))
        #expect(!counts(window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", resets: 10 * Self.minute)))
        #expect(!counts(window("monthly_all", minutes: nil, resets: 10 * Self.minute)))
        #expect(!counts(window("five_hour", minutes: 300, resets: -1)))
        #expect(!counts(window("five_hour", minutes: 300, resets: 0)))
        #expect(!counts(window("five_hour", minutes: 300, resets: 10 * Self.minute), cli: .gemini))
    }

    @Test("the clock reads H:MM:SS from an hour up and MM:SS below, rounded up")
    func clock() {
        #expect(LimitsCountdown.clock(23 * Self.hour + 12 * Self.minute + 5) == "23:12:05")
        #expect(LimitsCountdown.clock(Self.hour) == "1:00:00")
        #expect(LimitsCountdown.clock(Self.hour - 1) == "59:59")
        #expect(LimitsCountdown.clock(1) == "00:01")
        #expect(LimitsCountdown.clock(0.4) == "00:01")
        #expect(LimitsCountdown.spoken(42 * Self.minute + 17) == "42 min 17 s left")
    }

    @Test("Next resets rows carry the lead of the windows that can count, under the chosen weekly lead")
    func resetRows() {
        let entries = [
            CoreLimitsEntry(cli: .claude, state: .measured, plan: nil, source: nil, at: Self.now.timeIntervalSince1970, windows: [
                window("five_hour", minutes: 300, resets: 42 * Self.minute),
                window("weekly_all", minutes: 10080, resets: 23 * Self.hour),
                window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", resets: 23 * Self.hour),
            ]),
        ]
        let answer = LimitsAnswer(.read(entries), showUnused: false, now: Self.now, weeklyLead: .hours24)
        let leads = Dictionary(uniqueKeysWithValues: (answer.resets ?? []).map { ($0.id, $0.countdownLead) })
        #expect(leads["claude:five_hour"] == LimitsCountdown.fiveHourLead)
        #expect(leads["claude:weekly_all"] == WeeklyCountdownLead.hours24.seconds)
        #expect(leads["claude:weekly_scoped:Fable"] == .some(nil))
        let weekly = answer.resets?.first { $0.id == "claude:weekly_all" }
        #expect(weekly.flatMap { LimitsCountdown.remaining(until: $0.resetsAt, lead: $0.countdownLead, now: Self.now) } == 23 * Self.hour)
    }

    @MainActor
    @Test("the weekly lead is 1 h when nothing is saved, and a choice is remembered")
    func remembersLead() {
        let suite = "spacevibe-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LimitsCountdownPreferences(defaults: defaults).weeklyLead == .hours1)
        LimitsCountdownPreferences(defaults: defaults).weeklyLead = .hours24
        #expect(LimitsCountdownPreferences(defaults: defaults).weeklyLead == .hours24)
        defaults.set(7, forKey: LimitsCountdownPreferences.weeklyLeadKey)
        #expect(LimitsCountdownPreferences(defaults: defaults).weeklyLead == .hours1)
    }

    @MainActor
    @Test("with no defaults the choice lives in memory and starts where it is told")
    func inMemory() {
        let shot = LimitsCountdownPreferences(defaults: nil, weeklyLead: .hours24)
        #expect(shot.weeklyLead == .hours24)
        shot.weeklyLead = .hours5
        #expect(shot.weeklyLead == .hours5)
    }

    @Test("a ticking clock starts on the whole second at or before now")
    func wholeSecond() {
        #expect(LimitsCountdown.wholeSecond(before: Date(timeIntervalSince1970: 100.7)) == Date(timeIntervalSince1970: 100))
        #expect(LimitsCountdown.wholeSecond(before: Date(timeIntervalSince1970: 100)) == Date(timeIntervalSince1970: 100))
    }
}
