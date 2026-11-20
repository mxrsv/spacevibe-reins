import CoreGraphics
import Foundation

/// One limit window whose reset countdown runs, as the glance widget draws it (spec
/// `docs/specs/2026-11-19-limit-reset-countdown.md`, LC-R5, LC-R6). Which windows count, and the clock text, come from
/// `LimitsCountdown` (LC-R1, LC-R2), the same rules as the Limits page.
struct GlanceCountdownWindow: Equatable, Identifiable {
    enum Kind: Equatable {
        case fiveHour
        case weekly
    }

    /// The Limits page's id for the window (`cli:windowID`, `LimitsWording.Entry.id`), so a click selects that row (LC-R7).
    let id: String
    let cli: CLIID
    let kind: Kind
    /// "5-hour", "Weekly" (`LimitsWording.name`).
    let name: String
    let resetsAt: Date
    /// How long before the reset the countdown runs; the ring drains over it.
    let lead: TimeInterval
    /// The window's tone (LC9, `LimitsWording.tone`).
    let tone: LimitsWording.Tone
    /// The reset's clock time: "21:12", "Fri 16:00" (`LimitsWording.resetsAt`).
    let resetTime: String

    /// Seconds left at `now`; nil before the lead and from the reset on.
    func remaining(at now: Date) -> TimeInterval? {
        LimitsCountdown.remaining(until: resetsAt, lead: lead, now: now)
    }

    /// What is left of the lead, from 1 when the countdown starts to 0 at the reset.
    func share(at now: Date) -> Double {
        guard lead > 0, let left = remaining(at: now) else { return 0 }
        return min(1, max(0, left / lead))
    }
}

/// Which windows the widget counts down, and when it must look again (LC-R1, LC-R5, LC-R8). Pure: the clock, the readings and
/// the weekly lead are arguments, so a test drives every case without a window.
enum GlanceCountdown {
    /// How far past a clock change the widget wakes to draw it.
    static let wakeSlack: TimeInterval = 0.02

    /// The windows that count at `now`, the first to reset first (LC6: the pill shows the first, the list shows all). A tie
    /// keeps the core's order (Claude Code, Codex, then each CLI's own window order).
    static func counting(_ results: [CoreLimitsEntry], now: Date, weeklyLead: WeeklyCountdownLead,
                         calendar: Calendar = .current) -> [GlanceCountdownWindow] {
        candidates(results, weeklyLead: weeklyLead, now: now, calendar: calendar)
            .filter { $0.remaining(at: now) != nil }
    }

    /// When the widget must draw again: the next change of the first window's clock while one counts (its digits change on
    /// the whole second before its reset), else the moment the next window starts to count. Nil when no window ever will
    /// before the next read.
    static func nextWake(_ results: [CoreLimitsEntry], now: Date, weeklyLead: WeeklyCountdownLead) -> Date? {
        let windows = candidates(results, weeklyLead: weeklyLead, now: now, calendar: .current)
        if let first = windows.first(where: { $0.remaining(at: now) != nil }), let left = first.remaining(at: now) {
            // The clock rounds up, so it changes when `left` passes the whole second below it.
            // A little after it, so a timer that fires early still sees the new digit.
            let step = left - (left.rounded(.up) - 1)
            return now.addingTimeInterval((step > 0 ? step : LimitsCountdown.tick) + wakeSlack)
        }
        return windows.map { $0.resetsAt.addingTimeInterval(-$0.lead) }.filter { $0 > now }.min()
    }

    /// Every window that can count (a 5-hour or weekly window of Claude Code or Codex, active, current at `now`, no scope),
    /// counting or not yet, the first to reset first.
    private static func candidates(_ results: [CoreLimitsEntry], weeklyLead: WeeklyCountdownLead, now: Date,
                                   calendar: Calendar) -> [GlanceCountdownWindow] {
        let all = results.flatMap { entry -> [GlanceCountdownWindow] in
            guard let windows = entry.reading?.windows else { return [] }
            return windows.compactMap { window -> GlanceCountdownWindow? in
                guard window.isCurrent(at: now), let lead = LimitsCountdown.lead(window, cli: entry.cli, weekly: weeklyLead) else { return nil }
                return GlanceCountdownWindow(id: LimitsWording.Entry(cli: entry.cli, window: window).id, cli: entry.cli,
                                             kind: window.minutes == 300 ? .fiveHour : .weekly, name: LimitsWording.name(window),
                                             resetsAt: window.resetsAtDate, lead: lead, tone: LimitsWording.tone(window),
                                             resetTime: LimitsWording.resetsAt(window, now: now, calendar: calendar))
            }
        }
        return all.enumerated()
            .sorted { a, b in a.element.resetsAt != b.element.resetsAt ? a.element.resetsAt < b.element.resetsAt : a.offset < b.offset }
            .map(\.element)
    }
}

