import Foundation

// MARK: Facts of a hook row

/// What one CLI's usage cell says about a hook. A hook's `counted.runs` are runs (S2), not sessions, and Codex logs none
/// (`unmeasurable`, S5), so these cells are not `SkillCell`s: `Never ran` is a Claude Code hook counted at zero, `Unmeasurable`
/// is a hook nothing can count.
enum HookRun: Equatable, Sendable {
    /// The hook is not in that CLI.
    case missing
    /// The usage scan has not finished.
    case loading
    /// The settings file changed recently enough that no run may have been logged yet.
    case newlyAdded
    /// No log to count from: Codex never logs a hook, and Claude Code may have none yet.
    case unmeasurable
    case neverRan
    case ran(Int, last: String?)

    init(_ cell: CoreUsageCell) {
        switch cell {
        case .missing: self = .missing
        case .unmeasurable: self = .unmeasurable
        case .counted(let runs, let last, _): self = runs > 0 ? .ran(runs, last: last) : .neverRan
        case .pending(let reason):
            if reason.hasPrefix("Added") { self = .newlyAdded }
            else if reason.hasPrefix("No logs scanned") { self = .unmeasurable }
            else { self = .loading }
        }
    }

    /// A run count SpaceVibe can stand behind (a counted cell, zero or not, or a settings file too new to say).
    var isMeasured: Bool {
        switch self {
        case .ran, .neverRan, .newlyAdded: true
        case .missing, .loading, .unmeasurable: false
        }
    }
}

extension LoadoutRow {
    /// The hook behind each CLI's copy of the row.
    var hookMembers: [CoreCLI: CoreInventoryHook] {
        var out: [CoreCLI: CoreInventoryHook] = [:]
        for (cli, member) in members { if case .hook(let hook) = member { out[cli] = hook } }
        return out
    }

    /// The row's hook, Claude Code's first: its event, matcher and command are the row's (the key is event plus command).
    var firstHook: CoreInventoryHook? { CoreCLI.allCases.lazy.compactMap { hookMembers[$0] }.first }

    var hookEvent: String { firstHook?.event ?? "" }

    var hookMatcher: String? {
        guard let matcher = firstHook?.matcher, !matcher.isEmpty else { return nil }
        return matcher
    }

    /// The inventory gives a hook no name, only its command (G2): the name is its script's file name, else the command itself.
    var hookTitle: String {
        guard let path = firstHook?.paths.first, !path.isEmpty else { return detail.isEmpty ? name : detail }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// A script that a copy of this hook names is gone: the hook cannot run.
    var isDeadHook: Bool { hookMembers.values.contains(where: \.dead) }

    func hookRun(in cli: CoreCLI) -> HookRun { HookRun(cells[cli]) }

    /// The CLIs whose run count is real.
    var measuredCLIs: [CoreCLI] { presentCLIs.filter { hookRun(in: $0).isMeasured } }

    /// Nothing can count this hook's runs (a Codex-only hook): the neutral clock in the warning slot.
    var isUnmeasurable: Bool {
        let runs = presentCLIs.map { hookRun(in: $0) }
        return !runs.isEmpty && runs.allSatisfy { $0 == .unmeasurable }
    }
}

// MARK: Filter

/// The Filter fields of the Hooks tab (V5-R66). `Handler` is left out: the inventory carries no handler kind and the core lists
/// `command` hooks only (G2). `Event` has no fixed values: they are the events the inventory lists, so the menu reads them from
/// the model.
enum HooksFilterField: String, FilterFieldKind {
    case cli, status, event

    var title: String {
        switch self {
        case .cli: "CLI presence"
        case .status: "Status"
        case .event: "Event"
        }
    }

    /// The first words of a chip.
    var chipTitle: String {
        switch self {
        case .cli: "In"
        case .status: "Status is"
        case .event: "Event is"
        }
    }

    /// `Missing in Codex` is offered only while SpaceVibe writes hooks into Codex (`LoadoutRows.codexTakesHooks`), else it could
    /// never match.
    var values: [FilterValue] {
        switch self {
        case .cli:
            [FilterValue("both", "Both CLIs", chip: "Both CLIs"), FilterValue("claude", "Claude Code only", chip: "Claude Code only"),
             FilterValue("codex", "Codex only", chip: "Codex only")]
        case .status:
            [FilterValue("cantRun", "Can't run")]
                + (LoadoutRows.codexTakesHooks ? [FilterValue("missing", "Missing in Codex")] : [])
                + [FilterValue("cantCopy", "Can't copy to Codex")]
        case .event: []
        }
    }
}

typealias HooksFilter = PickFilter<HooksFilterField>

// MARK: Context

/// What the hooks are read against: the events each CLI has, the CLIs on this Mac, and whether SpaceVibe writes hooks into
/// Codex. The one copy rule (`LoadoutRows.hookCopyBlock`) is asked through here, so the logos, `a`, the detail, both small cards
/// and the Answer all get the same answer.
struct HooksContext: Equatable, Sendable {
    var events: [String: [String]]
    var detected: [CoreCLI]
    var codexTakesHooks = LoadoutRows.codexTakesHooks

