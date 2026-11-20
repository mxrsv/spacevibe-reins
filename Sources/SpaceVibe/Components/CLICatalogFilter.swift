import Foundation

/// The one filter between the core's results and the pages (MC-R2, MC-R4): every per-CLI value of a CLI the catalog does not
/// show (an id `clis.list` did not return, or a CLI the owner turned off) is dropped here, so no page shows it and no
/// comparison counts it. A model applies it where it takes a result in; pages never filter by CLI themselves.
extension CLICatalog {
    func shown(_ report: CoreActivityReport) -> CoreActivityReport {
        var out = report
        out.sessions = report.sessions.filter { isShown($0.cli) }
        out.failures = report.failures.filter { isShown($0.cli) }
        out.unmeasurable = report.unmeasurable.filter { isShown($0.cli) }
        out.files = report.files.compactMap { file in
            var kept = file
            kept.clis = file.clis.filter(isShown)
            return kept.clis.isEmpty ? nil : kept
        }
        return out
    }

    func shown(_ limits: [CoreLimitsEntry]) -> [CoreLimitsEntry] { limits.filter { isShown($0.cli) } }

    func shown(_ usage: CoreUsageResult) -> CoreUsageResult {
        var out = usage
        out.totals = usage.totals.filter { isShown($0.cli) }
        out.sessions = usage.sessions.filter { isShown($0.cli) }
        out.windows = usage.windows.filter { isShown($0.cli) }
        return out
    }

    func shown(_ item: CoreInventoryItem) -> CoreInventoryItem {
        var out = item
        out.readBy = item.readBy.filter(isShown)
        out.cells = item.cells.map(shownCells)
        return out
    }

    func shown(_ hook: CoreInventoryHook) -> CoreInventoryHook {
        var out = hook
        out.cells = hook.cells.map(shownCells)
        return out
    }

    /// Items, hooks, cells, events and roots of the shown inventory CLIs only. The chip counts and row flags are the core's
    /// while it lists nothing the catalog hides; otherwise they are counted again over what is left, by the core's rule
    /// (`filterCounts`), so a hidden CLI's presence neither adds a row nor makes one "in one CLI only".
    func shown(_ rows: CoreLoadoutRows) -> CoreLoadoutRows {
        let keep = Set(inventoryCLIs)
        var out = rows
        out.items = rows.items.filter { keep.contains($0.cli) }.map(shown)
        out.hooks = rows.hooks.filter { keep.contains($0.cli) }.map(shown)
        out.events = rows.events.filter { keep.contains($0.cli) }
        out.roots = rows.roots.filter { keep.contains($0.cli) }
        guard Self.listedCLIs(rows).isSubset(of: keep) else {
            out.countsByScope = Self.countsByScope(items: out.items, hooks: out.hooks, clis: inventoryCLIs)
            out.rowFlags = Self.rowFlags(items: out.items, hooks: out.hooks, clis: inventoryCLIs)
            return out
        }
        return out
    }

    private func shownCells(_ cells: CoreCells) -> CoreCells { cells.filter { inventoryCLIs.contains($0) } }

    /// Every CLI a loadout read names: the items' and hooks' own, their cells' and the chip counts'.
    static func listedCLIs(_ rows: CoreLoadoutRows) -> Set<CLIID> {
        var out = Set(rows.items.map(\.cli) + rows.hooks.map(\.cli))
        for item in rows.items { out.formUnion(item.cells?.clis ?? []) }
        for hook in rows.hooks { out.formUnion(hook.cells?.clis ?? []) }
        for counts in rows.countsByScope.values { out.formUnion(counts.only.map(\.cli)) }
        return out
    }
}

// MARK: Counting again (the core's `FilterCountsOfRows`, `buildLoadoutRows`)

extension CLICatalog {
    /// One row for the counts: its key, its own CLI, whether it is a dead hook, and its cells.
    struct CountedRow {
        var key: String
        var cli: CLIID
        var dead: Bool
        var cells: CoreCells?
        var project: String?
    }

    static func countedRows(items: [CoreInventoryItem], hooks: [CoreInventoryHook]) -> [CountedRow] {
        items.map { CountedRow(key: $0.key, cli: $0.cli, dead: false, cells: $0.cells, project: $0.project) }
            + hooks.map { CountedRow(key: $0.key, cli: $0.cli, dead: $0.dead, cells: $0.cells, project: $0.project) }
    }

    /// The filter counts of every scope: `global`, and each project folder an item or a hook names. `clis` is the shown
    /// inventory CLIs in registry order, so `only` lists each of them, zero included, as the core does.
    static func countsByScope(items: [CoreInventoryItem], hooks: [CoreInventoryHook], clis: [CLIID]) -> [String: CoreFilterCounts] {
        let rows = countedRows(items: items, hooks: hooks)
        var out = [LoadoutRows.globalScope: filterCounts(rows.filter { $0.project == nil }, clis: clis)]
        for project in Set(rows.compactMap(\.project)) {
            out[project] = filterCounts(rows.filter { $0.project == project }, clis: clis)
        }
        return out
    }

    /// Each row key's flags: the filter counts over that key's members, above zero.
    static func rowFlags(items: [CoreInventoryItem], hooks: [CoreInventoryHook], clis order: [CLIID]) -> [String: CoreRowFlags] {
        let rows = countedRows(items: items, hooks: hooks)
        return Dictionary(grouping: rows, by: \.key).mapValues { members in
            let counts = filterCounts(members, clis: order)
            return CoreRowFlags(one: counts.only.contains { $0.count > 0 }, neverRan: counts.neverRan > 0, dead: counts.dead > 0)
        }
    }

    /// Rows deduplicated by key: a row is present in every CLI whose cell is neither missing nor absent, or in its own CLI when
    /// it has no cells yet. `only` counts the rows present in exactly one CLI; `neverRan` the rows no CLI saw run while at
    /// least one CLI counted them; `dead` the rows with a dead hook (which are not counted as never ran).
    static func filterCounts(_ rows: [CountedRow], clis: [CLIID]) -> CoreFilterCounts {
        var order: [String] = []
        var present: [String: Set<CLIID>] = [:]
        var counted: [String: [CLIID: CoreUsageCell]] = [:]
        var dead: [String: Bool] = [:]
        for row in rows {
            if present[row.key] == nil { order.append(row.key); present[row.key] = [] }
            if row.cells == nil { present[row.key]?.insert(row.cli) }
            for entry in row.cells?.entries ?? [] where entry.cell.isPresent {
                present[row.key]?.insert(entry.cli)
                if counted[row.key]?[entry.cli] == nil { counted[row.key, default: [:]][entry.cli] = entry.cell }
            }
            dead[row.key] = (dead[row.key] ?? false) || row.dead
        }
        var only: [CLIID: Int] = [:]
        var neverRan = 0
        var deadCount = 0
        for key in order {
            let clis = present[key] ?? []
            if clis.count == 1, let cli = clis.first { only[cli, default: 0] += 1 }
            let runs = (counted[key] ?? [:]).values.compactMap { cell -> Int? in
                if case .counted(let runs, _, _) = cell { runs } else { nil }
            }
            let isDead = dead[key] ?? false
            if !isDead, !runs.isEmpty, runs.allSatisfy({ $0 == 0 }) { neverRan += 1 }
            if isDead { deadCount += 1 }
        }
        return CoreFilterCounts(all: order.count, only: clis.map { CoreCLICount(cli: $0, count: only[$0] ?? 0) },
                                neverRan: neverRan, dead: deadCount)
    }
}
