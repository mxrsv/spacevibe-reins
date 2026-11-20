import AppKit
import Foundation
import SwiftUI

/// `SPACEVIBE_SHOT_SCREEN=glance`: the session glance widget's two views (spec `docs/specs/2026-11-19-session-glance-widget.md`)
/// drawn headless from in-memory reports with synthetic titles (the mock's data sets), in dark and light. Nothing is read: no
/// core, no home, no defaults. Each view sits on the shot stage (`ShotRenderer.writeFloating`); the panel's drop shadow and the
/// hover fill of a row are not drawn here, since the window draws the one and only a pointer makes the other.
///
/// - `glance-strip-states`: one entry in each state (waiting, working, done, unmeasurable, idle), in a row.
/// - `glance-strip-many`: twelve sessions, six shown and `+6`.
/// - `glance-strip-vertical`: the right edge middle's column, every state.
/// - `glance-strip-empty`: no session, the faint mark.
/// - `glance-strip-failed`, `glance-list-failed`: the feed has failed after a read: the strip's entries fade and the list
///   puts the fixed sentence above the last rows; no ring turns.
/// - `glance-list`, `glance-list-long` (long Greek and CJK titles, very long tool text), `glance-list-many` (twelve rows at the
///   list's height cap, scrolled to the top), `glance-list-empty` ("No session running").
///
/// The reset countdown (spec `docs/specs/2026-11-19-limit-reset-countdown.md`, LC-R5, LC-R6), at a fixed clock, with the strip
/// and the pill laid out as `GlanceSlot.pillSide` places them:
/// - `glance-pill-sessions`: bottom right, the pill left of the strip, a 5-hour window at 42:17.
/// - `glance-pill-empty`: the pill beside the faint mark.
/// - `glance-pill-vertical`: the right edge middle, the pill under the column with its clock stacked (a weekly window, low,
///   at a 24 h lead).
/// - `glance-pill-two`: top left, two counting windows; the pill shows the 5-hour one, which resets first.
/// - `glance-pill-none`: no window inside its lead (a 5-hour window at 61 min, a weekly one at 23 h with the 1 h lead): no pill.
/// - `glance-hover-pill`: the hover list above the strip and the pill (bottom right), ending with the Limits group.
/// - `glance-list-limits-many`: twelve sessions at the height cap, scrolled to the top, the Limits group pinned under them.
/// - `glance-list-limits-empty`: no session and a counting window: the sentence above the group.
@MainActor
enum GlanceShots {
    static func run(into directory: URL) throws {
        let all = entries(GlanceShotData.all)
        let many = entries(GlanceShotData.many)
        try ShotHarness.check(Set(all.all.map(\.state)) == Set(GlanceState.allCases), "the state set holds every glance state")
        try ShotHarness.check(GlanceStrip(entries: many, slot: .bottomRight).items.last == .overflow(6), "twelve sessions show six and +6")
        try ShotHarness.check(GlanceStrip(entries: all, slot: .rightMiddle).axis == .vertical, "the right edge middle stacks the strip")

        let limits = GlanceLimitsShotData.self
        let fiveHour = limits.counting(limits.fiveHour)
        let week = limits.counting(limits.week, lead: .hours24)
        let both = limits.counting(limits.both, lead: .hours24)
        try ShotHarness.check(fiveHour.map(\.kind) == [.fiveHour], "a 5-hour window at 42 min counts")
        try ShotHarness.check(week.map(\.kind) == [.weekly] && limits.counting(limits.week).isEmpty,
                              "a weekly window at 23 h counts with the 24 h lead only")
        try ShotHarness.check(both.map(\.kind) == [.fiveHour, .weekly], "with two windows counting, the first to reset leads")
        try ShotHarness.check(limits.counting(limits.outside).isEmpty, "no window counts outside every lead")

        for choice in [AppearanceChoice.dark, .light] {
            func write(_ view: some View, _ name: String) throws {
                try ShotRenderer.writeFloating(view, name: name, choice: choice, to: directory)
            }
            try write(strip(all, slot: .bottomRight), "glance-strip-states")
            try write(strip(many, slot: .topRight), "glance-strip-many")
            try write(strip(all, slot: .rightMiddle), "glance-strip-vertical")
            try write(strip(.empty, slot: .bottomRight), "glance-strip-empty")
            try write(list(all), "glance-list")
            try write(list(entries(GlanceShotData.long)), "glance-list-long")
            try write(scrolledList(many), "glance-list-many")
            try write(list(.empty), "glance-list-empty")
            try write(strip(all, slot: .bottomRight, failure: GlanceFeed.unreadable), "glance-strip-failed")
            try write(list(entries(GlanceShotData.normal), failure: GlanceFeed.unreadable), "glance-list-failed")

            try write(group(all, slot: .bottomRight, pill: fiveHour.first), "glance-pill-sessions")
            try write(group(.empty, slot: .bottomRight, pill: fiveHour.first), "glance-pill-empty")
            try write(group(all, slot: .rightMiddle, pill: week.first), "glance-pill-vertical")
            try write(group(all, slot: .topLeft, pill: both.first), "glance-pill-two")
            try write(group(all, slot: .bottomRight, pill: nil), "glance-pill-none")
            try write(VStack(alignment: .trailing, spacing: GlanceLayout.listGap) {
                list(entries(GlanceShotData.normal), limits: both)
                group(entries(GlanceShotData.normal), slot: .bottomRight, pill: both.first)
            }, "glance-hover-pill")
            try write(scrolledList(many, limits: both), "glance-list-limits-many")
            try write(list(.empty, limits: fiveHour), "glance-list-limits-empty")
        }
    }

