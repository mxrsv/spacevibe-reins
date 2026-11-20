import Foundation

/// The state a session shows on the glance widget (GW-R2). Declared in display order (GW-R3): waiting, working, done,
/// unmeasurable, idle.
enum GlanceState: Int, CaseIterable, Equatable, Sendable {
    case waiting, working, done, unmeasurable, idle

    /// Nil for `ended`: an ended session has no entry (GW10). `idle` reads as done while its log was written within
    /// `GlanceEntries.doneWindowMs` (GW8); with no known write it reads as idle.
    init?(_ session: CoreActivitySession) {
        switch session.state {
        case .running: self = .working
        case .waiting: self = .waiting
        case .unmeasurable: self = .unmeasurable
        case .ended: return nil
        case .idle:
            if let ago = session.lastWriteAgoMs, ago <= GlanceEntries.doneWindowMs {
                self = .done
            } else {
                self = .idle
            }
        }
    }
}

/// One live session on the widget: what the strip icon and the hover row need (GW-R2, GW-R5).
struct GlanceEntry: Identifiable, Equatable, Sendable {
    /// Unique across both CLIs, the same shape as `ActivitySessionItem.id`.
    var id: String { "\(cli.rawValue):\(sessionID)" }
    let sessionID: String
    let cli: CLIID
    let state: GlanceState
    let title: String
    /// The open tool call as "name · target", or the name alone when the target is empty. Nil with no tool call.
    let toolText: String?
    let pid: Int
    /// The core's sentence for the state; the hover shows it for an unmeasurable session (GW9).
    let stateReason: String
    let lastWriteAgoMs: Double?

    init?(_ session: CoreActivitySession) {
        guard let state = GlanceState(session) else { return nil }
        sessionID = session.id
        cli = session.cli
        self.state = state
        title = session.title
        toolText = session.currentTool.map(Self.toolText)
        pid = session.pid
        stateReason = session.stateReason
        lastWriteAgoMs = session.lastWriteAgoMs
    }

    static func toolText(_ tool: CoreActivityTool) -> String {
        tool.target.isEmpty ? tool.name : "\(tool.name) · \(tool.target)"
    }

    /// GW-R3: state group first, then newest write (nil last), then id so equal writes keep a stable order.
    static func precedes(_ a: GlanceEntry, _ b: GlanceEntry) -> Bool {
        if a.state != b.state { return a.state.rawValue < b.state.rawValue }
        switch (a.lastWriteAgoMs, b.lastWriteAgoMs) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.id < b.id
        }
    }
}

/// One `CoreActivityReport` turned into what the glance widget shows: every live session in display order (`all`, the hover
/// list, GW-R5), the first `shownLimit` of them for the collapsed strip (`shown`) and the count behind `+N` (`overflow`, GW12).
/// `isEmpty` is the no-session state that shows the faint mark (GW11).
struct GlanceEntries: Equatable, Sendable {
    /// GW8: an idle session reads as done while its log was written within the last 10 minutes.
    static let doneWindowMs: Double = 10 * 60_000
    /// GW12: the strip shows at most this many entries, then `+N`.
    static let shownLimit = 6

    static let empty = GlanceEntries(all: [])

    let all: [GlanceEntry]

    init(report: CoreActivityReport) {
        all = report.sessions.compactMap(GlanceEntry.init).sorted(by: GlanceEntry.precedes)
    }

    private init(all: [GlanceEntry]) {
        self.all = all
    }

    /// These entries in `previous`'s order, for while the pointer is on the widget: a report every few seconds brings new
    /// write ages, and re-sorting by them would move rows under the pointer. The GW-R3 groups keep their order. Within a
    /// group, the entries that were already in that group keep their relative order from `previous`; the others (new
    /// sessions, and sessions whose state changed) follow at the group's end in GW-R3 order. Sessions gone from this report
    /// drop out. Each entry carries this report's values.
    func keepingOrder(of previous: GlanceEntries) -> GlanceEntries {
        var rank: [String: (index: Int, state: GlanceState)] = [:]
        for (index, entry) in previous.all.enumerated() where rank[entry.id] == nil {
            rank[entry.id] = (index, entry.state)
        }
        var merged: [GlanceEntry] = []
        merged.reserveCapacity(all.count)
        for state in GlanceState.allCases {
            let group = all.filter { $0.state == state }
            let kept = group.compactMap { entry in rank[entry.id].flatMap { $0.state == state ? (entry, $0.index) : nil } }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
            let keptIDs = Set(kept.map(\.id))
            merged += kept + group.filter { !keptIDs.contains($0.id) }
        }
        return GlanceEntries(all: merged)
    }

    var shown: [GlanceEntry] { Array(all.prefix(Self.shownLimit)) }
    /// The `N` of `+N`; 0 means no overflow mark.
    var overflow: Int { max(0, all.count - Self.shownLimit) }
    var isEmpty: Bool { all.isEmpty }
}
