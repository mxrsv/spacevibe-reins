import Foundation

// ---- Usage cells for the Matrix ------------------------------------------------------------------------------------
// counted      runs is how many times it ran (hooks) or how many sessions used it (skills, agents); 0 = never ran inside the
//              scanned logs. `errors` is set for hooks.
// pending      installed, but no scanned log can have covered it yet (see `pendingReason`)
// unmeasurable the CLI does not log it (Codex hooks), `reason` says why
// missing      not installed in that CLI
extension Inventory {
    /// HEURISTIC, not a fact: the age of an item is unknowable, so the mtime of its file stands in for "installed at"
    /// (SKILL.md, the agent file, or the settings file that holds the hook; any edit of that file moves it).
    /// An item with zero runs is "pending" instead of "never ran" when
    ///   1. its CLI has no scanned logs at all, or
    ///   2. it changed within the last 24 hours, or
    ///   3. it changed after the newest scanned log, so no session could have used it yet.
    static func pendingReason(addedMs: Double?, window: LogWindow?, nowMs: Double) -> String? {
        if let window, window.files == 0 { return "No logs scanned for this CLI yet" }
        if let addedMs, nowMs - addedMs < pendingGrace * 1000 { return "Added in the last 24 hours" }
        if let addedMs, let newest = window?.newest, addedMs > Double(newest) { return "Added after the newest log" }
        return nil
    }

    private struct Row {
        var kind: InventoryKind
        var name: String
        var hash: String
        var file: String
    }

    private static func cell(for row: Row?, cli: InventoryCLI, usage: UsageInput?, nowMs: Double, addedAt: (String) -> Double?) -> UsageCellState {
        guard let row else { return .missing }
        if row.kind == .hook, cli == .codex { return .unmeasurable(reason: codexHooksReason) }
        guard let totals = usage?.totals else { return .pending(reason: "Usage scan has not finished") }
        let isHook = row.kind == .hook
        let hookTotals = isHook ? totals[cli].hook[row.hash] : nil
        let nameUsage = isHook ? nil : (row.kind == .skill ? totals[cli].skill : totals[cli].agent)[bare(row.name)]
        let runs = isHook ? hookTotals?.runs ?? 0 : nameUsage?.sessions ?? 0
        if runs == 0, let reason = pendingReason(addedMs: addedAt(row.file), window: usage?.windows?[cli], nowMs: nowMs) {
            return .pending(reason: reason)
        }
        return isHook
            ? .counted(runs: runs, last: hookTotals?.last, errors: hookTotals?.errors ?? 0)
            : .counted(runs: runs, last: nameUsage?.last, errors: nil)
    }

    /// Pure apart from reading file mtimes. Adds `cells` to every item and hook, and `usage` to every Claude hook (nil when the
    /// scan has not finished or the CLI does not log it). Hook runs are keyed by event plus command, so the same hook in a
    /// global and a project file shares one count: the log does not say which file it came from.
    public static func attachUsage(_ inventory: InventorySnapshot, usage: UsageInput?, now: Date = Date()) -> InventorySnapshot {
        let nowMs = now.timeIntervalSince1970 * 1000
        var groups: [String: [InventoryCLI: Row]] = [:]
        for item in inventory.items { groups[item.key, default: [:]][item.cli] = Row(kind: item.kind, name: item.name, hash: "", file: item.file) }
        for hook in inventory.hooks { groups[hook.key, default: [:]][hook.cli] = Row(kind: .hook, name: "", hash: hook.hash, file: hook.file) }
        var mtimes: [String: Double?] = [:]
        let addedAt: (String) -> Double? = { file in
            if let known = mtimes[file] { return known }
            let value = InventoryFileIO.modifiedMs(URL(fileURLWithPath: file))
            mtimes[file] = .some(value)
            return value
        }
        func cells(for key: String) -> InventoryCells {
            let group = groups[key] ?? [:]
            return InventoryCells(
                claude: cell(for: group[.claude], cli: .claude, usage: usage, nowMs: nowMs, addedAt: addedAt),
                codex: cell(for: group[.codex], cli: .codex, usage: usage, nowMs: nowMs, addedAt: addedAt)
            )
        }

        var out = inventory
        for index in out.items.indices { out.items[index].cells = cells(for: out.items[index].key) }
        for index in out.hooks.indices {
            var hook = out.hooks[index]
            hook.cells = cells(for: hook.key)
            if hook.cli == .claude, let totals = usage?.totals {
                let u = totals.claude.hook[hook.hash]
                let avg = (u?.timed ?? 0) > 0 ? Int(((u?.ms ?? 0) / Double(u?.timed ?? 1)).rounded(.toNearestOrAwayFromZero)) : nil
                hook.usage = HookUsage(runs: u?.runs ?? 0, avgMs: avg, totalMs: u?.ms ?? 0, errors: u?.errors ?? 0, last: u?.last)
            } else {
                hook.usage = nil
            }
            out.hooks[index] = hook
        }
        return out
    }
}
