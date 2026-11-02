import Foundation

/// The fields `Inventory.filterCounts` needs from one row. Items and hooks convert to it; tests build it directly.
public struct FilterRow: Equatable, Sendable {
    public var key: String
    public var cli: InventoryCLI
    public var inOther: Bool
    public var dead: Bool
    public var cells: InventoryCells?

    public init(key: String, cli: InventoryCLI = .claude, inOther: Bool = false, dead: Bool = false, cells: InventoryCells?) {
        self.key = key; self.cli = cli; self.inOther = inOther; self.dead = dead; self.cells = cells
    }

    public init(_ item: InventoryItem) { self.init(key: item.key, cli: item.cli, inOther: item.inOther, dead: false, cells: item.cells) }
    public init(_ hook: InventoryHook) { self.init(key: hook.key, cli: hook.cli, inOther: false, dead: hook.dead, cells: hook.cells) }
}

extension Inventory {
    /// Counts for the filter chips. Rows are deduplicated by key, so a skill in both CLIs counts once.
    /// `neverRan`: it ran in no CLI that logs it, and at least one CLI counted it; a dead hook is counted only under `dead`.
    public static func filterCounts(items: [InventoryItem], hooks: [InventoryHook]) -> FilterCounts {
        filterCounts(items.map(FilterRow.init) + hooks.map(FilterRow.init))
    }

    public static func filterCounts(_ rows: [FilterRow]) -> FilterCounts {
        struct Group {
            var clis = Set<InventoryCLI>()
            var counted: [InventoryCLI: UsageCellState] = [:]
            var dead = false
        }
        var order: [String] = []
        var groups: [String: Group] = [:]
        for row in rows {
            if groups[row.key] == nil { order.append(row.key) }
            var group = groups[row.key] ?? Group()
            for cli in InventoryCLI.allCases {
                if let cell = row.cells?[cli] {
                    if !cell.isMissing { group.clis.insert(cli) }
                    if !cell.isMissing, group.counted[cli] == nil { group.counted[cli] = cell }
                } else if cli == row.cli || row.inOther {
                    group.clis.insert(cli)
                }
            }
            group.dead = group.dead || row.dead
            groups[row.key] = group
        }
        var out = FilterCounts(all: order.count, only: .init(claude: 0, codex: 0), neverRan: 0, dead: 0)
        for key in order {
            guard let group = groups[key] else { continue }
            if group.clis.count == 1 {
                if group.clis.contains(.claude) { out.only.claude += 1 } else { out.only.codex += 1 }
            }
            let runs = group.counted.values.compactMap { cell -> Int? in
                if case .counted(let runs, _, _) = cell { return runs } else { return nil }
            }
            if !group.dead, !runs.isEmpty, runs.allSatisfy({ $0 == 0 }) { out.neverRan += 1 }
            if group.dead { out.dead += 1 }
        }
        return out
    }
}
