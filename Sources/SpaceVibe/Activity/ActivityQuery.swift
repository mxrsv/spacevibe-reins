import Foundation

/// The tabs of the v5 Activity page (V5-R69): Running, Failed, Files, with `1` to `3` as their keys.
enum ActivityPane: String, CaseIterable, Identifiable, Sendable {
    case running, failed, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: "Running"
        case .failed: "Failed"
        case .files: "Files"
        }
    }

    var glyph: ContentGlyph {
        switch self {
        case .running: .pulse
        case .failed: .bug
        case .files: .file
        }
    }

    /// The Filter button and its `/` key exist on these tabs; Files has no field to filter by (V5-R61).
    var hasFilter: Bool { self != .files }
}

/// The one Filter field of the page (V5-R69): the CLI. It filters Running and Failed.
enum ActivityFilterField: String, FilterFieldKind {
    case cli

    var title: String { "CLI" }
    /// The first words of a chip.
    var chipTitle: String { "CLI is" }

    var values: [FilterValue] {
        [FilterValue("claude", "Claude Code"), FilterValue("codex", "Codex")]
    }
}

typealias ActivityFilter = PickFilter<ActivityFilterField>

/// One live session as a row (V5-R70): the core's session with the words the row and its popover use.
struct ActivitySessionItem: Identifiable, Equatable, Sendable {
    let session: CoreActivitySession
    /// The core's sentence for this CLI's fixed limit: it does not record approval waits, so a long tool run and a wait look the
    /// same (`claude-prompt-vs-busy`, `codex-tool-silent`). Nil when the report lists none for the CLI.
    var approvalLimit: String?

    /// What SpaceVibe cannot see about this session, in the core's words: a session it could not measure says why; a running
    /// session with a tool call open gets the CLI's approval limit, because the log would not show that it waits for one.
    var cannotSee: String? {
        if isUnmeasurable { return session.stateReason }
        if session.state == .running, session.currentTool != nil { return approvalLimit }
        return nil
    }

    /// The warning slot's neutral clock label.
    var cannotSeeLabel: String { isUnmeasurable ? "Not measurable" : "Approval waits not visible" }

    var id: String { "\(session.cli.rawValue):\(session.id)" }
    var isWaiting: Bool { session.state == .waiting }
    var isUnmeasurable: Bool { session.state == .unmeasurable }
    /// Stop needs a live process the core can name again: an id ending `:unknown` cannot authorize it (core-protocol.md).
    var canStop: Bool { !session.id.hasSuffix(":unknown") }

    /// The state column (104 wide): "waiting", "idle", "running Bash", "not measurable".
    var stateText: String {
        switch session.state {
        case .waiting: "waiting"
        case .idle, .ended: "idle"
        case .unmeasurable: "not measurable"
        case .running: session.currentTool.map { "running \($0.name)" } ?? "running"
        }
    }

    /// What VoiceOver reads for the row.
    var spoken: String {
        [session.title, session.cli.label, session.project, stateText].compactMap { $0 }.joined(separator: ", ")
    }

    /// Waiting first, then the ones whose state cannot be told (an approval wait looks like a long tool run), then running, idle.
    fileprivate var rank: Int {
        switch session.state {
        case .waiting: 0
        case .unmeasurable: 1
        case .running: 2
        case .idle, .ended: 3
        }
    }
}

/// One failed command or hook as a row (V5-R71).
struct ActivityFailureItem: Identifiable, Equatable, Sendable {
    let failure: CoreActivityFailure

    var id: String { "\(failure.cli.rawValue):\(failure.kind.rawValue):\(failure.key)" }
    /// A dismissal holds until the same failure fails again: its `last` moves on.
    var dismissKey: String { "\(id)@\(failure.last ?? "")" }
    var stillFailing: Bool { failure.laterPass == nil }

    /// The core cuts a title at 120 characters and ends it with an ellipsis; a cut command is not copied as if it were whole.
    var isCut: Bool { failure.title.hasSuffix("\u{2026}") && failure.title.utf16.count >= ActivityRows.failureTitleLimit }

