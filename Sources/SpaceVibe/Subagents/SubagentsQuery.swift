import Foundation

/// The filter fields of the Subagents tab (V5-R64). `Can touch` is left out: the inventory carries no tools for a subagent (G1).
/// `Unmeasurable` is offered because the engine reports it (a CLI with no logs to count from). No CLI field: the spine is already
/// banded by CLI presence (D70).
enum SubagentsFilterField: String, FilterFieldKind {
    case status, owner

    var title: String {
        switch self {
        case .status: "Status"
        case .owner: "Owner"
        }
    }

    /// The first words of a chip: `Status is`, `Owner is`.
    var chipTitle: String { "\(title) is" }

    var values: [FilterValue] {
        switch self {
        case .status: [FilterValue("neverRan", "Never ran"), FilterValue("unmeasurable", "Unmeasurable")]
        case .owner: [FilterValue("mine", "Mine"), FilterValue("plugin", "Plugin")]
        }
    }
}

typealias SubagentsFilter = PickFilter<SubagentsFilterField>

/// `Group: <field>` in the spine card's header. `Model` is left out (G1).
enum SubagentsGroup: String, CaseIterable, Sendable {
    case presence, none

    var title: String {
        switch self {
        case .presence: "CLI presence"
        case .none: "None"
        }
    }
}

/// The facts of one subagent row that the tab, its Answer and its card share (V5-R63, V5-R64). A subagent is a `LoadoutRow` of
/// kind `agent`; its usage cells read exactly as a skill's (`SkillUsage`), so the states are the Skills tab's.
extension LoadoutRow {
    /// Never ran, and not a file too new for a session to have used it: the warning triangle, and the Answer's problem.
    var isUnused: Bool { SkillsQuery.holdsTriangle(self) }
}

/// The Subagents spine as the head's Filter and the card's Group describe it, applied to the global subagents. Pure: a test
/// gives rows, a view reads `layout`.
struct SubagentsQuery: Equatable, Sendable {
    var filter = SubagentsFilter()
    var group = SubagentsGroup.presence

    /// One band of the spine, or the one headless group of a flat list.
    struct Group: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        var rows: [LoadoutRow]
        /// Holds a never-ran subagent: its band comes first and opens by default (V5-R55).
        var holdsProblem: Bool
    }

    struct Layout: Equatable, Sendable {
        var groups: [Group]
        var rows: [LoadoutRow] { groups.flatMap(\.rows) }
        var isGrouped: Bool
    }

    func layout(_ rows: [LoadoutRow]) -> Layout {
        let ordered = rows.filter(matches).sorted(by: Self.rank)
        func band(_ id: String, _ title: String, _ rows: [LoadoutRow]) -> Group? {
            rows.isEmpty ? nil : Group(id: id, title: title, rows: rows, holdsProblem: rows.contains(where: \.isUnused))
        }
        switch group {
        case .none:
            return Layout(groups: [band("flat", "", ordered)].compactMap { $0 }, isGrouped: false)
        case .presence:
            let bands = ([band("presence:both", "In both", ordered.filter { $0.presentCLIs.count == 2 })]
                + CLICatalog.current.inventoryCLIs.map { cli in
                    band("presence:\(cli.rawValue)", "\(cli.label) only", ordered.filter { $0.presentCLIs == [cli] })
                }).compactMap { $0 }
            // Bands that hold a problem come first, in their usual order.
            return Layout(groups: bands.filter(\.holdsProblem) + bands.filter { !$0.holdsProblem }, isGrouped: true)
        }
    }

    /// Never-ran subagents first, then the most sessions, then by name.
    static func rank(_ a: LoadoutRow, _ b: LoadoutRow) -> Bool {
        if a.isUnused != b.isUnused { return a.isUnused }
        let x = a.skillUsage.sessions ?? -1, y = b.skillUsage.sessions ?? -1
        if x != y { return x > y }
        let byName = a.name.localizedCaseInsensitiveCompare(b.name)
        return byName == .orderedSame ? a.key < b.key : byName == .orderedAscending
    }

    /// AND across fields, OR within one.
    func matches(_ row: LoadoutRow) -> Bool {
        SubagentsFilterField.allCases.allSatisfy { field in
            guard let picked = filter.picks[field], !picked.isEmpty else { return true }
            return picked.contains { Self.test(field, value: $0, row: row) }
        }
    }

    private static func test(_ field: SubagentsFilterField, value: String, row: LoadoutRow) -> Bool {
        switch field {
        case .status:
            let state = row.skillUsage.state
            return value == "neverRan" ? state == .neverRan : state == .unmeasurable
        case .owner:
            return value == "plugin" ? row.plugin != nil : row.plugin == nil
        }
    }
}

