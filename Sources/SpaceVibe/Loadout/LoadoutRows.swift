import Foundation

/// Pure logic of the Loadout screen: rows from the core's `loadout.rows`, scope, sort, tags, copy plan. No UI and no disk access.
/// Usage cells, chip counts and row flags come from the core; grouping rows by key, sorting and labels are done here.
enum LoadoutRows {
    static let globalScope = "global"

    /// `~` for the home folder so a command or path reads short. Only when the Claude folder sits directly in the home folder
    /// (the default); with a custom `CLAUDE_CONFIG_DIR` nothing is abbreviated rather than guessing.
    static func home(roots: [String: String]) -> String? {
        guard let claude = roots[CoreCLI.claude.rawValue], claude.hasSuffix("/.claude") else { return nil }
        let home = String(claude.dropLast("/.claude".count))
        return home.isEmpty ? nil : home
    }

    static func shorten(_ text: String, home: String?) -> String {
        guard let home else { return text }
        return text.replacingOccurrences(of: "\(home)/", with: "~/")
    }

    static func memberName(_ hook: CoreInventoryHook) -> String {
        guard let matcher = hook.matcher, !matcher.isEmpty else { return hook.event }
        return "\(hook.event) \u{00B7} \(matcher)"
    }

    /// Groups items and hooks by row key and sorts: most runs first, then by name.
    static func build(_ snapshot: CoreLoadoutRows, home: String?) -> [LoadoutRow] {
        var order: [String] = []
        var members: [String: [CoreCLI: LoadoutMember]] = [:]
        func add(_ member: LoadoutMember, key: String) {
            if members[key] == nil { order.append(key) }
            // The last member per CLI and key, as the core builds the cells from: the row's actions and its cell
            // then describe the same file.
            members[key, default: [:]][member.cli] = member
        }
        for item in snapshot.items { add(.item(item), key: item.key) }
        for hook in snapshot.hooks { add(.hook(hook), key: hook.key) }

        let rows = order.compactMap { key -> LoadoutRow? in
            guard let group = members[key], let first = group[.claude] ?? group[.codex] else { return nil }
            let present = CoreCLI.allCases.compactMap { group[$0] }
            let cells = first.cells ?? CoreCells(
                claude: group[.claude] == nil ? .missing : .pending(reason: "Usage scan has not finished"),
                codex: group[.codex] == nil ? .missing : .pending(reason: "Usage scan has not finished")
            )
            var name = ""
            var detail = ""
            var kind = LoadoutKind.skill
            var project: String?
            switch first {
            case .item(let item):
                kind = LoadoutKind(item.kind)
                name = item.name
                project = item.project
                detail = present.compactMap { member -> String? in
                    if case .item(let other) = member, !other.description.isEmpty { return other.description }
                    return nil
                }.first ?? ""
            case .hook(let hook):
                kind = .hook
                name = memberName(hook)
                project = hook.project
                detail = shorten(hook.command, home: home)
            }
            let owners = present.map(\.owner)
            let plugin = owners.allSatisfy { $0 != "user" && $0 != "link" } ? owners.first : nil
            var errors = 0
            var runs = 0
            for cli in CoreCLI.allCases {
                if case .counted(let counted, _, let failed) = cells[cli] {
                    runs += counted
                    errors += failed ?? 0
                }
            }
            return LoadoutRow(
                key: key, kind: kind, project: project, members: group, cells: cells,
                flags: snapshot.rowFlags[key] ?? CoreRowFlags(one: false, neverRan: false, dead: false),
                name: name, detail: detail, plugin: plugin, errors: errors, runs: runs, addedNote: addedNote(cells)
            )
        }
        return rows.sorted { a, b in
            if a.runs != b.runs { return a.runs > b.runs }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// A short tag when a cell says the item is new, so a zero is not read as "never ran".
    static func addedNote(_ cells: CoreCells) -> String? {
        for cli in CoreCLI.allCases {
            guard case .pending(let reason) = cells[cli] else { continue }
            if reason.hasPrefix("Added in") { return "added recently" }
            if reason.hasPrefix("Added after") { return "added after the last log" }
        }
        return nil
    }

    static func inScope(_ rows: [LoadoutRow], scope: String) -> [LoadoutRow] {
        rows.filter { scope == globalScope ? $0.project == nil : $0.project == scope }
    }

    static func section(_ rows: [LoadoutRow], _ kind: LoadoutKind) -> [LoadoutRow] {
        rows.filter { $0.kind == kind }
    }

    /// The bar scale of each kind, taken before the chip filter so a bar keeps its width when a chip is pressed.
    static func maxRuns(_ rows: [LoadoutRow]) -> [LoadoutKind: Int] {
        var out: [LoadoutKind: Int] = [:]
        for row in rows {
            for cli in CoreCLI.allCases {
                if case .counted(let runs, _, _) = row.cells[cli] { out[row.kind] = max(out[row.kind] ?? 0, runs) }
            }
        }
        return out
    }

    /// Global first, then every project that has visible config, named by its folder; two projects with the same folder name
    /// get their parent folder too.
    static func scopes(_ snapshot: CoreLoadoutRows) -> [LoadoutScope] {
        let paths = Set(snapshot.items.compactMap(\.project) + snapshot.hooks.compactMap(\.project)).sorted()
        func parts(_ path: String) -> [Substring] { path.split(separator: "/") }
        var taken: [Substring: Int] = [:]
        for path in paths { taken[parts(path).last ?? "", default: 0] += 1 }
        func label(_ path: String) -> String {
            let all = parts(path)
            guard let last = all.last else { return path }
            return taken[last] == 1 ? String(last) : all.suffix(2).joined(separator: "/")
        }
        return [LoadoutScope(value: globalScope, label: "Global")] + paths.map { LoadoutScope(value: $0, label: label($0)) }
    }

    /// The id of the item to copy when `to`'s cell is empty, or nil when no copy may be offered: project configuration is
    /// read-only here, a dead hook is not worth copying, and a hook goes only into Claude Code, never into Codex (Codex
    /// loading a hook SpaceVibe wrote is unverified), and only when Claude knows the event.
    static func copyPlan(_ row: LoadoutRow, to: CoreCLI, events: [String: [String]]) -> String? {
        guard row.project == nil, !row.flags.dead, row.cells[to] == .missing, let source = row.members[to.other] else { return nil }
        if case .hook(let hook) = source {
            guard to == .claude, events[to.rawValue]?.contains(hook.event) == true else { return nil }
        }
        return source.id
    }

    /// Why a row with nothing removable cannot be changed.
    static func readOnlyReason(_ row: LoadoutRow) -> String {
        row.project != nil ? "Read-only: project configuration" : "Read-only: owned by a plugin"
    }
}

// MARK: Skills (V5-R21 to V5-R33)

/// What one CLI's usage cell says about a skill. The core's `pending` cell is three different facts and the Skills tab keeps
/// them apart (`core/internal/inventory/attach-usage.go`): the scan is still running, the CLI has no logs to scan, or the file
/// changed too recently for a session to have used it (G7: the file's modification time, not a creation time).
enum SkillCell: Equatable, Sendable {
    /// Not installed in that CLI.
    case missing
    /// "Usage scan has not finished": no claim either way.
    case loading
    /// "No logs scanned for this CLI yet": SpaceVibe cannot count sessions there.
    case noLogs
    /// Sessions that used the skill, and the UTC day of the last one (`YYYY-MM-DD`; a skill's log record has no time of day).
    case sessions(Int, last: String?)
    /// Zero sessions, and the file changed recently enough that no session may have used it yet.
    case added(Added)

    enum Added: Equatable, Sendable {
        /// "Added in the last 24 hours".
        case lastDay
        /// "Added after the newest log".
        case afterNewestLog
    }
}

extension SkillCell {
    init(_ cell: CoreUsageCell) {
        switch cell {
        case .missing: self = .missing
        case .counted(let runs, let last, _): self = .sessions(runs, last: last)
        case .unmeasurable: self = .noLogs
        case .pending(let reason):
            if reason.hasPrefix("Added in") { self = .added(.lastDay) }
            else if reason.hasPrefix("Added after") { self = .added(.afterNewestLog) }
            else if reason.hasPrefix("No logs scanned") { self = .noLogs }
            else { self = .loading }
        }
    }
}

/// What a skill row says about usage, from the cells of the CLIs that have it. One definition for the Status filter, the
/// warning slot, the group bands and the pane (the core's `rowFlags.neverRan` skips a pending cell, so it is not used).
struct SkillUsage: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// At least one session used it.
        case ran
        /// No session used it, in a CLI that was counted or where the file is too new to say.
        case neverRan
        /// No counted CLI and no log to count from.
        case unmeasurable
        /// The scan has not finished.
        case loading
    }