    /// "once", "3 times".
    var timesText: String { failure.count == 1 ? "once" : "\(failure.count) times" }
    var statusText: String { stillFailing ? "still failing" : "passed later" }

    var spoken: String {
        "\(failure.title), failed \(timesText), \(failure.reason), \(statusText)"
    }
}

/// One edited file as a row (V5-R72): the name, the folder in front of it and the edits the logs hold.
struct ActivityFileItem: Identifiable, Equatable, Sendable {
    let file: CoreActivityFile

    var id: String { file.path }

    private var split: (folder: String, name: String) {
        let cut = file.label.lastIndex(of: "/").map { file.label.index(after: $0) } ?? file.label.startIndex
        return (String(file.label[..<cut]), String(file.label[cut...]))
    }

    var name: String { split.name }
    var folder: String { split.folder }
    var editsText: String { ActivityFormat.plural(file.edits, "edit") }
}

/// One CLI's band of the Running spine. A CLI the core cannot list sessions for (Gemini CLI writes no log, or a CLI that is not
/// installed) is a band with a note and no rows.
struct ActivitySessionBand: Identifiable, Equatable, Sendable {
    let cli: CoreLimitsCLI
    var items: [ActivitySessionItem]
    /// The words at the band's right end: "no log", "not installed".
    var extra: String?
    /// The one line inside a band that has no row.
    var note: String?

    var id: String { cli.rawValue }
    var name: String { LimitsWording.cliName(cli) }
    var waiting: Int { items.filter(\.isWaiting).count }
    /// Holds a waiting session: its band comes first and opens by default (V5-R55).
    var holdsProblem: Bool { waiting > 0 }
}

struct ActivityFailureBand: Identifiable, Equatable, Sendable {
    let cli: CoreCLI
    var items: [ActivityFailureItem]

    var id: String { cli.rawValue }
    var stillFailing: Int { items.filter(\.stillFailing).count }
    var holdsProblem: Bool { stillFailing > 0 }
}

/// A file band of the Edited files spine: `Edited today` and `Earlier`.
struct ActivityFileBand: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    var items: [ActivityFileItem]
}

extension ActivityRows {
    /// The length at which the core cuts a failure's title (`failureTitleMax` in core/internal/activity/groups.go).
    static let failureTitleLimit = 120
}

/// What the three tabs list, from one report, the Filter and the dismissals. Pure: the clock, the calendar and the CLI readings
/// are arguments, so a test fixes them. The sentences are `ActivityAnswers`'.
struct ActivityQuery: Equatable, Sendable {
    let isLoading: Bool
    let filter: ActivityFilter
    let sessionBands: [ActivitySessionBand]
    let failureBands: [ActivityFailureBand]
    let fileBands: [ActivityFileBand]
    let sessions: [ActivitySessionItem]
    let failures: [ActivityFailureItem]
    let files: [ActivityFileItem]
    /// Milliseconds between the report and `now`: the ages in it are as of the report.
    let elapsedMs: Double
    let now: Date
    let logs: Int
    let installed: Set<CoreCLI>

