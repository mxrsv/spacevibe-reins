import Foundation

/// Wording and time formatting for the Activity screen. Pure functions: every time is an argument, so nothing here
/// reads the clock. Wording rules from the spec: cost always carries `~`, and a later passing run is a fact about the log,
/// never "fixed".
enum ActivityFormat {
    private static let minute = 60_000.0
    private static let hour = 60 * minute
    private static let day = 24 * hour

    /// Time since a session started or a log was written: "<1 min", "18 min", "2 h 5 min", "3 d".
    static func span(_ ms: Double) -> String {
        if ms < minute { return "<1 min" }
        if ms < hour { return "\(Int(ms / minute)) min" }
        if ms < day {
            let h = Int(ms / hour)
            let m = Int(ms.truncatingRemainder(dividingBy: hour) / minute)
            return m > 0 ? "\(h) h \(m) min" : "\(h) h"
        }
        return "\(Int(ms / day)) d"
    }

    /// The engine writes ISO 8601 with milliseconds (`2026-11-02T11:58:00.000Z`).
    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: iso) { return parsed }
        return ISO8601DateFormatter().date(from: iso)
    }

    private static func formatted(_ date: Date, _ format: String, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "4 min ago", "1 h ago", "yesterday", then "Oct 29".
    static func ago(_ iso: String?, now: Date) -> String {
        guard let at = date(iso) else { return "unknown" }
        let ms = max(0, now.timeIntervalSince(at) * 1000)
        if ms < minute { return "just now" }
        if ms < day { return "\(span(ms)) ago" }
        if ms < 2 * day { return "yesterday" }
        return formatted(at, "MMM d", locale: "en_US")
    }

    /// "Nov 7" in the calendar's time zone.
    static func shortDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// "14:02" for today, "Oct 29, 14:02" for another day (local time).
    static func clock(_ iso: String, now: Date) -> String {
        guard let at = date(iso) else { return "unknown time" }
        let time = formatted(at, "HH:mm", locale: "en_GB")
        return Calendar.current.isDate(at, inSameDayAs: now) ? time : "\(formatted(at, "MMM d", locale: "en_US")), \(time)"
    }

    /// The cost is always an estimate, so it always carries the `~`.
    static func cost(_ usd: Double) -> String {
        usd > 0 && usd < 0.01 ? "~<$0.01" : "~$" + String(format: "%.2f", usd)
    }

    /// Neutral on purpose: a later pass of the same command is a fact about the log, not proof of a fix.
    static func laterPass(_ failure: CoreActivityFailure, now: Date) -> String? {
        guard let pass = failure.laterPass else { return nil }
        let times = failure.count == 1 ? "1 failure" : "\(failure.count) failures"
        return "passed once at \(clock(pass, now: now)) after \(times); one pass is not proof"
    }

    static func projects(_ list: [String]) -> String? {
        if list.isEmpty { return nil }
        return list.count <= 2 ? list.joined(separator: ", ") : "\(list.count) projects"
    }

    /// The engine's fallback title when no request is readable: "2026-11-02 · 1a2b3c4d" (or "unknown date · ...").
    static func isFallbackTitle(_ title: String) -> Bool {
        title.range(of: #"^(\d{4}-\d{2}-\d{2}|unknown date) · \S{0,8}$"#, options: .regularExpression) != nil
    }

    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) " + (n == 1 ? one : (many ?? one + "s"))
    }
}
