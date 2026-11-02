import Foundation
import ReinsCore

/// Pure logic of the Loadout screen: rows from an inventory, scope, filter, sort, tags, copy plan. No UI and no disk access.
enum LoadoutRows {
    static let globalScope = "global"

    /// `~` for the home folder so a command or path reads short. Only when the Claude folder sits directly in the home folder
    /// (the default); with a custom `CLAUDE_CONFIG_DIR` nothing is abbreviated rather than guessing.
    static func home(roots: [String: String]) -> String? {
        guard let claude = roots[InventoryCLI.claude.rawValue], claude.hasSuffix("/.claude") else { return nil }
        let home = String(claude.dropLast("/.claude".count))
        return home.isEmpty ? nil : home
    }

    static func shorten(_ text: String, home: String?) -> String {
        guard let home else { return text }
        return text.replacingOccurrences(of: "\(home)/", with: "~/")
    }

    static func memberName(_ hook: InventoryHook) -> String {
        guard let matcher = hook.matcher, !matcher.isEmpty else { return hook.event }
        return "\(hook.event) \u{00B7} \(matcher)"
    }

    /// Groups items and hooks by row key and sorts: most runs first, then by name.
    static func build(_ snapshot: InventorySnapshot, home: String?) -> [LoadoutRow] {
        var order: [String] = []
        var members: [String: [InventoryCLI: LoadoutMember]] = [:]
        var filterRows: [String: [FilterRow]] = [:]
        func add(_ member: LoadoutMember, key: String, filter: FilterRow) {
            if members[key] == nil { order.append(key) }
            if members[key]?[member.cli] == nil { members[key, default: [:]][member.cli] = member }
            filterRows[key, default: []].append(filter)
        }
        for item in snapshot.items { add(.item(item), key: item.key, filter: FilterRow(item)) }
        for hook in snapshot.hooks { add(.hook(hook), key: hook.key, filter: FilterRow(hook)) }

        let rows = order.compactMap { key -> LoadoutRow? in
            guard let group = members[key], let first = group[.claude] ?? group[.codex] else { return nil }
            let present = InventoryCLI.allCases.compactMap { group[$0] }
            let counts = Inventory.filterCounts(filterRows[key] ?? [])
            let cells = first.cells ?? InventoryCells(
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
            for cli in InventoryCLI.allCases {
                if case .counted(let counted, _, let failed) = cells[cli] {
                    runs += counted
                    errors += failed ?? 0
                }
            }
            return LoadoutRow(
                key: key, kind: kind, project: project, members: group, cells: cells,
                flags: LoadoutFlags(one: counts.only.claude + counts.only.codex > 0, neverRan: counts.neverRan > 0, dead: counts.dead > 0),
                name: name, detail: detail, plugin: plugin, errors: errors, runs: runs, addedNote: addedNote(cells)
            )
        }
        return rows.sorted { a, b in
            if a.runs != b.runs { return a.runs > b.runs }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// A short tag when a cell says the item is new, so a zero is not read as "never ran".
    static func addedNote(_ cells: InventoryCells) -> String? {
        for cli in InventoryCLI.allCases {
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
            for cli in InventoryCLI.allCases {
                if case .counted(let runs, _, _) = row.cells[cli] { out[row.kind] = max(out[row.kind] ?? 0, runs) }
            }
        }
        return out
    }

    /// Global first, then every project that has visible config, named by its folder; two projects with the same folder name
    /// get their parent folder too.
    static func scopes(_ snapshot: InventorySnapshot) -> [LoadoutScope] {
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
    static func copyPlan(_ row: LoadoutRow, to: InventoryCLI, events: [String: [String]]) -> String? {
        guard row.project == nil, !row.flags.dead, row.cells[to].isMissing, let source = row.members[to.other] else { return nil }
        if case .hook(let hook) = source {
            guard to == .claude, events[to.rawValue]?.contains(hook.event) == true else { return nil }
        }
        return source.id
    }

    /// Why a row with nothing removable cannot be changed.
    static func readOnlyReason(_ row: LoadoutRow) -> String {
        row.project != nil ? "Read-only: project configuration" : "Read-only: owned by a plugin"
    }

    /// Dead, user-level hooks of one CLI that may be removed.
    static func deadHooks(_ rows: [LoadoutRow], cli: InventoryCLI) -> [LoadoutRow] {
        rows.filter { $0.project == nil && $0.flags.dead && $0.members[cli]?.removable == true }
    }
}

/// Everything the screen shows, built off the main actor from one inventory read and one usage state.
struct LoadoutData: Sendable {
    var rows: [LoadoutRow]
    var scopes: [LoadoutScope]
    var countsByScope: [String: FilterCounts]
    var problems: [String]
    var events: [String: [String]]
    var globalCount: Int

    static func build(raw: InventorySnapshot, usage: UsageInput) -> LoadoutData {
        let attached = Inventory.attachUsage(raw, usage: usage)
        let home = LoadoutRows.home(roots: attached.roots)
        let rows = LoadoutRows.build(attached, home: home)
        let scopes = LoadoutRows.scopes(attached)
        var counts: [String: FilterCounts] = [:]
        for scope in scopes {
            let project: String? = scope.value == LoadoutRows.globalScope ? nil : scope.value
            counts[scope.value] = Inventory.filterCounts(
                items: attached.items.filter { $0.project == project },
                hooks: attached.hooks.filter { $0.project == project }
            )
        }
        return LoadoutData(
            rows: rows, scopes: scopes, countsByScope: counts,
            problems: attached.problems.map { LoadoutRows.shorten($0, home: home) },
            events: attached.events,
            globalCount: counts[LoadoutRows.globalScope]?.all ?? 0
        )
    }
}
