import Foundation

/// Everything the v5 Limits page says, derived from one `limits.read` in one place (V5-R73, V5-R74, V5-A18): the Answer
/// sentence and its verdict, the Next resets rows, the Source lines and the bands of the Usage windows card. Pure: the clock
/// and the calendar are arguments.
///
/// Data truth (V5-R75, W23): the share shown is the share LEFT, `100 - usedPercent` (`LimitsWording.shareLeft`); a window
/// past its reset at the display clock reads unknown, never 0%. A reading's age is per CLI (`CoreLimitsEntry.at`), so a stale
/// reading marks every window of that CLI. The plan is the one the record names (Codex only today).
struct LimitsAnswer: Equatable {
    /// What the page has to go on.
    enum Read: Equatable {
        /// The first read has not landed.
        case loading
        /// The read could not run and no earlier reading exists (`LimitsModel.failure`; the core reports no per-CLI failure).
        case failed
        /// Claude Code, Codex, Gemini CLI, in the core's order.
        case read([CoreLimitsEntry])

        init(results: [CoreLimitsEntry], failure: String?) {
            if !results.isEmpty {
                self = .read(results)
            } else {
                self = failure == nil ? .loading : .failed
            }
        }
    }

    struct Verdict: Equatable {
        let glyph: VerdictGlyph.Kind
        let title: String
        let text: String
        var small: String?
    }

    /// A state glyph and what VoiceOver reads for it.
    struct Mark: Equatable {
        enum Kind: Equatable { case warn, danger, clock }
        let kind: Kind
        let label: String
    }

    /// The button a band's note or a window's popover carries; refresh, read now and retry all read the files again.
    enum Action: Equatable { case refresh, readNow, retry, copyUsage }

    /// A window's warning slot: its glyph, and the popover's sentence and button.
    struct Warning: Equatable {
        let mark: Mark
        let sentence: String
        let action: Action?
    }

    struct WindowRow: Equatable, Identifiable {
        let id: String
        let cli: CoreLimitsCLI
        let name: String
        /// Whole percent left; nil once the reset has passed.
        let left: Int?
        let tone: LimitsWording.Tone
        let warning: Warning?

        /// "Codex Weekly": the popover's head.
        var title: String { "\(LimitsWording.cliName(cli)) \(name)" }
        var spoken: String { "\(title), \(left.map { "\($0)% left" } ?? "not known")" }
    }

    struct Band: Equatable, Identifiable {
        enum Body: Equatable {
            case loading
            case windows([WindowRow])
            /// One line in place of the windows, with its button.
            case note(String, Action?)
        }

        let cli: CoreLimitsCLI
        /// Windows listed; nil when the CLI lists none.
        let count: Int?
        let mark: Mark?
        /// "read 2 days ago", on a stale reading only.
        let staleAge: String?
        let body: Body

        var id: String { cli.rawValue }
    }

    struct Reset: Equatable, Identifiable {
        let id: String
        let cli: CoreLimitsCLI
        /// "21:12", "Fri 16:00", "Nov 10".
        let time: String
        /// "Codex Weekly".
        let title: String
    }

    struct SourceLine: Equatable, Identifiable {
        let cli: CoreLimitsCLI
        /// "Codex Pro": the CLI and the plan its record names.
        let name: String
        /// "read 4 min ago", "no reading", "not installed", "no log", "reading".
        let state: String

        var id: String { cli.rawValue }
    }

    /// Nil while the first read runs.
    let sentence: String?
    let verdict: Verdict?
    /// Nil while the first read runs; current windows only, the soonest first, and never a share (D60).
    let resets: [Reset]?
    let sources: [SourceLine]
    let bands: [Band]

    init(_ read: Read, showUnused: Bool, now: Date, calendar: Calendar = .current) {
        switch read {
        case .loading:
            sentence = nil
            verdict = nil
            resets = nil
            sources = CoreLimitsCLI.allCases.map { SourceLine(cli: $0, name: LimitsWording.cliName($0), state: "reading") }
            bands = CoreLimitsCLI.allCases.map { Band(cli: $0, count: nil, mark: nil, staleAge: nil, body: .loading) }
        case .failed:
            sentence = "No reading yet."
            verdict = Verdict(glyph: .nm, title: "The read did not finish", text: "Refresh to try again.")
            resets = []
            sources = CoreLimitsCLI.allCases.map { SourceLine(cli: $0, name: LimitsWording.cliName($0), state: "no reading") }
            bands = CoreLimitsCLI.allCases.map {
                Band(cli: $0, count: nil, mark: Mark(kind: .danger, label: "Read failed"), staleAge: nil,
                     body: .note("The last read did not finish.", .retry))
            }
        case .read(let entries):
            (sentence, verdict) = Self.answer(entries, now: now, calendar: calendar)
            resets = Self.resets(entries, showUnused: showUnused, now: now, calendar: calendar)
            sources = entries.map { Self.source($0, now: now) }
            bands = entries.map { Self.band($0, showUnused: showUnused, now: now, calendar: calendar) }
        }
    }

