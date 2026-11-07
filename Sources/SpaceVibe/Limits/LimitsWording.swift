import Foundation

extension CoreLimitWindow {
    var resetsAtDate: Date { Date(timeIntervalSince1970: resetsAt) }
}

extension CoreLimitsEntry {
    /// The windows and when they were read; nil unless the entry is measured.
    var reading: (at: Date, windows: [CoreLimitWindow])? {
        guard state == .measured, let at else { return nil }
        return (Date(timeIntervalSince1970: at), windows)
    }
}

/// Wording for the Limits surface. Pure functions: every time is an argument, so nothing here reads the clock.
/// The app shows the share left, like a battery; a window past its reset reads "unknown", never 0% used (spec, Limits).
/// Whether a window is still running is the core's `current` flag, set when the reading was taken.
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

    static func cliName(_ cli: CoreLimitsCLI) -> String {
        switch cli {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        }
    }

    /// The plan the record names, as a tag: "pro" reads "Pro".
    static func planName(_ plan: String) -> String { plan.prefix(1).uppercased() + plan.dropFirst() }

    // MARK: Windows

    private static func exactShareLeft(_ window: CoreLimitWindow) -> Double { max(0, 100 - window.usedPercent) }

    /// Whole percent left, from 0 to 100.
    static func shareLeft(_ window: CoreLimitWindow) -> Int { Int(exactShareLeft(window).rounded()) }

    /// Tinted at 20% left (low) and 5% left (out); decided on the exact share, not the rounded one.
    static func tone(_ window: CoreLimitWindow) -> Tone {
        let left = exactShareLeft(window)
        return left <= outShare ? .out : left <= lowShare ? .low : .normal
    }

    /// `5-hour`, `Weekly`, `Weekly · <model>`. A length the engine does not map gets whole hours or days, and a record
    /// with no length is named by its own id.
    static func name(_ window: CoreLimitWindow) -> String {
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
    static func tightest(_ windows: [CoreLimitWindow], now: Date) -> CoreLimitWindow? {
        windows.filter { $0.active && $0.current }.min { shareLeft($0) < shareLeft($1) }
    }

    /// Windows to list: the active ones, plus the rest when `showInactive`.
    static func visible(_ windows: [CoreLimitWindow], showInactive: Bool) -> [CoreLimitWindow] {
        showInactive ? windows : windows.filter(\.active)
    }

    /// "3 h 12 min" until the reset; nil once it has passed.
    static func resetsIn(_ window: CoreLimitWindow, now: Date) -> String? {
        window.current ? span(window.resetsAtDate.timeIntervalSince(now)) : nil
    }

    /// The reset's clock time: "21:12", "Fri 16:00", "Nov 10".
    static func resetsAt(_ window: CoreLimitWindow, now: Date, calendar: Calendar = .current) -> String {
        clock(window.resetsAtDate, now: now, calendar: calendar)
    }

    /// The second line of a window in the page's list: "Codex · resets in 3 h 12 min", or "Codex · reset passed".
    static func entryLine(_ window: CoreLimitWindow, cli: CoreLimitsCLI, now: Date) -> String {
        let reset = resetsIn(window, now: now).map { "resets in \($0)" } ?? "reset passed"
        return "\(cliName(cli)) · \(reset)"
    }

    /// The detail's first fact: "Resets in" and "3 h 12 min", or "Reset was" and "26 min ago" once it has passed.
    static func resetFact(_ window: CoreLimitWindow, now: Date) -> (label: String, value: String) {
        if let left = resetsIn(window, now: now) { return ("Resets in", left) }
        return ("Reset was", ago(now.timeIntervalSince(window.resetsAtDate)))
    }

    // MARK: Page

    /// One line of the Limits page's list: a window of a CLI, or the CLI itself when it lists no window.
    struct Entry: Equatable, Identifiable {
        let cli: CoreLimitsCLI
        let window: CoreLimitWindow?

        var id: String { "\(cli.rawValue):\(window?.id ?? "state")" }
    }

    /// The list, CLI by CLI in the engine's order: each window to list, or one entry for a CLI with none (no reading yet,
    /// not installed, not measurable, unreadable, or no window that applies right now).
    static func entries(_ results: [CoreLimitsEntry], showInactive: Bool) -> [Entry] {
        results.flatMap { limits -> [Entry] in
            if let windows = limits.reading?.windows {
                let shown = visible(windows, showInactive: showInactive)
                if !shown.isEmpty { return shown.map { Entry(cli: limits.cli, window: $0) } }
            }
            return [Entry(cli: limits.cli, window: nil)]
        }
    }

    /// What the page selects first: the window with the least left across every CLI (ties go to the earlier CLI), else the
    /// first entry.
    static func firstSelection(_ results: [CoreLimitsEntry], entries: [Entry], now: Date) -> String? {
        let leads = results.compactMap { limits -> Entry? in
            guard let windows = limits.reading?.windows, let lead = tightest(windows, now: now) else { return nil }
            return Entry(cli: limits.cli, window: lead)
        }
        let least = leads.min { a, b in
            guard let x = a.window, let y = b.window else { return false }
            return shareLeft(x) < shareLeft(y)
        }
        return least?.id ?? entries.first?.id
    }

    // MARK: Readings

    static func isStale(at: Date, now: Date) -> Bool { now.timeIntervalSince(at) > staleAfter }

    /// "4 min ago", "2 days ago": the value under the "Reading" label.
    static func readAge(at: Date, now: Date) -> String { ago(now.timeIntervalSince(at)) }

    static func summary(_ limits: CoreLimitsEntry, now: Date) -> Summary {
        switch limits.state {
        case .measured:
            guard let reading = limits.reading else { return .state("unreadable") }
            guard let lead = tightest(reading.windows, now: now) else { return .unknown }
            return .share(left: shareLeft(lead), tone: tone(lead), stale: isStale(at: reading.at, now: now))
        case .notRecorded: return .state("no reading")
        case .notInstalled: return .state("not installed")
        case .notMeasurable: return .state("not measurable")
        case .unreadable: return .state("unreadable")
        }
    }

    /// Title and sentence of the tile that stands in for windows when a CLI has no reading. Nil when it has one.
    static func stateNote(_ limits: CoreLimitsEntry) -> (title: String, body: String)? {
        let name = cliName(limits.cli)
        switch limits.state {
        case .measured: return nil
        case .notMeasurable:
            return ("Not measurable", "\(name) keeps no usage limit on disk, and SpaceVibe does not go online for it.")
        case .notInstalled:
            return ("Not installed", "No \(name) folder on this Mac.")
        case .notRecorded:
            let body = limits.cli == .claude
                ? "Claude Code has not fetched usage on this Mac. Run \(copyHint) once in Claude Code."
                : "No Codex turn has logged limits yet."
            return ("No reading yet", body)
        case .unreadable:
            return ("Unreadable", "The file is in a shape SpaceVibe does not know.")
        }
    }

    /// What the page says for a CLI that lists no window: its state note, or that no window applies right now.
    static func entryNote(_ limits: CoreLimitsEntry) -> (title: String, body: String) {
        stateNote(limits) ?? ("No current window", "\(cliName(limits.cli)) records no limit that applies right now.")
    }

    /// Where a CLI's usage reading comes from, shown with the reading's age on the page.
    static func source(_ limits: CoreLimitsEntry) -> (title: String, body: String)? {
        if limits.source == .claudeStatusline {
            return ("From Claude Code's status line", "Last quota received from a Claude Code session. SpaceVibe makes no network request.")
        }
        return source(limits.cli)
    }

    static func source(_ cli: CoreLimitsCLI) -> (title: String, body: String)? {
        switch cli {
        case .claude:
            ("From Claude Code's own cache",
             "Saved cache fallback; it can lag behind current usage. Refresh only rereads the file. A successful \(copyHint) fetch may update it.")
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