    var codexInstalled: Bool { detected.contains(.codex) }

    /// Why `row` cannot go to `cli`, or nil when it can (or is there already).
    func block(_ row: LoadoutRow, to cli: CoreCLI) -> LoadoutRows.HookCopyBlock? {
        row.members[cli] == nil
            ? LoadoutRows.hookCopyBlock(row, to: cli, events: events, detected: detected, codexTakesHooks: codexTakesHooks) : nil
    }

    private func claudeOnly(_ row: LoadoutRow) -> Bool { row.members[.claude] != nil && row.members[.codex] == nil && codexInstalled }

    /// Claude Code runs it, Codex doesn't, and Codex could take it.
    func isMissingInCodex(_ row: LoadoutRow) -> Bool { claudeOnly(row) && block(row, to: .codex) == nil }

    /// Claude Code runs it, Codex doesn't, and the rule says why Codex can't take it.
    func isCantCopyToCodex(_ row: LoadoutRow) -> Bool { claudeOnly(row) && block(row, to: .codex) != nil }
}

// MARK: Query

/// The Hooks spine as the head's Filter describes it: one band per event. Pure: a test gives rows and a context, a view reads
/// `layout`.
struct HooksQuery: Equatable, Sendable {
    var filter = HooksFilter()

    struct Band: Identifiable, Equatable, Sendable {
        let id: String
        let event: String
        /// The one CLI that has this event; nil when both have it (V5-R65).
        let lead: CoreCLI?
        var rows: [LoadoutRow]
        /// Holds a hook that cannot run: the danger glyph, first in the list, open by default.
        var holdsProblem: Bool
    }

    struct Layout: Equatable, Sendable {
        var bands: [Band]
        var rows: [LoadoutRow] { bands.flatMap(\.rows) }
    }

    /// Every event a hook or a CLI has, in lifecycle order: Claude Code's list, then Codex's events it lacks, then the events only
    /// a hook names (alphabetical, so a hook on an event missing from both lists still gets its band, never dropped).
    static func lifecycle(events: [String: [String]], rows: [LoadoutRow]) -> [String] {
        var order: [String] = []
        for event in (events[CoreCLI.claude.rawValue] ?? []) + (events[CoreCLI.codex.rawValue] ?? []) where !order.contains(event) { order.append(event) }
        let extra = Set(rows.map(\.hookEvent)).subtracting(order).filter { !$0.isEmpty }.sorted()
        return order + extra
    }

    /// The CLIs that have `event`: those whose list names it and those that have a hook on it.
    static func clis(of event: String, events: [String: [String]], rows: [LoadoutRow]) -> Set<CoreCLI> {
        var out = Set(CoreCLI.allCases.filter { events[$0.rawValue]?.contains(event) == true })
        for row in rows where row.hookEvent == event { out.formUnion(row.presentCLIs) }
        return out
    }

    /// The events the Filter's `Event` field offers: the ones that have a hook, in lifecycle order.
    static func eventValues(events: [String: [String]], rows: [LoadoutRow]) -> [FilterValue] {
        let used = Set(rows.map(\.hookEvent))
        return lifecycle(events: events, rows: rows).filter(used.contains).map { FilterValue($0, $0) }
    }

    func layout(_ rows: [LoadoutRow], context: HooksContext) -> Layout {
        let all = Self.lifecycle(events: context.events, rows: rows)
        let shown = rows.filter { matches($0, context: context) }
        func clis(_ event: String) -> Set<CoreCLI> { Self.clis(of: event, events: context.events, rows: rows) }
        // Shared events in lifecycle order, then Claude Code's own, then Codex's own (V5-R65).
        let ordered = all.filter { clis($0).count == 2 } + all.filter { clis($0) == [.claude] } + all.filter { clis($0) == [.codex] }
        let bands = ordered.compactMap { event -> Band? in
            let inBand = shown.filter { $0.hookEvent == event }.sorted(by: Self.rank)
            guard !inBand.isEmpty else { return nil }
            let owners = clis(event)
            return Band(id: "event:\(event)", event: event, lead: owners.count == 1 ? owners.first : nil, rows: inBand,
                        holdsProblem: inBand.contains(where: \.isDeadHook))
        }
        return Layout(bands: bands.filter(\.holdsProblem) + bands.filter { !$0.holdsProblem })
    }

