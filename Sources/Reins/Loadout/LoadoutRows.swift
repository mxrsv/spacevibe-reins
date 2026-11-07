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
    /// loading a hook Reins wrote is unverified), and only when Claude knows the event.
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

/// Everything the screen shows, built off the main actor from one `loadout.rows` read.
struct LoadoutData: Sendable {
    var rows: [LoadoutRow]
    var scopes: [LoadoutScope]
    var countsByScope: [String: CoreFilterCounts]
    var problems: [String]
    var events: [String: [String]]
    var globalCount: Int

    static func build(raw: CoreLoadoutRows) -> LoadoutData {
        let home = LoadoutRows.home(roots: raw.roots)
        return LoadoutData(
            rows: LoadoutRows.build(raw, home: home),
            scopes: LoadoutRows.scopes(raw),
            countsByScope: raw.countsByScope,
            // The core sends the sentences with absolute paths; the home folder is shortened here.
            problems: raw.problems.map { LoadoutRows.shorten($0, home: home) },
            events: raw.events,
            globalCount: raw.countsByScope[LoadoutRows.globalScope]?.all ?? 0
        )
    }
}