    let cells: [CoreCLI: SkillCell]

    /// The CLIs that have the skill, Claude Code first.
    var present: [CoreCLI] { CoreCLI.allCases.filter { cells[$0].map { $0 != .missing } ?? false } }

    var state: State {
        let kinds = present.compactMap { cells[$0] }
        if kinds.contains(.loading) { return .loading }
        if kinds.contains(where: { if case .sessions(let n, _) = $0 { n > 0 } else { false } }) { return .ran }
        let measured = kinds.contains { cell in
            switch cell {
            case .sessions, .added: true
            default: false
            }
        }
        return measured ? .neverRan : .unmeasurable
    }

    /// Sessions over every CLI that counted them; nil while the number is not known.
    var sessions: Int? {
        switch state {
        case .ran, .neverRan: present.reduce(0) { total, cli in
            if case .sessions(let n, _) = cells[cli] { total + n } else { total }
        }
        case .unmeasurable, .loading: nil
        }
    }

    func sessions(in cli: CoreCLI) -> Int? {
        if case .sessions(let n, _) = cells[cli] { n } else { nil }
    }

    /// The UTC day of the latest session in any CLI.
    var lastRan: String? {
        present.compactMap { cli -> String? in
            if case .sessions(_, let last) = cells[cli] { last } else { nil }
        }.max()
    }

