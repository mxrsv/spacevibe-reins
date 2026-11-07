import Foundation
import Testing
@testable import Reins

@Suite("Loadout rows")
struct LoadoutRowsTests {
    // MARK: Builders (synthetic names only, S-R2)

    /// What the core documents for the two CLIs; copy plans read it from the rows, never from the engine.
    private let events = ["claude": ["PreToolUse", "Stop"], "codex": ["Interrupt", "Stop"]]

    /// A Claude skill; `runs` fills its usage cell (Claude counted, Codex missing), nil leaves the cells to `build`.
    private func skill(_ name: String, project: String? = nil, runs: Int? = nil) -> CoreInventoryItem {
        CoreInventoryItem(
            id: "claude:skill:\(project ?? "global"):\(name)", cli: .claude, kind: .skill, name: name, entry: name, description: "",
            owner: "user", path: "/home/demo/.claude/skills/\(name)", file: "/home/demo/.claude/skills/\(name)/SKILL.md",
            removable: true, scope: project == nil ? .global : .project, project: project, inOther: false, key: "skill:\(project ?? ""):\(name)",
            cells: runs.map { CoreCells(claude: .counted(runs: $0, last: nil, errors: nil), codex: .missing) }
        )
    }

    private func hook(event: String, hash: String, dead: Bool = false) -> CoreInventoryHook {
        CoreInventoryHook(
            id: "claude:hook:\(hash)", cli: .claude, kind: .hook, event: event, matcher: nil, command: "demo-hook.sh", timeout: nil, async: false,
            owner: "user", removable: true, dead: dead, paths: [], hash: hash, file: "/home/demo/.claude/settings.json",
            scope: .global, project: nil, key: "hook::\(hash)", cells: nil, usage: nil
        )
    }

    /// The same skill as seen in Codex.
    private func inCodex(_ item: CoreInventoryItem) -> CoreInventoryItem {
        var copy = item
        copy.cli = .codex
        copy.id = item.id.replacingOccurrences(of: "claude:", with: "codex:")
        return copy
    }

    private func inCodex(_ hook: CoreInventoryHook) -> CoreInventoryHook {
        var copy = hook
        copy.cli = .codex
        copy.id = hook.id.replacingOccurrences(of: "claude:", with: "codex:")
        return copy
    }

    /// `loadout.rows` as the core sends it, with the row flags it would compute: one CLI only, and dead.
    private func snapshot(items: [CoreInventoryItem] = [], hooks: [CoreInventoryHook] = []) -> CoreLoadoutRows {
        var seen: [String: (clis: Set<CoreCLI>, dead: Bool)] = [:]
        for item in items { seen[item.key, default: ([], false)].clis.insert(item.cli) }
        for hook in hooks {
            let dead = seen[hook.key]?.dead == true || hook.dead
            seen[hook.key, default: ([], false)].clis.insert(hook.cli)
            seen[hook.key]?.dead = dead
        }
        let flags = seen.mapValues { CoreRowFlags(one: $0.clis.count == 1, neverRan: false, dead: $0.dead) }
        return CoreLoadoutRows(
            usage: .ready, items: items, hooks: hooks, problems: [], events: events,
            roots: ["claude": "/home/demo/.claude", "codex": "/home/demo/.codex"], countsByScope: [:], rowFlags: flags
        )
    }

    private func onlyRow(_ snapshot: CoreLoadoutRows) throws -> LoadoutRow {
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
        #expect(LoadoutRows.copyPlan(row, to: .codex, events: events) == nil)
        let global = try onlyRow(snapshot(items: [skill("one")]))
        #expect(LoadoutRows.copyPlan(global, to: .codex, events: events) == "claude:skill:global:one")
    }

    @Test("a dead hook is not copied")
    func copyPlanRefusesDeadHook() throws {
        let dead = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Stop", hash: "h1", dead: true))]))
        #expect(dead.flags.dead)
        #expect(LoadoutRows.copyPlan(dead, to: .claude, events: events) == nil)
        let alive = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Stop", hash: "h1"))]))
        #expect(LoadoutRows.copyPlan(alive, to: .claude, events: events) == "codex:hook:h1")
    }

    @Test("a hook is never copied into Codex")
    func copyPlanRefusesHookToCodex() throws {
        let row = try onlyRow(snapshot(hooks: [hook(event: "Stop", hash: "h1")]))
        #expect(LoadoutRows.copyPlan(row, to: .codex, events: events) == nil)
    }