/// Where the countdown pill sits beside the strip (LC-R5): toward the screen centre, below the strip on a left or right edge
/// middle. The strip keeps its own slot and size; the pill never moves it.
enum GlancePillSide: Equatable {
    /// Left of the strip (a right column corner).
    case leading
    /// Right of the strip (a left column corner, and the top and bottom middles, as the mock draws them).
    case trailing
    /// Under the strip, centred on it (the left and right edge middles, whose strip is a column).
    case below
}

extension GlanceSlot {
    var pillSide: GlancePillSide {
        switch self {
        case .topRight, .bottomRight: .leading
        case .topLeft, .bottomLeft, .topCenter, .bottomCenter: .trailing
        case .leftMiddle, .rightMiddle: .below
        }
    }

    /// The pill's frame for a strip at `stripFrame` (global coordinates, origin bottom left), `GlanceLayout.pillGap` away from
    /// it, centred on the strip across the side it sits on.
    func pillFrame(for size: CGSize, beside stripFrame: CGRect) -> CGRect {
        let gap = GlanceLayout.pillGap
        let origin: CGPoint = switch pillSide {
        case .leading: CGPoint(x: stripFrame.minX - gap - size.width, y: stripFrame.midY - size.height / 2)
        case .trailing: CGPoint(x: stripFrame.maxX + gap, y: stripFrame.midY - size.height / 2)
        case .below: CGPoint(x: stripFrame.midX - size.width / 2, y: stripFrame.minY - gap - size.height)
        }
        // Whole points, as the strip's own frame, so the pill's edge is never drawn across a pixel.
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }
}

extension GlanceLayout {
    /// Between the strip and the countdown pill (the mock's group gap).
    static let pillGap: CGFloat = Space.s6
}

extension LimitsWording.Tone {
    /// The clock's ink: the Limits page's (LC9).
    var textTone: TextTone {
        switch self {
        case .normal: .primary
        case .low: .warn
        case .out: .danger
        }
    }

    /// The ring's ink: the Limits page's bar tones (LC9).
    var barTone: BarTone {
        switch self {
        case .normal: .neutral
        case .low: .warn
        case .out: .danger
        }
    }
}

/// Every word the countdown pill and the Limits group show (LC-R5, LC-R6). English, like the rest of the app.
enum GlanceCountdownWording {
    /// The pinned group's name, read by VoiceOver.
    static let groupName = "Limits"

    /// The pill's short window name.
    static func label(_ kind: GlanceCountdownWindow.Kind) -> String {
        switch kind {
        case .fiveHour: "5h"
        case .weekly: "Week"
        }
    }

    /// The clock at `now` (`LimitsCountdown.clock`); "00:00" once the reset has passed, for the moment before it leaves.
    static func clock(_ window: GlanceCountdownWindow, now: Date) -> String {
        LimitsCountdown.clock(window.remaining(at: now) ?? 0)
    }

    /// A Limits row's second line: "Claude Code · resets at 21:12".
    static func detail(_ window: GlanceCountdownWindow) -> String {
        "\(LimitsWording.cliName(window.cli)) · resets at \(window.resetTime)"
    }

    /// What VoiceOver reads for the pill and a row: "Claude Code 5-hour limit, 42 min 17 s left".
    static func spoken(_ window: GlanceCountdownWindow, now: Date) -> String {
        "\(LimitsWording.cliName(window.cli)) \(window.name) limit, \(LimitsCountdown.spoken(window.remaining(at: now) ?? 0))"
    }
}