    /// Set while the skill never ran and a CLI's file is new: the clock and a quiet note, not the warning triangle.
    var added: SkillCell.Added? {
        guard state == .neverRan else { return nil }
        return present.compactMap { cli -> SkillCell.Added? in
            if case .added(let note) = cells[cli] { note } else { nil }
        }.first
    }

    /// The CLIs whose cell has no logs behind it.
    var withoutLogs: [CoreCLI] { present.filter { cells[$0] == .noLogs } }
}

extension LoadoutRow {
    var skillUsage: SkillUsage {
        SkillUsage(cells: Dictionary(uniqueKeysWithValues: CoreCLI.allCases.map { ($0, SkillCell(cells[$0])) }))
    }

    /// The CLIs that have this row, from its members (a row with no member at all has none).
    var presentCLIs: [CoreCLI] { CoreCLI.allCases.filter { members[$0] != nil } }
}

extension LoadoutRows {
    /// The CLIs the logo strip lists (V5-R24): the ones `limits.read` does not call `notInstalled`; before a reading exists, the
    /// ones that hold at least one skill, agent or hook. Claude Code first.
    static func detectedCLIs(limits: [CoreLimitsEntry], rows: [LoadoutRow]) -> [CoreCLI] {
        CoreCLI.allCases.filter { cli in
            if let entry = limits.first(where: { $0.cli == CoreLimitsCLI(cli) }) { return entry.state != .notInstalled }
            return rows.contains { $0.members[cli] != nil }
        }
    }

    /// What pressing the logo of `cli` on a skill row does (V5-R25): a plugin's or a project's skill is read-only; the only copy
    /// is removed from the pane, not toggled (D53); a dim logo adds only where a copy is allowed.
    static func logoMode(_ row: LoadoutRow, cli: CoreCLI, events: [String: [String]]) -> LogoToggleMode {
        guard row.plugin == nil, row.project == nil else { return .readOnly }
        if let member = row.members[cli] {
            guard member.removable else { return .readOnly }
            return row.presentCLIs.count == 1 ? .onlyCopy : .toggles
        }
        return copyPlan(row, to: cli, events: events) == nil ? .readOnly : .toggles
    }

    /// The `loadout.copyToOther` and `loadout.removeItem` calls a set of skills needs, and how many rows were left out.
    /// A plugin's skill, a project's, a copy that is not removable and (for a removal from one CLI) the only copy are skipped.
    struct SkillWrites: Equatable, Sendable {
        enum Step: Equatable, Sendable {
            case copy(id: String, to: CoreCLI)
            case remove(id: String, from: CoreCLI)
        }

        var steps: [Step] = []
        /// Rows that take part in at least one step.
        var rows = 0
        var skipped = 0
    }

    static func addWrites(_ rows: [LoadoutRow], to cli: CoreCLI, events: [String: [String]]) -> SkillWrites {
        var out = SkillWrites()
        for row in rows where row.members[cli] == nil {
            guard row.plugin == nil, let id = copyPlan(row, to: cli, events: events) else { out.skipped += 1; continue }
            out.steps.append(.copy(id: id, to: cli))
            out.rows += 1
        }
        return out
    }

    /// Removes each row from `cli`, or from every CLI that has it when `cli` is nil (the pane's and the bar's `Remove`).
    static func removeWrites(_ rows: [LoadoutRow], from cli: CoreCLI?) -> SkillWrites {
        var out = SkillWrites()
        for row in rows {
            guard row.plugin == nil, row.project == nil else { out.skipped += 1; continue }
            let members = row.members.values.filter { cli == nil || $0.cli == cli }
            if let cli, row.presentCLIs == [cli] { out.skipped += 1; continue }
            let removable = members.filter(\.removable).sorted { $0.cli.rawValue < $1.cli.rawValue }
            guard !removable.isEmpty else { out.skipped += 1; continue }
            out.steps += removable.map { .remove(id: $0.id, from: $0.cli) }
            out.rows += 1
        }
        return out
    }
}

/// Everything the screen shows, built off the main actor from one `loadout.rows` read.
struct LoadoutData: Sendable {
    var rows: [LoadoutRow]
    var scopes: [LoadoutScope]
    var countsByScope: [String: CoreFilterCounts]
    var problems: [String]
    var events: [String: [String]]
    var globalCount: Int
    /// The home folder as `~` abbreviates it, when the Claude folder sits directly in it.
    var home: String?

    static func build(raw: CoreLoadoutRows) -> LoadoutData {
        let home = LoadoutRows.home(roots: raw.roots)
        return LoadoutData(
            rows: LoadoutRows.build(raw, home: home),
            scopes: LoadoutRows.scopes(raw),
            countsByScope: raw.countsByScope,
            // The core sends the sentences with absolute paths; the home folder is shortened here.
            problems: raw.problems.map { LoadoutRows.shorten($0, home: home) },
            events: raw.events,
            globalCount: raw.countsByScope[LoadoutRows.globalScope]?.all ?? 0,
            home: home
        )
    }
}
