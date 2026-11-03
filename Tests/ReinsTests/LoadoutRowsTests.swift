import Foundation
import Testing
import ReinsCore
@testable import Reins

@Suite("Loadout rows")
struct LoadoutRowsTests {
    // MARK: Builders (synthetic names only, S-R2)

    /// A Claude skill; `runs` fills its usage cell (Claude counted, Codex missing), nil leaves the cells to `build`.
    private func skill(_ name: String, project: String? = nil, runs: Int? = nil) -> InventoryItem {
        InventoryItem(
            id: "claude:skill:\(project ?? "global"):\(name)", cli: .claude, kind: .skill, name: name, entry: name, description: "",
            owner: "user", path: "/home/demo/.claude/skills/\(name)", file: "/home/demo/.claude/skills/\(name)/SKILL.md",
            removable: true, scope: project == nil ? .global : .project, project: project,
            cells: runs.map { InventoryCells(claude: .counted(runs: $0, last: nil, errors: nil), codex: .missing) }
        )
    }

    private func hook(event: String, hash: String, dead: Bool = false) -> InventoryHook {
        InventoryHook(
            id: "claude:hook:\(hash)", cli: .claude, event: event, matcher: nil, command: "demo-hook.sh", timeout: nil, async: false,
            owner: "user", removable: true, dead: dead, paths: [], hash: hash, file: "/home/demo/.claude/settings.json",
            scope: .global, project: nil
        )
    }

    /// The same skill as seen in Codex.
    private func inCodex(_ item: InventoryItem) -> InventoryItem {
        var copy = item
        copy.cli = .codex
        copy.id = item.id.replacingOccurrences(of: "claude:", with: "codex:")
        return copy
    }

    private func inCodex(_ hook: InventoryHook) -> InventoryHook {
        var copy = hook
        copy.cli = .codex
        copy.id = hook.id.replacingOccurrences(of: "claude:", with: "codex:")
        return copy
    }

    private func snapshot(items: [InventoryItem] = [], hooks: [InventoryHook] = []) -> InventorySnapshot {
        InventorySnapshot(items: items, hooks: hooks, problems: [], roots: ["claude": "/home/demo/.claude", "codex": "/home/demo/.codex"])
    }

    private func onlyRow(_ snapshot: InventorySnapshot) throws -> LoadoutRow {
        try #require(LoadoutRows.build(snapshot, home: nil).first)
    }

    // MARK: scopes

    @Test("scopes lists Global first, then each project by its folder name, with the parent folder when two share a name")
    func scopeLabels() {
        let webHook = hook(event: "Stop", hash: "h1").withProject("/c/web")
        let scopes = LoadoutRows.scopes(snapshot(items: [skill("one", project: "/a/app"), skill("two", project: "/b/app")], hooks: [webHook]))
        #expect(scopes == [
            LoadoutScope(value: LoadoutRows.globalScope, label: "Global"),
            LoadoutScope(value: "/a/app", label: "a/app"),
            LoadoutScope(value: "/b/app", label: "b/app"),
            LoadoutScope(value: "/c/web", label: "web"),
        ])
    }

    @Test("scopes with no project config is just Global")
    func scopesGlobalOnly() {
        #expect(LoadoutRows.scopes(snapshot(items: [skill("one")])) == [LoadoutScope(value: "global", label: "Global")])
    }

    // MARK: copyPlan

    @Test("a row from a project is never copied: project configuration is read-only")
    func copyPlanRefusesProjectRow() throws {
        let row = try onlyRow(snapshot(items: [skill("one", project: "/a/app")]))
        #expect(LoadoutRows.copyPlan(row, to: .codex, events: Inventory.events) == nil)
        let global = try onlyRow(snapshot(items: [skill("one")]))
        #expect(LoadoutRows.copyPlan(global, to: .codex, events: Inventory.events) == "claude:skill:global:one")
    }

    @Test("a dead hook is not copied")
    func copyPlanRefusesDeadHook() throws {
        let dead = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Stop", hash: "h1", dead: true))]))
        #expect(dead.flags.dead)
        #expect(LoadoutRows.copyPlan(dead, to: .claude, events: Inventory.events) == nil)
        let alive = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Stop", hash: "h1"))]))
        #expect(LoadoutRows.copyPlan(alive, to: .claude, events: Inventory.events) == "codex:hook:h1")
    }

    @Test("a hook is never copied into Codex")
    func copyPlanRefusesHookToCodex() throws {
        let row = try onlyRow(snapshot(hooks: [hook(event: "Stop", hash: "h1")]))
        #expect(LoadoutRows.copyPlan(row, to: .codex, events: Inventory.events) == nil)
    }

    @Test("a Codex hook whose event Claude Code does not document is not copied; a known event is")
    func copyPlanChecksClaudeEvents() throws {
        #expect(Inventory.events["codex"]?.contains("Interrupt") == true)
        #expect(Inventory.events["claude"]?.contains("Interrupt") == false)
        let unknown = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Interrupt", hash: "h1"))]))
        #expect(LoadoutRows.copyPlan(unknown, to: .claude, events: Inventory.events) == nil)
        let known = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Stop", hash: "h2"))]))
        #expect(LoadoutRows.copyPlan(known, to: .claude, events: Inventory.events) == "codex:hook:h2")
    }

    @Test("nothing is copied into a CLI whose cell is already filled")
    func copyPlanRefusesFilledCell() throws {
        let both = try onlyRow(snapshot(items: [skill("one"), inCodex(skill("one"))]))
        #expect(LoadoutRows.copyPlan(both, to: .codex, events: Inventory.events) == nil)
        #expect(LoadoutRows.copyPlan(both, to: .claude, events: Inventory.events) == nil)
    }

    // MARK: build

    @Test("rows are sorted by runs, most first, then by name ignoring case")
    func buildSortOrder() {
        // "alpha" before "Beta" only if the comparison ignores case; a plain byte order puts "Beta" first.
        let items = [skill("Beta", runs: 5), skill("mid", runs: 3), skill("zeta", runs: 9), skill("alpha", runs: 5)]
        let rows = LoadoutRows.build(snapshot(items: items), home: nil)
        #expect(rows.map(\.name) == ["zeta", "alpha", "Beta", "mid"])
        #expect(rows.map(\.runs) == [9, 5, 5, 3])
    }
}

private extension InventoryHook {
    func withProject(_ project: String) -> InventoryHook {
        var copy = self
        copy.project = project
        copy.scope = .project
        return copy
    }
}