    /// The strip and, when a window counts, the pill on the side its slot gives it (`GlanceSlot.pillFrame`), centred across.
    @ViewBuilder
    private static func group(_ entries: GlanceEntries, slot: GlanceSlot, pill window: GlanceCountdownWindow?) -> some View {
        let bar = strip(entries, slot: slot)
        let pill = window.map { GlanceCountdownPillView(window: $0, now: GlanceLimitsShotData.now, axis: slot.axis, open: { _ in }) }
        switch slot.pillSide {
        case .leading: HStack(spacing: GlanceLayout.pillGap) { pill; bar }
        case .trailing: HStack(spacing: GlanceLayout.pillGap) { bar; pill }
        case .below: VStack(spacing: GlanceLayout.pillGap) { bar; pill }
        }
    }

    private static func entries(_ sessions: [CoreActivitySession]) -> GlanceEntries {
        GlanceEntries(report: CoreActivityReport(sessions: sessions, failures: [], files: [], unmeasurable: [],
                                                 stats: CoreActivityStats(logs: sessions.count, truncated: 0)))
    }

    private static func strip(_ entries: GlanceEntries, slot: GlanceSlot, failure: String? = nil) -> GlanceStripView {
        GlanceStripView(strip: GlanceStrip(entries: entries, slot: slot), isOnScreen: true, failure: failure, open: { _ in })
    }

    /// The list as the controller sizes it when it fits: rows at the list's width, a bare sentence at its own.
    private static func list(_ entries: GlanceEntries, limits: [GlanceCountdownWindow] = [], failure: String? = nil) -> GlanceListView {
        GlanceListView(entries: entries.all, note: GlanceWording.noSession, failure: failure,
                       width: entries.isEmpty && limits.isEmpty ? nil : Metrics.Glance.listWidth,
                       isOnScreen: true, hint: { _ in GlanceWording.activity }, open: { _ in },
                       limits: limits, now: GlanceLimitsShotData.now)
    }

    /// A list taller than the cap, scrolled to the top, sized as `GlanceController` sizes it: the pinned Limits group keeps its
    /// height and the session rows get the rest.
    private static func scrolledList(_ entries: GlanceEntries, limits: [GlanceCountdownWindow] = []) -> some View {
        let group = limits.isEmpty ? 0 : height(list(entries, limits: limits)) - height(list(entries))
        return GlanceListView(entries: entries.all, note: GlanceWording.noSession, width: Metrics.Glance.listWidth,
                              rowsHeight: Metrics.Glance.listMaxHeight - 2 * Metrics.Glance.listPadding - group,
                              isOnScreen: true, hint: { _ in GlanceWording.activity }, open: { _ in },
                              limits: limits, now: GlanceLimitsShotData.now)
    }

    private static func height(_ view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.height.rounded(.up)
    }
}

/// Limit readings for the countdown shots, at a fixed clock. Synthetic only (S-R2); the windows and times are the mock's
/// (`session-glance-widget.html`, `LIM`).
private enum GlanceLimitsShotData {
    /// 2026-11-19 17:30 local time, so the reset clock times read like the mock's.
    static let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 17, minute: 30)) ?? Date()

    private static let hour = 3600.0

    private static func window(_ id: String, _ minutes: Int, used: Double, resets seconds: Double) -> CoreLimitWindow {
        CoreLimitWindow(id: id, minutes: minutes, scope: nil, usedPercent: used, resetsAt: now.timeIntervalSince1970 + seconds,
                        active: true, current: true)
    }

    private static func entry(_ cli: CLIID, _ windows: [CoreLimitWindow]) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: .measured, plan: nil, source: nil, at: now.timeIntervalSince1970 - 120, windows: windows)
    }

    /// The mock's "5h · còn 42 phút": Claude Code's 5-hour window, normal.
    static let fiveHour = [entry(.claude, [window("five_hour", 300, used: 40, resets: 42 * 60 + 17),
                                           window("seven_day", 10080, used: 30, resets: 3 * 24 * hour)])]
    /// The mock's "Tuần · còn 23 giờ": Codex's weekly window, low.
    static let week = [entry(.codex, [window("primary", 300, used: 20, resets: 3 * hour),
                                      window("secondary", 10080, used: 85, resets: 23 * hour + 12 * 60 + 5)])]
    /// The mock's "Hai window, 5h cạn": Claude Code's 5-hour window out, Codex's weekly window normal.
    static let both = [entry(.claude, [window("five_hour", 300, used: 97, resets: 3 * 60 + 12)]),
                       entry(.codex, [window("secondary", 10080, used: 40, resets: 4 * hour + 5 * 60 + 33)])]
    /// Outside every lead at the default 1 h weekly lead.
    static let outside = [entry(.claude, [window("five_hour", 300, used: 50, resets: 61 * 60)]),
                          entry(.codex, [window("secondary", 10080, used: 50, resets: 23 * hour)])]

    static func counting(_ results: [CoreLimitsEntry], lead: WeeklyCountdownLead = .standard) -> [GlanceCountdownWindow] {
        GlanceCountdown.counting(results, now: now, weeklyLead: lead)
    }
}