    // MARK: Answer

    /// A CLI with a reading and the window that decides its room: the whole-plan window (no scope) that is current and
    /// active with the least left. Scoped windows (one model) do not decide where heavy work goes.
    private struct Room {
        let entry: CoreLimitsEntry
        let at: Date
        let windows: [CoreLimitWindow]
        let tightest: CoreLimitWindow

        var left: Int { LimitsWording.shareLeft(tightest) }
        var isLow: Bool { LimitsWording.tone(tightest) != .normal }
        var name: String { LimitsWording.cliName(entry.cli) }
    }

    private static func planWide(_ windows: [CoreLimitWindow], now: Date) -> [CoreLimitWindow] {
        windows.filter { $0.scope == nil && $0.isCurrent(at: now) && $0.active }
    }

    private static func exactLeft(_ window: CoreLimitWindow) -> Double { 100 - window.usedPercent }

    private static func answer(_ entries: [CoreLimitsEntry], now: Date, calendar: Calendar) -> (String, Verdict) {
        let readings = entries.compactMap { entry in entry.reading.map { (entry, $0.at, $0.windows) } }
        let rooms = readings.compactMap { entry, at, windows -> Room? in
            guard let tightest = planWide(windows, now: now).min(by: { exactLeft($0) < exactLeft($1) }) else { return nil }
            return Room(entry: entry, at: at, windows: windows, tightest: tightest)
        }
        // Most room first; the core's order breaks a tie.
        let ranked = rooms.enumerated().sorted { a, b in
            exactLeft(a.element.tightest) != exactLeft(b.element.tightest)
                ? exactLeft(a.element.tightest) > exactLeft(b.element.tightest) : a.offset < b.offset
        }.map(\.element)
        let stale = readings.filter { LimitsWording.isStale(at: $0.1, now: now) }
            .map { "\(LimitsWording.cliName($0.0.cli)) was read \(LimitsWording.readAge(at: $0.1, now: now))." }
        let small = stale.isEmpty ? nil : stale.joined(separator: " ")

        guard let best = ranked.first else {
            let sentence = readings.isEmpty ? "No reading yet." : "No current reading."
            let text = readings.isEmpty ? "Refresh to read usage from the local files." : "No window that applies now has a reading."
            return (sentence, Verdict(glyph: .nm, title: "Nothing to compare", text: text, small: small))
        }

        if best.isLow {
            // Every CLI with room is low: hold until the first of them has no low whole-plan window left.
            let until = ranked.compactMap { room in
                planWide(room.windows, now: now).filter { LimitsWording.tone($0) != .normal }.map(\.resetsAt).max()
            }.min() ?? best.tightest.resetsAt
            let verdict = ranked.count > 1
                ? Verdict(glyph: .used, title: "Both CLIs are low", text: "The best window left has \(best.left)%.", small: small)
                : Verdict(glyph: .used, title: "\(best.name) is low", text: "Its tightest window has \(best.left)% left.", small: small)
            return ("Hold heavy work until \(clock(until, now: now, calendar: calendar)).", verdict)
        }

        // Until the best CLI's longest whole-plan window resets (the mock's weekly window).
        let longest = planWide(best.windows, now: now).max { ($0.minutes ?? 0) < ($1.minutes ?? 0) } ?? best.tightest
        let sentence = "Do heavy work in \(best.name) until \(clock(longest.resetsAt, now: now, calendar: calendar))."
        let other = readings.lazy.filter { $0.0.cli != best.entry.cli }.compactMap { entry, _, windows -> (String, CoreLimitWindow)? in
            windows.filter { $0.isCurrent(at: now) && $0.active }.min { exactLeft($0) < exactLeft($1) }.map { (LimitsWording.cliName(entry.cli), $0) }
        }.first
        if let other {
            let text = "\(LimitsWording.name(other.1)) has \(LimitsWording.shareLeft(other.1))% left."
            return (sentence, Verdict(glyph: .used, title: "\(other.0) is the tighter one", text: text, small: small))
        }
        return (sentence, Verdict(glyph: .used, title: "\(best.name) has room", text: "Its tightest window has \(best.left)% left.", small: small))
    }

    private static func clock(_ seconds: Double, now: Date, calendar: Calendar) -> String {
        LimitsWording.clock(Date(timeIntervalSince1970: seconds), now: now, calendar: calendar)
    }

    // MARK: Next resets