    @Test("a Codex hook whose event Claude Code does not document is not copied; a known event is")
    func copyPlanChecksClaudeEvents() throws {
        #expect(events["codex"]?.contains("Interrupt") == true)
        #expect(events["claude"]?.contains("Interrupt") == false)
        let unknown = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Interrupt", hash: "h1"))]))
        #expect(LoadoutRows.copyPlan(unknown, to: .claude, events: events) == nil)
        let known = try onlyRow(snapshot(hooks: [inCodex(hook(event: "Stop", hash: "h2"))]))
        #expect(LoadoutRows.copyPlan(known, to: .claude, events: events) == "codex:hook:h2")
    }

    @Test("nothing is copied into a CLI whose cell is already filled")
    func copyPlanRefusesFilledCell() throws {
        let both = try onlyRow(snapshot(items: [skill("one"), inCodex(skill("one"))]))
        #expect(LoadoutRows.copyPlan(both, to: .codex, events: events) == nil)
        #expect(LoadoutRows.copyPlan(both, to: .claude, events: events) == nil)
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

    @Test("a row takes its chip flags from the core, not from its members")
    func flagsComeFromTheCore() throws {
        var rows = snapshot(items: [skill("one")])
        rows.rowFlags["skill::one"] = CoreRowFlags(one: false, neverRan: true, dead: true)
        let row = try onlyRow(rows)
        #expect(row.flags == CoreRowFlags(one: false, neverRan: true, dead: true))
        #expect(LoadoutFilter.never.matches(row.flags) && LoadoutFilter.dead.matches(row.flags) && !LoadoutFilter.one.matches(row.flags))
        // A key the core sent no flags for is in no chip.
        rows.rowFlags = [:]
        #expect(try onlyRow(rows).flags == CoreRowFlags(one: false, neverRan: false, dead: false))
    }

    @Test("a chip's count is the core's count for the scope")
    func chipCounts() {
        let counts = CoreFilterCounts(all: 9, only: .init(claude: 3, codex: 2), neverRan: 4, dead: 1)
        #expect(LoadoutFilter.allCases.map { $0.count(in: counts) } == [9, 5, 4, 1])
    }

    @Test("what the screen shows: problems lose the home folder, the badge counts the global scope, scopes come from the rows")
    func screenData() {
        var rows = snapshot(items: [skill("one"), skill("two", project: "/a/app")])
        rows.problems = ["Could not read /home/demo/.claude/skills/broken/SKILL.md", "No home here: /elsewhere/x"]
        rows.countsByScope = ["global": CoreFilterCounts(all: 7, only: .init(claude: 0, codex: 0), neverRan: 0, dead: 0)]
        let data = LoadoutData.build(raw: rows)
        #expect(data.problems == ["Could not read ~/.claude/skills/broken/SKILL.md", "No home here: /elsewhere/x"])
        #expect(data.globalCount == 7)
        #expect(data.scopes.map(\.value) == ["global", "/a/app"])
        #expect(data.events == events)
        #expect(data.rows.count == 2)
    }

    @Test("the home folder is abbreviated only when the Claude folder sits directly in it")
    func homeAbbreviation() {
        #expect(LoadoutRows.home(roots: ["claude": "/home/demo/.claude"]) == "/home/demo")
        #expect(LoadoutRows.home(roots: ["claude": "/custom/place"]) == nil)
        #expect(LoadoutRows.home(roots: [:]) == nil)
        #expect(LoadoutRows.shorten("run /home/demo/bin/x", home: "/home/demo") == "run ~/bin/x")
    }

    @Test("a pending cell that says the item is new is tagged")
    func addedNotes() {
        #expect(LoadoutRows.addedNote(CoreCells(claude: .pending(reason: "Added in the last scan window"), codex: .missing)) == "added recently")
        #expect(LoadoutRows.addedNote(CoreCells(claude: .missing, codex: .pending(reason: "Added after the last log"))) == "added after the last log")
        #expect(LoadoutRows.addedNote(CoreCells(claude: .pending(reason: "Usage scan has not finished"), codex: .missing)) == nil)
    }
}

private extension CoreInventoryHook {
    func withProject(_ project: String) -> CoreInventoryHook {
        var copy = self
        copy.project = project
        copy.scope = .project
        return copy
    }
}
