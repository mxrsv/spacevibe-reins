import AppKit
import Foundation
import Testing
@testable import SpaceVibe

/// V5-A18 for Limits: the Answer, the Next resets rows, the Source lines and the bands come from one derivation
/// (`LimitsAnswer`) on the core's DTOs, against a fixed clock. Shares are the share LEFT (V5-R75).
@Suite("Limits answer")
struct LimitsAnswerTests {
    private static let hour = 3600.0
    private static let day = 86_400.0
    /// Tuesday 2026-11-03 18:00 at UTC+7, the clock of `LimitsWordingTests`.
    private static let now = Date(timeIntervalSince1970: 1_793_703_600)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }()

    /// `current` is the core's flag: the reset is after the moment of the reading, which here is `now`.
    private func window(_ id: String, minutes: Int? = 300, scope: String? = nil, used: Double, resets: TimeInterval, active: Bool = true) -> CoreLimitWindow {
        CoreLimitWindow(id: id, minutes: minutes, scope: scope, usedPercent: used, resetsAt: Self.now.addingTimeInterval(resets).timeIntervalSince1970,
                        active: active, current: resets > 0)
    }

    private func measured(_ cli: CoreLimitsCLI, plan: String? = nil, at: TimeInterval = -4 * 60, _ windows: [CoreLimitWindow]) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: .measured, plan: plan, source: nil, at: Self.now.addingTimeInterval(at).timeIntervalSince1970, windows: windows)
    }

    private func entry(_ cli: CoreLimitsCLI, _ state: CoreLimitsState) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: state, plan: nil, source: nil, at: nil, windows: [])
    }

    private func answer(_ entries: [CoreLimitsEntry], showUnused: Bool = false) -> LimitsAnswer {
        LimitsAnswer(.read(entries), showUnused: showUnused, now: Self.now, calendar: Self.calendar)
    }

    private func rows(_ band: LimitsAnswer.Band) -> [LimitsAnswer.WindowRow] {
        if case .windows(let rows) = band.body { return rows }
        return []
    }

    /// The `typical` fixture's shape: Claude Code read 2 days ago (stale), Codex 4 min ago, Gemini CLI not measurable.
    private var typical: [CoreLimitsEntry] {
        [
            measured(.claude, at: -(2 * Self.day + 2 * Self.hour), [
                window("weekly_all", minutes: 10080, used: 8, resets: 2 * Self.day + 22 * Self.hour),
                window("weekly_scoped:Fable", minutes: 10080, scope: "Fable", used: 0, resets: 2 * Self.day + 22 * Self.hour, active: false),
            ]),
            measured(.codex, plan: "pro", [
                window("primary", used: 23, resets: 3 * Self.hour + 12 * 60),
                window("secondary", minutes: 10080, used: 61, resets: 6 * Self.day + 16 * Self.hour),
            ]),
            entry(.gemini, .notMeasurable),
        ]
    }

    @Test("one CLI has room: heavy work goes there until its weekly reset, the tighter CLI and the stale read are named")
    func oneHasRoom() {
        let facts = answer(typical)
        #expect(facts.sentence == "Do heavy work in Claude Code until Fri 16:00.")
        #expect(facts.verdict == LimitsAnswer.Verdict(glyph: .used, title: "Codex is the tighter one", text: "Weekly has 39% left.",
                                                      small: "Claude Code was read 2 days ago."))
    }

    @Test("the share shown is the share left, 100 minus used, never below 0; a window past its reset is unknown, not 0")
    func shareDirection() {
        let facts = answer([measured(.codex, [
            window("primary", used: 61, resets: Self.hour),
            window("secondary", minutes: 10080, used: 130, resets: Self.day),
            window("review", minutes: nil, used: 88, resets: -26 * 60),
        ])])
        let shown = rows(facts.bands[0])
        #expect(shown.map(\.left) == [39, 0, nil])
        #expect(shown.map(\.tone) == [.normal, .out, .normal])
        #expect(shown[2].warning?.sentence == "The reset time passed and no reading came after it. It is not 0%.")
        #expect(shown[2].warning?.mark.kind == .clock)
        #expect(shown[0].spoken == "Codex 5-hour, 39% left")
        #expect(shown[2].spoken == "Codex Review, not known")
    }

    @Test("both CLIs low: hold heavy work until the first of them has no low window left")
    func bothLow() {
        let facts = answer([
            measured(.claude, [window("five_hour", used: 86, resets: 2 * Self.hour), window("seven_day", minutes: 10080, used: 70, resets: 3 * Self.day)]),
            measured(.codex, [window("primary", used: 97, resets: Self.hour), window("secondary", minutes: 10080, used: 50, resets: 5 * Self.day)]),
            entry(.gemini, .notMeasurable),
        ])
        #expect(facts.sentence == "Hold heavy work until 19:00.")
        #expect(facts.verdict == LimitsAnswer.Verdict(glyph: .used, title: "Both CLIs are low", text: "The best window left has 14%."))
        #expect(facts.bands[0].mark == LimitsAnswer.Mark(kind: .warn, label: "A window is low"))
        #expect(facts.bands[1].mark == LimitsAnswer.Mark(kind: .danger, label: "A window is low"))
        let claudeLow = rows(facts.bands[0])[0].warning
        #expect(claudeLow == LimitsAnswer.Warning(mark: LimitsAnswer.Mark(kind: .warn, label: "5-hour: 14% left"),
                                                  sentence: "14% left, resets 20:00.", action: .copyUsage))
        // `/usage` is Claude Code's command, so a Codex window offers no copy.
        #expect(rows(facts.bands[1])[0].warning?.action == nil)
        #expect(rows(facts.bands[1])[0].warning?.mark.kind == .danger)
    }

    @Test("one CLI low and the other with no reading: the verdict names only the CLI that was read (the edge fixture)")
    func oneLowOtherUnread() {
        let facts = answer([
            entry(.claude, .notRecorded),
            measured(.codex, plan: "plus", at: -5 * Self.hour, [
                window("primary", used: 88, resets: -26 * 60),
                window("secondary", minutes: 10080, used: 96, resets: Self.day + 3 * Self.hour),
            ]),
            entry(.gemini, .notInstalled),
        ])
        #expect(facts.sentence == "Hold heavy work until Wed 21:00.")
        #expect(facts.verdict == LimitsAnswer.Verdict(glyph: .used, title: "Codex is low", text: "Its tightest window has 4% left."))
        #expect(facts.bands[0].body == .note("No reading yet.", .readNow))
        #expect(facts.bands[2].body == .note("Not installed. SpaceVibe found no Gemini CLI on this Mac.", nil))
        #expect(facts.bands[1].staleAge == nil, "5 hours is not stale")
        #expect(facts.resets?.map(\.title) == ["Codex Weekly"])
        #expect(facts.sources.map { "\($0.name) \($0.state)" } == ["Claude Code no reading", "Codex Plus read 5 h ago", "Gemini CLI not installed"])
    }

    @Test("no reading anywhere: the Answer says so and offers nothing to compare")
    func noReading() {
        let facts = answer([entry(.claude, .notRecorded), entry(.codex, .notRecorded), entry(.gemini, .notMeasurable)])
        #expect(facts.sentence == "No reading yet.")
        #expect(facts.verdict?.glyph == .nm)
        #expect(facts.verdict?.title == "Nothing to compare")
        #expect(facts.resets == [])
    }

    @Test("a stale reading is named in the Answer, on its band and on every one of its windows, from six hours on")
    func staleNamed() {
        let facts = answer([
            measured(.claude, at: -6 * Self.hour, [window("seven_day", minutes: 10080, used: 30, resets: 3 * Self.day)]),
            measured(.codex, [window("secondary", minutes: 10080, used: 50, resets: 4 * Self.day)]),
            entry(.gemini, .notMeasurable),
        ])
        #expect(facts.verdict?.small == "Claude Code was read 6 h ago.")
        #expect(facts.bands[0].staleAge == "read 6 h ago")
        #expect(rows(facts.bands[0])[0].warning == LimitsAnswer.Warning(
            mark: LimitsAnswer.Mark(kind: .clock, label: "Weekly: read 6 h ago"), sentence: "Read 6 h ago. The real number may be lower.", action: .refresh))
        #expect(facts.bands[1].staleAge == nil)
    }

    @Test("Gemini CLI is never measured: its band says so, its source line says no log, and it never enters the Answer")
    func geminiNotMeasurable() {
        let facts = answer(typical)
        #expect(facts.bands[2].body == .note("Not measurable. Gemini CLI exposes no usage numbers.", nil))
        #expect(facts.bands[2].count == nil)
        #expect(facts.sources[2] == LimitsAnswer.SourceLine(cli: .gemini, name: "Gemini CLI", state: "no log"))
        #expect(facts.sentence?.contains("Gemini") == false)
    }

    @Test("not installed and unreadable: a note per band, unreadable with Retry and the warn glyph")
    func notInstalledAndUnreadable() {
        let facts = answer([entry(.claude, .unreadable), entry(.codex, .notInstalled), entry(.gemini, .notMeasurable)])
        #expect(facts.bands[0].body == .note("Can't read usage from local files.", .retry))
        #expect(facts.bands[0].mark == LimitsAnswer.Mark(kind: .warn, label: "Unreadable"))
        #expect(facts.bands[1].body == .note("Not installed. SpaceVibe found no Codex on this Mac.", nil))
        #expect(facts.sources.map(\.state) == ["no reading", "not installed", "no log"])
        #expect(facts.sentence == "No reading yet.")
    }

    @Test("loading, then a failed first read: skeletons first, then a Retry on every band; a failure after a reading keeps it")
    func loadingAndFailed() {
        #expect(LimitsAnswer.Read(results: [], failure: nil) == .loading)
        #expect(LimitsAnswer.Read(results: [], failure: "no roots") == .failed)
        #expect(LimitsAnswer.Read(results: typical, failure: "no roots") == .read(typical))

        let loading = LimitsAnswer(.loading, showUnused: false, now: Self.now, calendar: Self.calendar)
        #expect(loading.sentence == nil && loading.verdict == nil && loading.resets == nil)
        #expect(loading.bands.map(\.body) == [.loading, .loading, .loading])
        #expect(loading.sources.map(\.state) == ["reading", "reading", "reading"])

        let failed = LimitsAnswer(.failed, showUnused: false, now: Self.now, calendar: Self.calendar)
        #expect(failed.sentence == "No reading yet.")
        #expect(failed.verdict?.title == "The read did not finish")
        #expect(failed.bands.allSatisfy { $0.body == .note("The last read did not finish.", .retry) && $0.mark?.kind == .danger })
    }

    @Test("Next resets: current windows only, the soonest first, by time and CLI window, never a share; unused ones only when shown")
    func nextResets() {
        let facts = answer(typical)
        #expect(facts.resets?.map { "\($0.time) \($0.title)" } == ["21:12 Codex 5-hour", "Fri 16:00 Claude Code Weekly", "Nov 10 Codex Weekly"])
        let all = answer(typical, showUnused: true)
        #expect(all.resets?.map(\.title).contains("Claude Code Weekly · Fable") == true)
    }

    @Test("Show unused lists the windows the CLI marks as not applying now, and counts them on the band")
    func unusedWindows() {
        #expect(answer(typical).bands[0].count == 1)
        #expect(answer(typical, showUnused: true).bands[0].count == 2)
        #expect(answer(typical, showUnused: true).bands[0].staleAge == "read 2 days ago")
        // Not in use never decides the Answer.
        #expect(answer(typical, showUnused: true).sentence == answer(typical).sentence)
    }

    @Test("a scoped window does not decide where heavy work goes, but it can be the tighter one named")
    func scopedWindows() {
        let claude = measured(.claude, [
            window("seven_day", minutes: 10080, used: 40, resets: 3 * Self.day),
            window("seven_day_opus", minutes: 10080, scope: "Opus", used: 95, resets: 3 * Self.day),
        ])
        let codex = measured(.codex, [window("secondary", minutes: 10080, used: 20, resets: 2 * Self.day)])
        let both = answer([claude, codex, entry(.gemini, .notMeasurable)])
        #expect(both.sentence == "Do heavy work in Codex until Thu 18:00.")
        #expect(both.verdict?.title == "Claude Code is the tighter one")
        #expect(both.verdict?.text == "Weekly · Opus has 5% left.")
        let alone = answer([claude, entry(.codex, .notRecorded), entry(.gemini, .notMeasurable)])
        #expect(alone.sentence == "Do heavy work in Claude Code until Fri 18:00.")
        #expect(alone.verdict == LimitsAnswer.Verdict(glyph: .used, title: "Claude Code has room", text: "Its tightest window has 60% left."))
        #expect(alone.bands[0].mark?.kind == .danger, "the band still marks the scoped window that is almost out")
    }

    @Test("j and k move the current row and stop at the ends; a row no longer listed gives way to the first")
    func currentRow() {
        let rows = ["claude:a", "codex:b", "codex:c"]
        #expect(LimitsCurrentRow.resolve(nil, in: rows) == "claude:a")
        #expect(LimitsCurrentRow.step(nil, by: 1, in: rows) == "codex:b")
        #expect(LimitsCurrentRow.step("codex:c", by: 1, in: rows) == "codex:c")
        #expect(LimitsCurrentRow.step("claude:a", by: -1, in: rows) == "claude:a")
        #expect(LimitsCurrentRow.resolve("gone", in: rows) == "claude:a")
        #expect(LimitsCurrentRow.step(nil, by: 1, in: []) == nil)
    }

    @Test("Copy /usage puts /usage on the pasteboard and nothing else")
    @MainActor
    func copyUsage() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.spacevibe.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("before", forType: .string)
        LimitsClipboard.copyUsageCommand(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "/usage")
        #expect(pasteboard.pasteboardItems?.count == 1)
    }
}