    private static func resets(_ entries: [CoreLimitsEntry], showUnused: Bool, now: Date, calendar: Calendar) -> [Reset] {
        let rows = entries.flatMap { entry -> [(CoreLimitsEntry, CoreLimitWindow)] in
            guard let windows = entry.reading?.windows else { return [] }
            return LimitsWording.visible(windows, showInactive: showUnused).filter { $0.isCurrent(at: now) }.map { (entry, $0) }
        }
        return rows.enumerated()
            .sorted { a, b in
                a.element.1.resetsAt != b.element.1.resetsAt ? a.element.1.resetsAt < b.element.1.resetsAt : a.offset < b.offset
            }
            .map { _, row in
                let (entry, window) = row
                return Reset(id: "\(entry.cli.rawValue):\(window.id)", cli: entry.cli,
                             time: LimitsWording.resetsAt(window, now: now, calendar: calendar),
                             title: "\(LimitsWording.cliName(entry.cli)) \(LimitsWording.name(window))")
            }
    }

    // MARK: Source

    private static func source(_ entry: CoreLimitsEntry, now: Date) -> SourceLine {
        let cli = LimitsWording.cliName(entry.cli)
        if let reading = entry.reading {
            let name = entry.plan.map { "\(cli) \(LimitsWording.planName($0))" } ?? cli
            return SourceLine(cli: entry.cli, name: name, state: "read \(LimitsWording.readAge(at: reading.at, now: now))")
        }
        let state = switch entry.state {
        case .notInstalled: "not installed"
        case .notMeasurable: "no log"
        case .measured, .notRecorded, .unreadable: "no reading"
        }
        return SourceLine(cli: entry.cli, name: cli, state: state)
    }

    // MARK: Bands

    private static func band(_ entry: CoreLimitsEntry, showUnused: Bool, now: Date, calendar: Calendar) -> Band {
        let cli = LimitsWording.cliName(entry.cli)
        guard let reading = entry.reading else {
            switch entry.state {
            case .notRecorded:
                return Band(cli: entry.cli, count: nil, mark: nil, staleAge: nil, body: .note("No reading yet.", .readNow))
            case .notInstalled:
                return Band(cli: entry.cli, count: nil, mark: nil, staleAge: nil,
                            body: .note("Not installed. \(SpaceVibeMark.productName) found no \(cli) on this Mac.", nil))
            case .notMeasurable:
                return Band(cli: entry.cli, count: nil, mark: nil, staleAge: nil,
                            body: .note("Not measurable. \(cli) exposes no usage numbers.", nil))
            case .unreadable, .measured:
                return Band(cli: entry.cli, count: nil, mark: Mark(kind: .warn, label: "Unreadable"), staleAge: nil,
                            body: .note("Can't read usage from local files.", .retry))
            }
        }
        let stale = LimitsWording.isStale(at: reading.at, now: now)
        let age = LimitsWording.readAge(at: reading.at, now: now)
        let shown = LimitsWording.visible(reading.windows, showInactive: showUnused)
        let rows = shown.map { row($0, cli: entry.cli, stale: stale ? age : nil, now: now, calendar: calendar) }
        let tones = reading.windows.filter { $0.isCurrent(at: now) && $0.active }.map(LimitsWording.tone)
        let mark: Mark? = tones.contains(.out) ? Mark(kind: .danger, label: "A window is low")
            : tones.contains(.low) ? Mark(kind: .warn, label: "A window is low") : nil
        let body: Band.Body = rows.isEmpty ? .note(LimitsWording.entryNote(entry).body, nil) : .windows(rows)
        return Band(cli: entry.cli, count: rows.count, mark: mark, staleAge: stale ? "read \(age)" : nil, body: body)
    }

    /// The slot's glyph in the mock's order: a passed reset, then a stale reading (both the neutral clock), then little left.
    private static func row(_ window: CoreLimitWindow, cli: CoreLimitsCLI, stale age: String?, now: Date, calendar: Calendar) -> WindowRow {
        let name = LimitsWording.name(window)
        let left = window.isCurrent(at: now) ? LimitsWording.shareLeft(window) : nil
        let tone = window.isCurrent(at: now) ? LimitsWording.tone(window) : .normal
        let warning: Warning?
        if left == nil {
            warning = Warning(mark: Mark(kind: .clock, label: "\(name): not known, reset passed"),
                              sentence: "The reset time passed and no reading came after it. It is not 0%.", action: .refresh)
        } else if let age {
            warning = Warning(mark: Mark(kind: .clock, label: "\(name): read \(age)"),
                              sentence: "Read \(age). The real number may be lower.", action: .refresh)
        } else if let left, tone != .normal {
            let resets = LimitsWording.resetsAt(window, now: now, calendar: calendar)
            warning = Warning(mark: Mark(kind: tone == .out ? .danger : .warn, label: "\(name): \(left)% left"),
                              sentence: "\(left)% left, resets \(resets).", action: cli == .claude ? .copyUsage : nil)
        } else {
            warning = nil
        }
        return WindowRow(id: "\(cli.rawValue):\(window.id)", cli: cli, name: name, left: left, tone: tone, warning: warning)
    }
}