    /// Hooks that cannot run first, then by name.
    static func rank(_ a: LoadoutRow, _ b: LoadoutRow) -> Bool {
        if a.isDeadHook != b.isDeadHook { return a.isDeadHook }
        let byName = a.hookTitle.localizedCaseInsensitiveCompare(b.hookTitle)
        return byName == .orderedSame ? a.key < b.key : byName == .orderedAscending
    }

    /// AND across fields, OR within one.
    func matches(_ row: LoadoutRow, context: HooksContext) -> Bool {
        HooksFilterField.allCases.allSatisfy { field in
            guard let picked = filter.picks[field], !picked.isEmpty else { return true }
            return picked.contains { Self.test(field, value: $0, row: row, context: context) }
        }
    }

    private static func test(_ field: HooksFilterField, value: String, row: LoadoutRow, context: HooksContext) -> Bool {
        switch field {
        case .cli:
            switch value {
            case "both": row.presentCLIs.count == 2
            case "claude": row.presentCLIs == [.claude]
            default: row.presentCLIs == [.codex]
            }
        case .status:
            switch value {
            case "cantRun": row.isDeadHook
            case "missing": context.isMissingInCodex(row)
            default: context.isCantCopyToCodex(row)
            }
        case .event:
            row.hookEvent == value
        }
    }
}

// MARK: The two small cards (V5-R65)

/// `Can't copy to Codex`: the Claude Code hooks Codex lacks that the rule keeps from it, and why, in the order the `Why`
/// popover explains the reasons.
struct HooksCantCopy: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        var id: String { row.key }
        let row: LoadoutRow
        let block: LoadoutRows.HookCopyBlock
    }

    var entries: [Entry]

    init(_ rows: [LoadoutRow], context: HooksContext) {
        entries = rows.filter(context.isCantCopyToCodex).compactMap { row in
            context.block(row, to: .codex).map { Entry(row: row, block: $0) }
        }.sorted { a, b in
            let x = HooksWording.order(a.block), y = HooksWording.order(b.block)
            return x != y ? x < y : HooksQuery.rank(a.row, b.row)
        }
    }

    /// The card is dropped when it has no row.
    var isEmpty: Bool { entries.isEmpty }
}

/// `Missing in Codex`: the Claude Code hooks Codex lacks and could take.
struct HooksMissing: Equatable, Sendable {
    var rows: [LoadoutRow]

    init(_ rows: [LoadoutRow], context: HooksContext) {
        self.rows = rows.filter(context.isMissingInCodex).sorted(by: HooksQuery.rank)
    }

    var isEmpty: Bool { rows.isEmpty }
}

// MARK: The Answer (V5-R53, V5-R65)

/// The Answer card's sentence and fixes, derived from the hooks in one place: "N hooks can't run, M are missing in Codex." (or
/// one half, or "Nothing needs you."), a row per hook that cannot run (the first `shownDead`, then "N more are marked in the
/// list", V5-R53) and one row that copies the missing ones to Codex.
struct HooksAnswer: Equatable, Sendable {
    static let shownDead = 3

    /// Nil while the inventory has not been read: the card shows its skeleton.
    let sentence: String?
    let dead: [LoadoutRow]
    /// Hooks that cannot run beyond the ones listed.
    let more: Int
    let missing: [LoadoutRow]

    static func of(_ rows: [LoadoutRow], isLoaded: Bool, context: HooksContext, notShown: Bool = false) -> HooksAnswer {
        // A hook that cannot run, or that Codex lacks, is known from the config alone: the Answer does not wait for the usage scan.
        guard isLoaded else {
            return HooksAnswer(sentence: nil, dead: [], more: 0, missing: [])
        }
        // The core lists `command` hooks only: when it says it left others out, "none" would be false.
        guard !rows.isEmpty else { return HooksAnswer(sentence: notShown ? "No hooks to show." : "No hooks yet.", dead: [], more: 0, missing: []) }
        let dead = rows.filter(\.isDeadHook).sorted(by: HooksQuery.rank)
        let missing = HooksMissing(rows, context: context).rows
        var parts: [String] = []
        if !dead.isEmpty { parts.append("\(dead.count) \(dead.count == 1 ? "hook" : "hooks") can't run") }
        if !missing.isEmpty {
            parts.append(dead.isEmpty ? "\(missing.count) \(missing.count == 1 ? "hook is" : "hooks are") missing in Codex"
                : "\(missing.count) \(missing.count == 1 ? "is" : "are") missing in Codex")
        }
        return HooksAnswer(sentence: parts.isEmpty ? "Nothing needs you." : parts.joined(separator: ", ") + ".",
                           dead: Array(dead.prefix(shownDead)), more: max(0, dead.count - shownDead), missing: missing)
    }
}
