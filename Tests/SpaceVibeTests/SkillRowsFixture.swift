import Foundation
@testable import SpaceVibe

/// Skill rows for the Skills tests: built through `LoadoutRows.build`, as the app builds them, from items that carry the cells
/// the core would attach. Synthetic names only (S-R2).
enum SkillRowsFixture {
    static let now = Date(timeIntervalSince1970: 1_794_000_000) // 2026-11-06 21:20 UTC

    static func counted(_ runs: Int, last: String? = nil) -> CoreUsageCell { .counted(runs: runs, last: last, errors: nil) }

    static let addedToday = CoreUsageCell.pending(reason: "Added in the last 24 hours")
    static let addedAfterLog = CoreUsageCell.pending(reason: "Added after the newest log")
    static let scanning = CoreUsageCell.pending(reason: "Usage scan has not finished")
    static let noLogs = CoreUsageCell.pending(reason: "No logs scanned for this CLI yet")

    /// A skill: a nil cell means the CLI does not have it.
    static func item(_ name: String, cli: CoreCLI, cells: CoreCells, owner: String = "user", project: String? = nil,
                     removable: Bool = true, description: String = "") -> CoreInventoryItem {
        CoreInventoryItem(
            id: "\(cli.rawValue):skill:\(project ?? "global"):\(name)", cli: cli, kind: .skill, name: name, entry: name, description: description,
            owner: owner, path: "/home/demo/.\(cli.rawValue)/skills/\(name)", file: "/home/demo/.\(cli.rawValue)/skills/\(name)/SKILL.md",
            removable: removable, scope: project == nil ? .global : .project, project: project, inOther: false,
            key: "skill:\(project ?? ""):\(name)", cells: cells
        )
    }

    static func snapshot(_ specs: [(name: String, claude: CoreUsageCell?, codex: CoreUsageCell?, owner: String, project: String?)]) -> CoreLoadoutRows {
        var items: [CoreInventoryItem] = []
        for spec in specs {
            let cells = CoreCells(claude: spec.claude ?? .missing, codex: spec.codex ?? .missing)
            if spec.claude != nil { items.append(item(spec.name, cli: .claude, cells: cells, owner: spec.owner, project: spec.project, removable: spec.owner == "user")) }
            if spec.codex != nil { items.append(item(spec.name, cli: .codex, cells: cells, owner: spec.owner, project: spec.project, removable: spec.owner == "user")) }
        }
        return CoreLoadoutRows(usage: .ready, items: items, hooks: [], problems: [], events: ["claude": ["Stop"], "codex": ["Stop"]],
                               roots: ["claude": "/home/demo/.claude", "codex": "/home/demo/.codex"], countsByScope: [:], rowFlags: [:])
    }

    /// Rows in the order given by `LoadoutRows.build` (sessions first), for a test to look up by name.
    static func rows(_ specs: [(name: String, claude: CoreUsageCell?, codex: CoreUsageCell?)], owners: [String: String] = [:]) -> [LoadoutRow] {
        LoadoutRows.build(snapshot(specs.map { ($0.name, $0.claude, $0.codex, owners[$0.name] ?? "user", nil) }), home: nil)
    }

    static func row(_ name: String, claude: CoreUsageCell? = nil, codex: CoreUsageCell? = nil, owner: String = "user", project: String? = nil) -> LoadoutRow {
        LoadoutRows.build(snapshot([(name, claude, codex, owner, project)]), home: nil)[0]
    }
}
