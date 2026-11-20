import Foundation

/// How long before a weekly reset its countdown starts (spec `docs/specs/2026-11-19-limit-reset-countdown.md`, LC3): the
/// user's choice in Settings > Limits, 1 h by default.
enum WeeklyCountdownLead: Int, CaseIterable, Identifiable, Sendable {
    case hours24 = 24, hours12 = 12, hours5 = 5, hours1 = 1

    static let standard = WeeklyCountdownLead.hours1

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) * 3600 }
    /// "24 h", the segment's label.
    var title: String { "\(rawValue) h" }
}

/// The reset countdown (LC-R1, LC-R2). Pure: the clock is an argument.
enum LimitsCountdown {
    /// The 5-hour window counts its last hour, with no setting (LC4).
    static let fiveHourLead: TimeInterval = 3600
    /// A counting clock redraws this often (LC5, LC7).
    static let tick: TimeInterval = 1
    /// A row starts ticking this long before its countdown starts: the Limits page itself redraws once a minute.
    static let wakeAhead: TimeInterval = 60

    /// The whole second at or before `date`: where a ticking clock starts, so every tick lands on a second boundary.
    static func wholeSecond(before date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    private static let fiveHourMinutes = 300
    private static let weekMinutes = 10080

    /// How long before its reset `window` counts, or nil when it never does: a window of a CLI that keeps no limits on disk, an inactive one, one scoped
    /// to a model, or one that is neither the 5-hour nor the weekly window. Claude's `five_hour` and `session` both count.
    static func lead(_ window: CoreLimitWindow, cli: CLIID, weekly: WeeklyCountdownLead) -> TimeInterval? {
        guard let reading = cli.identity.limitsReading, reading != .notKept, window.active, window.scope == nil else { return nil }
        switch window.minutes {
        case fiveHourMinutes: return fiveHourLead
        case weekMinutes: return weekly.seconds
        default: return nil
        }
    }

    /// Seconds left while the countdown runs; nil before its lead and once the reset has passed. The lead's own edge counts.
    static func remaining(until reset: Date, lead: TimeInterval?, now: Date) -> TimeInterval? {
        guard let lead else { return nil }
        let left = reset.timeIntervalSince(now)
        return left > 0 && left <= lead ? left : nil
    }

    /// "23:12:05" from an hour up, "42:17" below. Rounded up, so the clock reads "00:01" until the reset itself.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.up))
        let hours = whole / 3600, minutes = whole % 3600 / 60, rest = whole % 60
        let tail = String(format: "%02d:%02d", minutes, rest)
        return hours > 0 ? "\(hours):\(tail)" : tail
    }

    /// "42 min 17 s left", for VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.up))
        let hours = whole / 3600, minutes = whole % 3600 / 60, rest = whole % 60
        let parts = [hours > 0 ? "\(hours) h" : nil, minutes > 0 ? "\(minutes) min" : nil, "\(rest) s"].compactMap { $0 }
        return parts.joined(separator: " ") + " left"
    }
}
