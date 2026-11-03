import Foundation
import ReinsCore

/// Wording for the Limits surface. Pure functions: every time is an argument, so nothing here reads the clock.
/// The app shows the share left, like a battery; a window past its reset reads "unknown", never 0% used (spec, Limits).
enum LimitsWording {
    enum Tone: Equatable { case normal, low, out }

    /// What a sidebar tile shows for one CLI.
    enum Summary: Equatable {
        case share(left: Int, tone: Tone, stale: Bool)
        /// Measured, but no window is current and active: every reset has passed since the reading.
        case unknown
        /// No reading to show: "no reading", "not installed", "not measurable" or "unreadable".
        case state(String)
    }

    /// A reading older than this carries a warning and the `/usage` hint (plan, Decisions).
    static let staleAfter: TimeInterval = 6 * 3600
    static let lowShare = 20.0
    static let outShare = 5.0
    static let copyHint = "/usage"

    static func cliName(_ cli: LimitsCLI) -> String {
        switch cli {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        }
    }

    /// The plan the record names, as a tag: "pro" reads "Pro".
    static func planName(_ plan: String) -> String { plan.prefix(1).uppercased() + plan.dropFirst() }

    // MARK: Windows

    private static func exactShareLeft(_ window: LimitWindow) -> Double { max(0, 100 - window.usedPercent) }

    /// Whole percent left, from 0 to 100.
    static func shareLeft(_ window: LimitWindow) -> Int { Int(exactShareLeft(window).rounded()) }

    /// Tinted at 20% left (low) and 5% left (out); decided on the exact share, not the rounded one.
    static func tone(_ window: LimitWindow) -> Tone {
        let left = exactShareLeft(window)
        return left <= outShare ? .out : left <= lowShare ? .low : .normal
    }

    /// `5-hour`, `Weekly`, `Weekly · <model>`. A length the engine does not map gets whole hours or days, and a record
    /// with no length is named by its own id.
    static func name(_ window: LimitWindow) -> String {
        let base: String
        switch window.minutes {
        case 300: base = "5-hour"
        case 10080: base = "Weekly"
        case let minutes? where minutes % 1440 == 0: base = "\(minutes / 1440)-day"
        case let minutes? where minutes % 60 == 0: base = "\(minutes / 60)-hour"
        default:
            let own = window.id.split(separator: ":").first.map(String.init) ?? window.id
            let spaced = own.replacingOccurrences(of: "_", with: " ")
            base = spaced.prefix(1).uppercased() + spaced.dropFirst()
        }
        return window.scope.map { "\(base) · \($0)" } ?? base
    }

    /// The window that decides how much is usable: the current, active one with the least left. Nil when there is none.
    static func tightest(_ windows: [LimitWindow], now: Date) -> LimitWindow? {
        windows.filter { $0.active && $0.isCurrent(at: now) }.min { shareLeft($0) < shareLeft($1) }
    }

    /// Windows to list: the active ones, plus the rest when `showInactive`.
    static func visible(_ windows: [LimitWindow], showInactive: Bool) -> [LimitWindow] {
        showInactive ? windows : windows.filter(\.active)
    }

    /// "Resets in 3 h 12 min · 21:12", or "Reset at 17:34 · no newer reading" once the reset has passed.
    static func resets(_ window: LimitWindow, now: Date, calendar: Calendar = .current) -> String {
        let when = clock(window.resetsAt, now: now, calendar: calendar)
        if window.isCurrent(at: now) { return "Resets in \(span(window.resetsAt.timeIntervalSince(now))) · \(when)" }
        return "Reset at \(when) · no newer reading"
    }

    // MARK: Readings

    static func isStale(at: Date, now: Date) -> Bool { now.timeIntervalSince(at) > staleAfter }

    /// "read 4 min ago", "read 2 days ago".
    static func readAge(at: Date, now: Date) -> String { "read \(ago(now.timeIntervalSince(at)))" }

    static func summary(_ limits: CLILimits, now: Date) -> Summary {
        switch limits.state {
        case .measured(let at, let windows):
            guard let lead = tightest(windows, now: now) else { return .unknown }
            return .share(left: shareLeft(lead), tone: tone(lead), stale: isStale(at: at, now: now))
        case .notRecorded: return .state("no reading")
        case .notInstalled: return .state("not installed")
        case .notMeasurable: return .state("not measurable")
        case .unreadable: return .state("unreadable")
        }
    }

    /// Title and sentence of the tile that stands in for windows when a CLI has no reading. Nil when it has one.
    static func stateNote(_ limits: CLILimits) -> (title: String, body: String)? {
        let name = cliName(limits.cli)
        switch limits.state {
        case .measured: return nil
        case .notMeasurable:
            return ("Not measurable", "\(name) keeps no usage limit on disk, and Reins does not go online for it.")
        case .notInstalled:
            return ("Not installed", "No \(name) folder on this Mac.")
        case .notRecorded:
            let body = limits.cli == .claude
                ? "Claude Code has not fetched usage on this Mac. Run \(copyHint) once in Claude Code."
                : "No Codex turn has logged limits yet."
            return ("No reading yet", body)
        case .unreadable:
            return ("Unreadable", "The file is in a shape Reins does not know.")
        }
    }

    /// The one line a CLI's usage reading comes from, shown behind the info button.
    static func source(_ cli: LimitsCLI) -> (title: String, body: String)? {
        switch cli {
        case .claude:
            ("From Claude Code's own cache",
             "Claude Code saves this when it fetches usage, for example in \(copyHint). Reins reads the file and asks nobody.")
        case .codex:
            ("From the last Codex turn", "Codex logs its limits after every turn. The reading moves when you use Codex.")
        case .gemini: nil
        }
    }

    // MARK: Time

    /// "12 min", "3 h 12 min", "2 d 22 h". Under a minute reads "<1 min".
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) d \(hours % 24) h"
    }

    /// "12 min ago", "5 h ago", "2 days ago".
    static func ago(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// Today "21:12", within six days "Fri 16:00", later "Nov 10".
    static func clock(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = date.timeIntervalSince(now) / 86_400
        let format: String
        if calendar.isDate(date, inSameDayAs: now) { format = "HH:mm" } else if abs(days) < 6 { format = "EEE HH:mm" } else { format = "MMM d" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