// MARK: The addable rule (V5-R63)

/// Which subagents the detail popover offers `Add to <CLI>` for (the `In one CLI only` card was dropped, D69).
struct SubagentsAddable: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        var id: String { row.key }
        let row: LoadoutRow
        /// The CLI the subagent is in, and the one it would be added to.
        let here: CLIID
        let target: CLIID
    }

    /// Rows with exactly one CLI whose other CLI is on this Mac (`detected`), that no plugin owns and that did not go unused:
    /// most sessions first, then by name.
    var entries: [Entry]

    init(_ rows: [LoadoutRow], detected: [CLIID]) {
        var entries: [Entry] = []
        for row in rows {
            guard row.presentCLIs.count == 1, let here = row.presentCLIs.first else { continue }
            guard let target = row.copyTarget(from: here), row.plugin == nil, !row.isUnused, detected.contains(target),
                  LoadoutRows.copyPlan(row, to: target, events: [:]) != nil else { continue }
            entries.append(Entry(row: row, here: here, target: target))
        }
        self.entries = entries.sorted { a, b in
            let x = a.row.skillUsage.sessions ?? -1, y = b.row.skillUsage.sessions ?? -1
            if x != y { return x > y }
            return a.row.name.localizedCaseInsensitiveCompare(b.row.name) == .orderedAscending
        }
    }
}

// MARK: The Answer (V5-R53, V5-R63)

/// The Answer card's sentence, verdict and fixes, derived from the subagents in one place. The mock's "never ran and can run
/// Bash" needs each subagent's tools (G1), which the inventory does not carry, so the sentence says "never ran" and nothing more.
struct SubagentsAnswer: Equatable, Sendable {
    struct Verdict: Equatable, Sendable {
        let key: String
        let name: String
        let text: String
        let small: String?
        /// A plugin's subagent offers `Review` but no `Remove`.
        let offersRemove: Bool
    }

    /// Nil while the inventory or the usage scan has not finished: the card shows its skeleton. A scan that failed has
    /// finished: the card says the counts are missing.
    let sentence: String?
    let verdict: Verdict?
    /// Never-ran subagents beyond the one named: "N more are marked in the list."
    let more: Int

    static func of(_ rows: [LoadoutRow], isLoaded: Bool, detected: [CLIID], since: String? = nil, scanFailed: Bool = false) -> SubagentsAnswer {
        guard isLoaded, !rows.isEmpty, !rows.contains(where: { $0.skillUsage.state == .loading }) else {
            let uncounted = isLoaded && !rows.isEmpty && scanFailed
            return SubagentsAnswer(sentence: uncounted ? "Usage could not be counted." : nil, verdict: nil, more: 0)
        }
        let unused = rows.filter(\.isUnused).sorted(by: SubagentsQuery.rank)
        guard let first = unused.first else {
            let allRan = rows.allSatisfy { $0.skillUsage.state == .ran }
            return SubagentsAnswer(sentence: allRan ? "Every subagent has run." : "Nothing needs your attention.", verdict: nil, more: 0)
        }
        let sentence = "\(unused.count) \(unused.count == 1 ? "subagent" : "subagents") never ran."
        return SubagentsAnswer(sentence: sentence, verdict: SubagentsWording.verdict(for: first, detected: detected, since: since), more: unused.count - 1)
    }
}
