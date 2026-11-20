import Foundation

/// The tabs of the v5 Activity page (V5-R69): Running and Failed, with `1` and `2` as their keys. There is no Files tab (D70):
/// the core still reports edited files, the page does not show them.
enum ActivityPane: String, CaseIterable, Identifiable, Sendable {
    case running, failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: "Running"
        case .failed: "Failed"
        }
    }

    var glyph: ContentGlyph {
        switch self {
        case .running: .pulse
        case .failed: .bug
        }
    }
}

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
    var isCut: Bool { failure.title.hasSuffix("\u{2026}") && failure.title.utf16.count >= ActivityFailureTitle.limit }

    /// "once", "3 times".
    var timesText: String { failure.count == 1 ? "once" : "\(failure.count) times" }
    var statusText: String { stillFailing ? "still failing" : "passed later" }

    var spoken: String {
        "\(failure.title), failed \(timesText), \(failure.reason), \(statusText)"
    }
}

/// One CLI's band of the Running spine. A CLI the core cannot list sessions for (Gemini CLI writes no log, or a CLI that is not
/// installed) is a band with a note and no rows.
struct ActivitySessionBand: Identifiable, Equatable, Sendable {
    let cli: CLIID
    var items: [ActivitySessionItem]
    /// The words at the band's right end: "no log", "not installed".
    var extra: String?
    /// The one line inside a band that has no row.
    var note: String?

    var id: String { cli.rawValue }
    var name: String { LimitsWording.cliName(cli) }
    var waiting: Int { items.filter(\.isWaiting).count }
    var unmeasurable: Int { items.filter(\.isUnmeasurable).count }
    /// Holds a session that waits for the user, or one the log cannot show (the Answer names it): its band comes first and opens by
    /// default (V5-R55), so the row "marked in the list" is on screen.
    var holdsProblem: Bool { waiting > 0 || unmeasurable > 0 }
}

struct ActivityFailureBand: Identifiable, Equatable, Sendable {
    let cli: CLIID
    var items: [ActivityFailureItem]

    var id: String { cli.rawValue }
    var stillFailing: Int { items.filter(\.stillFailing).count }
    var holdsProblem: Bool { stillFailing > 0 }
}

enum ActivityFailureTitle {
    /// The length at which the core cuts a failure's title (`failureTitleMax` in core/internal/activity/groups.go).
    static let limit = 120
}

/// What the two tabs list, from one report and the dismissals. Pure: the clock and the CLI readings are arguments, so a test
/// fixes them. The sentences are `ActivityAnswers`'. The page has no Filter (D70): every list is already banded per CLI.
struct ActivityQuery: Equatable, Sendable {
    let isLoading: Bool
    let sessionBands: [ActivitySessionBand]
    let failureBands: [ActivityFailureBand]
    let sessions: [ActivitySessionItem]
    let failures: [ActivityFailureItem]
    /// Milliseconds between the report and `now`: the ages in it are as of the report.
    let elapsedMs: Double
    let now: Date

    init(report: CoreActivityReport?, dismissed: Set<String> = [], limits: [CoreLimitsEntry] = [], readAt: Date? = nil, now: Date = Date()) {
        self.now = now
        isLoading = report == nil
        elapsedMs = readAt.map { max(0, now.timeIntervalSince($0) * 1000) } ?? 0

        let approval = Dictionary(
            (report?.unmeasurable ?? []).filter { $0.code == $0.cli.identity.approvalLimitCode }.map { ($0.cli, $0.text) },
            uniquingKeysWith: { first, _ in first })
        let live = (report?.sessions ?? []).filter { $0.state != .ended }
            .map { ActivitySessionItem(session: $0, approvalLimit: approval[$0.cli]) }
        let ordered = live.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
        sessions = ordered
        let bands = CLICatalog.current.limitsCLIs.compactMap { shown -> ActivitySessionBand? in
            // A CLI the Limits reading calls not installed; no reading yet means nothing is known against it.
            let gone = limits.first { $0.cli == shown }?.state == .notInstalled
            let name = shown.label
            guard shown.identity.readsSessionLog else {
                return ActivitySessionBand(
                    cli: shown, items: [], extra: gone ? "not installed" : "no log",
                    note: gone ? "\(name) is not installed on this Mac." : "SpaceVibe cannot read \(name) sessions: it writes no log.")
            }
            let items = ordered.filter { $0.session.cli == shown }
            if !items.isEmpty { return ActivitySessionBand(cli: shown, items: items) }
            guard gone else { return nil }
            return ActivitySessionBand(cli: shown, items: [], extra: "not installed", note: "\(name) is not installed on this Mac.")
        }
        // A band with a waiting session comes first, then one with a session that cannot be measured, then the rest, each in the usual order.
        sessionBands = bands.filter { $0.waiting > 0 } + bands.filter { $0.waiting == 0 && $0.unmeasurable > 0 } + bands.filter { !$0.holdsProblem }

        let kept = (report?.failures ?? []).map(ActivityFailureItem.init).filter { !dismissed.contains($0.dismissKey) }
        let ranked = kept.enumerated().sorted { a, b in
            if a.element.stillFailing != b.element.stillFailing { return a.element.stillFailing }
            if a.element.failure.count != b.element.failure.count { return a.element.failure.count > b.element.failure.count }
            return a.offset < b.offset
        }.map(\.element)
        failures = ranked
        let failureBands = CLICatalog.current.inventoryCLIs.compactMap { cli -> ActivityFailureBand? in
            let items = ranked.filter { $0.failure.cli == cli }
            return items.isEmpty ? nil : ActivityFailureBand(cli: cli, items: items)
        }
        self.failureBands = failureBands.filter(\.holdsProblem) + failureBands.filter { !$0.holdsProblem }
    }

    /// The tab counts (V5-R69): sessions listed, failures not dismissed.
    func count(_ pane: ActivityPane) -> Int {
        switch pane {
        case .running: sessions.count
        case .failed: failures.count
        }
    }
}