/// The mock's data sets (`session-glance-widget.html`: normal, all, long, many) as core sessions. Synthetic titles only (S-R2).
private enum GlanceShotData {
    /// A session in `state`; `minutesAgo` is its last write, which also splits an idle session into done (within 10 minutes)
    /// and idle.
    private static func session(_ index: Int, _ cli: CLIID, _ state: GlanceState, _ title: String, tool: CoreActivityTool? = nil,
                                reason: String = "Log written 2 s ago", minutesAgo: Double = 0) -> CoreActivitySession {
        let core: CoreSessionState = switch state {
        case .waiting: .waiting
        case .working: .running
        case .unmeasurable: .unmeasurable
        case .done, .idle: .idle
        }
        let ago = state == .idle ? max(minutesAgo, 40) * 60_000 : minutesAgo * 60_000
        return CoreActivitySession(cli: cli, id: "shot-\(index)", title: title, project: nil, pid: 41_000 + index, state: core,
                                   stateReason: reason, reasonCode: nil, currentTool: tool, ageMs: 3_600_000,
                                   lastWriteAgoMs: ago, cost: nil, costNote: nil)
    }

    private static func tool(_ name: String, _ target: String) -> CoreActivityTool {
        CoreActivityTool(name: name, target: target)
    }

    /// The mock's "Thường": five sessions.
    static var normal: [CoreActivitySession] { Array(all.prefix(5)) }

    /// The mock's "Đủ trạng thái": its normal five and an unmeasurable Codex process.
    static let all: [CoreActivitySession] = [
        session(1, .claude, .idle, "Tidy the docs index", minutesAgo: 40),
        session(2, .claude, .working, "Fix the Activity poll after sleep", tool: tool("Bash", "scripts/test.sh"), minutesAgo: 1),
        session(3, .codex, .done, "Port usage scan to Go", reason: "Finished 3 min ago", minutesAgo: 3),
        session(4, .claude, .waiting, "Rename the Limits card", reason: "Asks: keep the old key?"),
        session(5, .codex, .working, "Landing copy pass", tool: tool("Edit", "site/app/copy.ts")),
        session(6, .codex, .unmeasurable, "pid 48213", reason: "Rollout could not be read", minutesAgo: 2),
    ]

    /// The mock's "Tên dài": the longest titles and tool text, Greek and CJK, and a one-letter title.
    static let long: [CoreActivitySession] = [
        session(1, .claude, .waiting,
                "Investigate why the subscription limit window resets twice when the status line capture restarts during a long session",
                reason: "Asks: replace ~/.claude/settings.json statusLine with the captured wrapper command and keep a backup?"),
        session(2, .codex, .working, "Ταξινόμηση των αρχείων καταγραφής ανά έργο και ημερομηνία — 日本語のタイトルも長い",
                tool: tool("Bash", "cd core && go vet ./... && SPACEVIBE_TEST=1 go test -count=1 ./internal/activity/...")),
        session(3, .claude, .unmeasurable, "x", reason: "Tool call open, no log write for 30 s", minutesAgo: 1),
    ]

    /// The mock's "12 session".
    static let many: [CoreActivitySession] = {
        let states: [GlanceState] = [.working, .working, .idle, .done, .waiting, .working, .idle, .unmeasurable, .working, .done, .idle, .working]
        let names = ["refactor rows", "go tests", "docs pass", "icons", "limits", "site build", "hooks", "codex lock", "stop flow", "tokens",
                     "settings", "release"]
        return states.indices.map { index in
            let tool = index % 2 == 1 ? tool("Bash", "npm run build") : tool("Edit", "Sources/SpaceVibe/App/AppDelegate.swift")
            return session(index + 1, index % 3 == 0 ? .codex : .claude, states[index],
                           "Session \(String(format: "%02d", index + 1)) · \(names[index])", tool: tool,
                           reason: states[index] == .unmeasurable ? "Rollout could not be read" : "Log written 2 s ago",
                           minutesAgo: Double(index))
        }
    }()
}