    init(report: CoreActivityReport?, filter: ActivityFilter = ActivityFilter(), dismissed: Set<String> = [], limits: [CoreLimitsEntry] = [],
         readAt: Date? = nil, now: Date = Date(), calendar: Calendar = .current) {
        self.filter = filter
        self.now = now
        isLoading = report == nil
        elapsedMs = readAt.map { max(0, now.timeIntervalSince($0) * 1000) } ?? 0
        logs = report?.stats.logs ?? 0
        // A CLI the Limits reading calls not installed; no reading yet means nothing is known against it.
        let installed = Set(CoreCLI.allCases.filter { cli in
            limits.first { $0.cli.rawValue == cli.rawValue }.map { $0.state != .notInstalled } ?? true
        })
        self.installed = installed
        func cliOn(_ cli: CoreCLI) -> Bool { filter.count(.cli) == 0 || filter.isPicked(.cli, cli.rawValue) }

        let approval = Dictionary(
            (report?.unmeasurable ?? []).filter { $0.code == "claude-prompt-vs-busy" || $0.code == "codex-tool-silent" }.map { ($0.cli, $0.text) },
            uniquingKeysWith: { first, _ in first })
        let live = (report?.sessions ?? []).filter { $0.state != .ended && cliOn($0.cli) }
            .map { ActivitySessionItem(session: $0, approvalLimit: approval[$0.cli]) }
        let ordered = live.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
        sessions = ordered
        var bands = CoreCLI.allCases.filter(cliOn).compactMap { cli -> ActivitySessionBand? in
            let items = ordered.filter { $0.session.cli == cli }
            if !items.isEmpty { return ActivitySessionBand(cli: CoreLimitsCLI(cli), items: items) }
            guard !installed.contains(cli) else { return nil }
            return ActivitySessionBand(cli: CoreLimitsCLI(cli), items: [], extra: "not installed", note: "\(cli.label) is not installed on this Mac.")
        }
        if filter.count(.cli) == 0 {
            let gone = limits.first { $0.cli == .gemini }?.state == .notInstalled
            bands.append(ActivitySessionBand(
                cli: .gemini, items: [], extra: gone ? "not installed" : "no log",
                note: gone ? "Gemini CLI is not installed on this Mac." : "SpaceVibe cannot read Gemini CLI sessions: it writes no log."))
        }
        // Bands that hold a waiting session come first, in their usual order.
        sessionBands = bands.filter(\.holdsProblem) + bands.filter { !$0.holdsProblem }

        let kept = (report?.failures ?? []).filter { cliOn($0.cli) }.map(ActivityFailureItem.init).filter { !dismissed.contains($0.dismissKey) }
        let ranked = kept.enumerated().sorted { a, b in
            if a.element.stillFailing != b.element.stillFailing { return a.element.stillFailing }
            if a.element.failure.count != b.element.failure.count { return a.element.failure.count > b.element.failure.count }
            return a.offset < b.offset
        }.map(\.element)
        failures = ranked
        let failureBands = CoreCLI.allCases.compactMap { cli -> ActivityFailureBand? in
            let items = ranked.filter { $0.failure.cli == cli }
            return items.isEmpty ? nil : ActivityFailureBand(cli: cli, items: items)
        }
        self.failureBands = failureBands.filter(\.holdsProblem) + failureBands.filter { !$0.holdsProblem }

        let all = (report?.files ?? []).map(ActivityFileItem.init).sorted(by: Self.mostEdited)
        files = all
        let today = all.filter { item in
            ActivityFormat.date(item.file.last).map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
        let todayIDs = Set(today.map(\.id))
        fileBands = [
            ActivityFileBand(id: "today", title: "Edited today", items: today),
            ActivityFileBand(id: "earlier", title: today.isEmpty ? "Edited files" : "Earlier", items: all.filter { !todayIDs.contains($0.id) }),
        ].filter { !$0.items.isEmpty }
    }

    /// Most edits first; a tie goes to the later edit, then the path.
    private static func mostEdited(_ a: ActivityFileItem, _ b: ActivityFileItem) -> Bool {
        if a.file.edits != b.file.edits { return a.file.edits > b.file.edits }
        let x = ActivityFormat.date(a.file.last), y = ActivityFormat.date(b.file.last)
        if x != y { return (x ?? .distantPast) > (y ?? .distantPast) }
        return a.file.path < b.file.path
    }

    /// The tab counts (V5-R69): sessions listed, failures not dismissed, files listed. Each follows the Filter where the tab has one.
    func count(_ pane: ActivityPane) -> Int {
        switch pane {
        case .running: sessions.count
        case .failed: failures.count
        case .files: files.count
        }
    }

    /// The filter named for an Answer: " in Codex", " in Claude Code or Codex"; empty when no CLI is picked.
    var scope: String {
        let names = ActivityFilterField.cli.values.filter { filter.isPicked(.cli, $0.id) }.map(\.title)
        return names.isEmpty ? "" : " in \(names.joined(separator: " or "))"
    }

    /// Every CLI the filter lets through is not installed.
    var pickedAreAllMissing: Bool {
        let picked = CoreCLI.allCases.filter { filter.count(.cli) == 0 || filter.isPicked(.cli, $0.rawValue) }
        return !picked.isEmpty && picked.allSatisfy { !installed.contains($0) }
    }
}
