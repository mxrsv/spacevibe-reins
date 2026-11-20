import Foundation
import Testing
@testable import SpaceVibe

/// The glance widget's reset countdown (spec `docs/specs/2026-11-19-limit-reset-countdown.md`, LC-R5 to LC-R8): which window
/// the pill shows, when the widget draws again, where the pill sits, the Limits group's rows, the 60 s read and its stop, and
/// the click route to Limits. No window is opened.
@Suite("Glance countdown", .fixtureCLIs)
@MainActor
struct GlanceCountdownTests {
    private static let now = Date(timeIntervalSince1970: 1_793_703_600)
    private static let minute = 60.0, hour = 3600.0

    private func window(_ id: String, _ minutes: Int?, scope: String? = nil, used: Double = 40, resets: TimeInterval,
                        active: Bool = true) -> CoreLimitWindow {
        CoreLimitWindow(id: id, minutes: minutes, scope: scope, usedPercent: used, resetsAt: Self.now.addingTimeInterval(resets).timeIntervalSince1970,
                        active: active, current: resets > 0)
    }

    private func entry(_ cli: CLIID, _ windows: [CoreLimitWindow]) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: .measured, plan: nil, source: nil, at: Self.now.timeIntervalSince1970 - 60, windows: windows)
    }

    private func counting(_ results: [CoreLimitsEntry], lead: WeeklyCountdownLead = .standard, at now: Date = now) -> [GlanceCountdownWindow] {
        GlanceCountdown.counting(results, now: now, weeklyLead: lead)
    }

    // MARK: Which window

    @Test("the spec's success case: a 5-hour window at 59 min and a weekly one at 23 h with the 24 h lead both count, the 5-hour one first")
    func successCase() {
        let results = [entry(.claude, [window("five_hour", 300, resets: 59 * Self.minute)]),
                       entry(.codex, [window("secondary", 10080, resets: 23 * Self.hour)])]
        let shown = counting(results, lead: .hours24)
        #expect(shown.map(\.id) == ["claude:five_hour", "codex:secondary"])
        #expect(shown.first?.kind == .fiveHour)
        #expect(counting(results).map(\.id) == ["claude:five_hour"], "at the default 1 h lead the weekly window waits")
    }

    @Test("the first to reset wins, whatever the CLI or window order; a tie keeps the core's order")
    func firstToReset() {
        let results = [entry(.claude, [window("seven_day", 10080, resets: 30 * Self.minute), window("five_hour", 300, resets: 50 * Self.minute)]),
                       entry(.codex, [window("primary", 300, resets: 10 * Self.minute)])]
        #expect(counting(results).map(\.id) == ["codex:primary", "claude:seven_day", "claude:five_hour"])
        let tie = [entry(.codex, [window("primary", 300, resets: 10 * Self.minute)]),
                   entry(.claude, [window("five_hour", 300, resets: 10 * Self.minute)])]
        #expect(counting(tie).map(\.id) == ["codex:primary", "claude:five_hour"])
    }

    @Test("no pill outside every lead, nor for inactive, scoped, passed, monthly or Gemini CLI windows")
    func noPill() {
        let outside = [entry(.claude, [window("five_hour", 300, resets: 61 * Self.minute), window("seven_day", 10080, resets: 2 * Self.hour)]),
                       entry(.codex, [window("secondary", 10080, resets: 23 * Self.hour)])]
        #expect(counting(outside).isEmpty)
        let never = [entry(.claude, [window("five_hour", 300, resets: 10 * Self.minute, active: false),
                                     window("seven_day_opus", 10080, scope: "Opus", resets: 10 * Self.minute),
                                     window("five_hour", 300, resets: -1 * Self.minute),
                                     window("monthly", 43_200, resets: 10 * Self.minute)]),
                     entry(.gemini, [window("daily", 300, resets: 10 * Self.minute)])]
        #expect(counting(never, lead: .hours24).isEmpty)
        let notMeasured = CoreLimitsEntry(cli: .codex, state: .notRecorded, plan: nil, source: nil, at: nil, windows: [])
        #expect(counting([notMeasured]).isEmpty)
    }

    @Test("the weekly lead from Settings decides when a weekly window starts, and a change shows at once", arguments: WeeklyCountdownLead.allCases)
    func weeklyLead(lead: WeeklyCountdownLead) {
        // An absolute path keeps the suite's plist in the temporary folder, out of `~/Library/Preferences`.
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-tests-\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LimitsCountdownPreferences(defaults: defaults)
        #expect(preferences.weeklyLead == .hours1)
        let results = [entry(.codex, [window("secondary", 10080, resets: lead.seconds - Self.minute)])]
        preferences.weeklyLead = lead
        #expect(counting(results, lead: preferences.weeklyLead).count == 1)
        let shorter = WeeklyCountdownLead.allCases.filter { $0.seconds < lead.seconds }
        for other in shorter { #expect(counting(results, lead: other).isEmpty, "\(other)") }
    }

    @Test("a window leaves at zero, and the ring drains from 1 to 0 over the lead")
    func leavesAtZero() throws {
        let results = [entry(.claude, [window("five_hour", 300, resets: 30 * Self.minute)])]
        let shown = try #require(counting(results).first)
        #expect(abs(shown.share(at: Self.now) - 0.5) < 0.0001)
        #expect(shown.share(at: Self.now.addingTimeInterval(-30 * Self.minute)) == 1)
        let reset = Self.now.addingTimeInterval(30 * Self.minute)
        #expect(counting(results, at: reset).isEmpty)
        #expect(counting(results, at: reset.addingTimeInterval(-1)).count == 1)
    }

    // MARK: When to draw

    @Test("while a window counts the widget wakes at its next clock change; otherwise when the next window starts; else never")
    func nextWake() throws {
        let counting = [entry(.claude, [window("five_hour", 300, resets: 42 * Self.minute + 17.3)])]
        let wake = try #require(GlanceCountdown.nextWake(counting, now: Self.now, weeklyLead: .standard))
        #expect(abs(wake.timeIntervalSince(Self.now) - (0.3 + GlanceCountdown.wakeSlack)) < 0.0001)
        #expect(LimitsCountdown.clock(42 * Self.minute + 17.3) == "42:18")
        #expect(LimitsCountdown.clock(42 * Self.minute + 17.3 - wake.timeIntervalSince(Self.now)) == "42:17")

        let whole = [entry(.claude, [window("five_hour", 300, resets: 10 * Self.minute)])]
        let next = try #require(GlanceCountdown.nextWake(whole, now: Self.now, weeklyLead: .standard))
        #expect(abs(next.timeIntervalSince(Self.now) - (1 + GlanceCountdown.wakeSlack)) < 0.0001)

        let later = [entry(.claude, [window("five_hour", 300, resets: 3 * Self.hour)]),
                     entry(.codex, [window("secondary", 10080, resets: 30 * Self.hour)])]
        let start = try #require(GlanceCountdown.nextWake(later, now: Self.now, weeklyLead: .hours24))
        #expect(start == Self.now.addingTimeInterval(2 * Self.hour), "the 5-hour window starts first, 1 h before its reset")
        #expect(GlanceCountdown.nextWake([entry(.claude, [window("monthly", 43_200, resets: Self.hour)])], now: Self.now,
                                         weeklyLead: .standard) == nil)
    }

    // MARK: Placement

    @Test("the pill sits toward the screen centre: left of a right corner, right of a left corner or a middle, under an edge middle")
    func pillSide() {
        #expect(GlanceSlot.topRight.pillSide == .leading && GlanceSlot.bottomRight.pillSide == .leading)
        #expect(GlanceSlot.topLeft.pillSide == .trailing && GlanceSlot.bottomLeft.pillSide == .trailing)
        #expect(GlanceSlot.topCenter.pillSide == .trailing && GlanceSlot.bottomCenter.pillSide == .trailing)
        #expect(GlanceSlot.leftMiddle.pillSide == .below && GlanceSlot.rightMiddle.pillSide == .below)
    }

    @Test("the pill's frame is the gap away from the strip, centred across, and never overlaps it", arguments: GlanceSlot.allCases)
    func pillFrame(slot: GlanceSlot) {
        let strip = CGRect(x: 800, y: 40, width: slot.axis == .horizontal ? 120 : 30, height: slot.axis == .horizontal ? 30 : 120)
        let size = slot.axis == .horizontal ? CGSize(width: 84, height: 30) : CGSize(width: 30, height: 80)
        let pill = slot.pillFrame(for: size, beside: strip)
        #expect(pill.size == size && !pill.intersects(strip))
        switch slot.pillSide {
        case .leading:
            #expect(strip.minX - pill.maxX == GlanceLayout.pillGap && pill.midY == strip.midY)
        case .trailing:
            #expect(pill.minX - strip.maxX == GlanceLayout.pillGap && pill.midY == strip.midY)
        case .below:
            #expect(strip.minY - pill.maxY == GlanceLayout.pillGap && pill.midX == strip.midX)
        }
    }

    // MARK: Words

    @Test("Limits rows: the window's name, its clock, and the CLI with the reset's clock time; the pill's short name")
    func rows() throws {
        let calendar = Calendar(identifier: .gregorian)
        let results = [entry(.claude, [window("five_hour", 300, used: 97, resets: 3 * Self.minute + 12)]),
                       entry(.codex, [window("secondary", 10080, used: 85, resets: 23 * Self.hour + 12 * Self.minute + 5)])]
        let shown = GlanceCountdown.counting(results, now: Self.now, weeklyLead: .hours24, calendar: calendar)
        let first = try #require(shown.first), second = try #require(shown.last)
        #expect(first.name == "5-hour" && second.name == "Weekly")
        #expect(GlanceCountdownWording.label(first.kind) == "5h" && GlanceCountdownWording.label(second.kind) == "Week")
        #expect(GlanceCountdownWording.clock(first, now: Self.now) == "03:12")
        #expect(GlanceCountdownWording.clock(second, now: Self.now) == "23:12:05")
        #expect(first.tone == .out && second.tone == .low)
        #expect(first.tone.textTone == .danger && second.tone.barTone == .warn)
        let resetTime = LimitsWording.resetsAt(results[0].windows[0], now: Self.now, calendar: calendar)
        #expect(GlanceCountdownWording.detail(first) == "Claude Code · resets at \(resetTime)")
        #expect(GlanceCountdownWording.spoken(first, now: Self.now) == "Claude Code 5-hour limit, 3 min 12 s left")
    }

    // MARK: Read cadence

    @Test("the widget reads limits every 60 s")
    func cadence() {
        #expect(GlanceLimitsFeed.readInterval == .seconds(60))
        #expect(GlanceLimitsFeed.readInterval == LimitsModel.interval)
    }

    @Test("the read runs while the feed runs and stops when the switch turns it off", .timeLimit(.minutes(1)))
    func readStops() async throws {
        let core = CountingLimitsCore()
        let limits = LimitsModel(env: AppEnvironment(makeCoreClient: { core }))
        let feed = GlanceLimitsFeed(limits: limits, interval: .milliseconds(40))
        #expect(!feed.isRunning && core.reads == 0)
        feed.start()
        feed.start()
        #expect(feed.isRunning)
        let deadline = Date().addingTimeInterval(10)
        while core.reads < 3, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(core.reads >= 3)
        #expect(feed.results.map(\.cli) == [.claude])
        feed.stop()
        #expect(!feed.isRunning)
        try await Task.sleep(for: .milliseconds(80))
        let stopped = core.reads
        try await Task.sleep(for: .milliseconds(300))
        #expect(core.reads == stopped, "no read after stop")
    }

    // MARK: Click

    @Test("a click opens Limits with that window current, over Settings")
    func clickRoute() {
        let shell = ShellModel.forAppTests()
        let limits = LimitsModel(env: AppEnvironment(makeCoreClient: { UnservedCore() }))
        shell.openSettings()
        shell.openLimits(windowID: "codex:secondary", in: limits, openState: OpenStateStore())
        #expect(shell.activeID == TabRegistry.limitsID)
        #expect(!shell.isSettingsOpen)
        #expect(limits.selectedID == "codex:secondary")
    }

    @Test("a click opens the Usage windows card and that CLI's band when the user had closed them")
    func clickOpensClosedBand() {
        let shell = ShellModel.forAppTests()
        let limits = LimitsModel(env: AppEnvironment(makeCoreClient: { UnservedCore() }))
        let store = OpenStateStore()
        let page = LimitsCanvas.page
        store.setOpen(false, page: page, id: LimitsCanvas.windowsCardID)
        store.setOpen(false, page: page, id: LimitsCanvas.bandOpenID(CLIID.codex.rawValue))
        store.setOpen(false, page: page, id: LimitsCanvas.bandOpenID(CLIID.claude.rawValue))
        shell.openLimits(windowID: "codex:secondary", in: limits, openState: store)
        #expect(store.isOpen(page: page, id: LimitsCanvas.windowsCardID, byDefault: false))
        #expect(store.isOpen(page: page, id: LimitsCanvas.bandOpenID(CLIID.codex.rawValue), byDefault: false))
        // Another CLI's band keeps the user's choice.
        #expect(!store.isOpen(page: page, id: LimitsCanvas.bandOpenID(CLIID.claude.rawValue), byDefault: true))
        #expect(limits.selectedID == "codex:secondary")
    }
}

/// Serves `limits.read` only, with one Claude Code reading, and counts the reads.
private final class CountingLimitsCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var _reads = 0

    var reads: Int { lock.withLock { _reads } }

    override func limitsRead() async throws -> CoreLimitsResult {
        lock.withLock { _reads += 1 }
        return CoreLimitsResult(limits: [CoreLimitsEntry(cli: .claude, state: .notRecorded, plan: nil, source: nil, at: nil, windows: [])])
    }
}
