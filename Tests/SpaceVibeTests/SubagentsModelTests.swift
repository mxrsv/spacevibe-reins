import Foundation
import Testing
@testable import SpaceVibe

/// The Subagents tab's derived facts (V5-A18): the Answer in each case, the bands and their default open state, the warning
/// slot's states, the filters, the rule behind `In one CLI only` and the sentences. Rows are built through `LoadoutRows.build`, as
/// the app builds them. Synthetic names only (S-R2).
@Suite("Subagents model")
@MainActor
struct SubagentsModelTests {
    private func counted(_ runs: Int, last: String? = nil) -> CoreUsageCell { SkillRowsFixture.counted(runs, last: last) }
    private let both: [CoreCLI] = [.claude, .codex]

    private func rows(_ specs: [(name: String, claude: CoreUsageCell?, codex: CoreUsageCell?, owner: String)]) -> [LoadoutRow] {
        var items: [CoreInventoryItem] = []
        for spec in specs {
            let cells = CoreCells(claude: spec.claude ?? .missing, codex: spec.codex ?? .missing)
            for (cli, cell) in [(CoreCLI.claude, spec.claude), (CoreCLI.codex, spec.codex)] where cell != nil {
                items.append(CoreInventoryItem(
                    id: "\(cli.rawValue):agent:global:\(spec.name)", cli: cli, kind: .agent, name: spec.name, entry: spec.name, description: "",
                    owner: spec.owner, path: "/home/demo/.\(cli.rawValue)/agents/\(spec.name)", file: "/home/demo/.\(cli.rawValue)/agents/\(spec.name).md",
                    removable: spec.owner == "user", scope: .global, project: nil, inOther: false, key: "agent::\(spec.name)", cells: cells))
            }
        }
        let snapshot = CoreLoadoutRows(usage: .ready, items: items, hooks: [], problems: [], events: [:],
                                       roots: ["claude": "/home/demo/.claude", "codex": "/home/demo/.codex"], countsByScope: [:], rowFlags: [:])
        return LoadoutRows.build(snapshot, home: nil)
    }

    private func row(_ name: String, claude: CoreUsageCell? = nil, codex: CoreUsageCell? = nil, owner: String = "user") -> LoadoutRow {
        rows([(name, claude, codex, owner)])[0]
    }

    private func answer(_ rows: [LoadoutRow], loaded: Bool = true, detected: [CoreCLI] = [.claude, .codex]) -> SubagentsAnswer {
        SubagentsAnswer.of(rows, isLoaded: loaded, detected: detected)
    }

    // MARK: The Answer (V5-A18)

    @Test("a problem: the sentence counts what never ran and the verdict names it, with Review and Remove")
    func oneProblem() {
        let list = rows([("architect", counted(0), nil, "user"), ("typescript-reviewer", counted(34), nil, "user")])
        let result = answer(list)
        #expect(result.sentence == "1 subagent never ran.")
        #expect(result.verdict?.name == "architect" && result.verdict?.offersRemove == true && result.more == 0)
        #expect(result.verdict?.text == "Installed in Claude Code. Nothing in the local logs shows a session.")
    }

    @Test("several problems: the sentence counts them all, names the first by name and says how many more are marked")
    func severalProblems() {
        let list = rows([("zeta", counted(0), nil, "user"), ("alpha", counted(0), counted(0), "user"), ("mid", counted(0), nil, "user"), ("busy", counted(9), nil, "user")])
        let result = answer(list)
        #expect(result.sentence == "3 subagents never ran.")
        #expect(result.verdict?.name == "alpha" && result.more == 2)
        #expect(result.verdict?.text == "Installed in both CLIs. Nothing in the local logs shows a session in either.")
    }

    @Test("nothing needs the user: every subagent has run, or nothing is worth a look; no verdict either way")
    func nothingNeedsTheUser() {
        let healthy = answer(rows([("a", counted(3), nil, "user"), ("b", counted(1), counted(2), "user")]))
        #expect(healthy.sentence == "Every subagent has run." && healthy.verdict == nil && healthy.more == 0)
        let fresh = answer(rows([("a", counted(3), nil, "user"), ("new", SkillRowsFixture.addedToday, nil, "user")]))
        #expect(fresh.sentence == "Nothing needs your attention." && fresh.verdict == nil)
        let unlogged = answer(rows([("a", counted(3), nil, "user"), ("b", nil, SkillRowsFixture.noLogs, "user")]))
        #expect(unlogged.sentence == "Nothing needs your attention.")
    }

    @Test("no data or loading: no sentence, so the card shows its skeleton")
    func loading() {
        #expect(answer([], loaded: false).sentence == nil)
        #expect(answer(rows([("a", counted(3), nil, "user")]), loaded: false).sentence == nil)
        #expect(answer([]).sentence == nil)
        #expect(answer(rows([("a", counted(3), nil, "user"), ("b", SkillRowsFixture.scanning, nil, "user")])).sentence == nil, "the usage scan has not finished")
    }

    @Test("Codex not installed: the sentence is the same, the verdict says Claude Code only and no subagent can be added")
    func codexNotInstalled() {
        let list = rows([("architect", counted(0), nil, "user"), ("typescript-reviewer", counted(34), nil, "user")])
        let result = answer(list, detected: [.claude])
        #expect(result.sentence == "1 subagent never ran.")
        #expect(result.verdict?.text.hasPrefix("Installed in Claude Code.") == true)
        let addable = SubagentsAddable(list, detected: [.claude])
        #expect(addable.isEmpty && addable.leftOut == ["architect (never ran)", "typescript-reviewer (Codex is not installed)"])
    }

    @Test("a plugin's subagent that never ran is counted, but its verdict offers no Remove")
    func pluginProblem() {
        let list = rows([("vendor", counted(0), nil, "neon"), ("mine", counted(5), nil, "user")])
        let result = answer(list)
        #expect(result.sentence == "1 subagent never ran." && result.verdict?.offersRemove == false)
        #expect(result.verdict?.small == "Owned by the neon plugin, so SpaceVibe can read it but not change it.")
    }

    // MARK: Bands (V5-R55, V5-R63)

    @Test("bands: the one holding a never-ran subagent comes first and opens; the rest start closed")
    func bands() {
        let list = rows([("both-ran", counted(4), counted(1), "user"), ("c-ran", counted(9), nil, "user"), ("c-never", counted(0), nil, "user"), ("x-ran", nil, counted(2), "user")])
        let layout = SubagentsQuery().layout(list)
        #expect(layout.groups.map(\.title) == ["Claude Code only", "In both", "Codex only"])
        #expect(layout.groups.map(\.holdsProblem) == [true, false, false])
        #expect(layout.groups.first?.rows.map(\.name) == ["c-never", "c-ran"], "never ran first, then sessions")
        #expect((0 ..< 3).map { SubagentsCanvas.opensByDefault(layout, $0) } == [true, false, false])
    }

    @Test("bands: with nothing to look at, the first band opens")
    func bandsWithoutProblems() {
        let list = rows([("a", counted(4), counted(1), "user"), ("b", counted(9), nil, "user")])
        let layout = SubagentsQuery().layout(list)
        #expect(layout.groups.map(\.title) == ["In both", "Claude Code only"])
        #expect((0 ..< 2).map { SubagentsCanvas.opensByDefault(layout, $0) } == [true, false])
    }

    @Test("Group: None lists the rows flat, in the same order")
    func flat() {
        let list = rows([("a", counted(4), counted(1), "user"), ("b", counted(9), nil, "user"), ("c", counted(0), nil, "user")])
        var query = SubagentsQuery()
        query.group = .none
        let layout = query.layout(list)
        #expect(!layout.isGrouped && layout.groups.count == 1)
        #expect(layout.rows.map(\.name) == ["c", "b", "a"])
    }

    // MARK: The warning slot (V5-R64)

    @Test("the slot: lock for a plugin, triangle for never ran, neutral clock for new or unmeasurable, nothing for a subagent that ran")
    func slots() {
        #expect(SubagentsWording.slot(for: row("a", claude: counted(3)))?.mark == nil)
        #expect(SubagentsWording.slot(for: row("a", claude: counted(0)))?.mark.kind == .warn)
        #expect(SubagentsWording.slot(for: row("a", claude: SkillRowsFixture.addedToday))?.mark.kind == .clock)
        #expect(SubagentsWording.slot(for: row("a", claude: SkillRowsFixture.noLogs))?.mark.kind == .clock)
        #expect(SubagentsWording.slot(for: row("a", claude: SkillRowsFixture.scanning)) == nil)
        let plugin = SubagentsWording.slot(for: row("a", claude: counted(0), owner: "neon"))
        #expect(plugin?.mark.kind == .lock && plugin?.offersRemove == false && plugin?.plugin == "neon")
        #expect(plugin?.sentence == "Never ran in Claude Code. Nothing in the local logs shows a session.", "the lock's popover still says it never ran")
        #expect(SubagentsWording.slot(for: row("a", claude: counted(3), owner: "neon"))?.sentence == nil)
        #expect(SubagentsWording.slot(for: row("a", claude: counted(0)))?.offersRemove == true)
    }

    @Test("the row text: sessions, never ran (a new file too), unmeasurable, counting")
    func sessionsText() {
        #expect(SubagentsWording.sessionsText(row("a", claude: counted(142))) == "142 sessions")
        #expect(SubagentsWording.sessionsText(row("a", claude: counted(1))) == "1 session")
        #expect(SubagentsWording.sessionsText(row("a", claude: counted(0))) == "never ran")
        #expect(SubagentsWording.sessionsText(row("a", claude: SkillRowsFixture.addedToday)) == "never ran")
        #expect(SubagentsWording.sessionsText(row("a", claude: SkillRowsFixture.noLogs)) == "unmeasurable")
        #expect(SubagentsWording.sessionsText(row("a", claude: SkillRowsFixture.scanning)) == "counting")
        #expect(SubagentsWording.sessionsText(row("a", claude: counted(5), codex: counted(2))) == "7 sessions", "every CLI that counted")
    }

    @Test("the detail popover: one sentence per CLI with its sessions and the day of the last one, never a model or tools")
    func detailLines() {
        let list = row("a", claude: counted(34, last: "2026-11-05"), codex: SkillRowsFixture.noLogs)
        #expect(SubagentsWording.lines(for: list, now: SkillRowsFixture.now) == ["Claude Code: 34 sessions, last session yesterday.", "Codex: no logs to count sessions from."])
        #expect(SubagentsWording.lines(for: row("a", claude: counted(0)), now: SkillRowsFixture.now) == ["Claude Code: never ran."])
        #expect(SubagentsWording.presence(list) == "In both CLIs" && SubagentsWording.presence(row("a", codex: counted(1))) == "Codex only")
    }

    // MARK: Filters (V5-R64)

    @Test("filters: AND across fields, OR within one; Status, CLI and Owner")
    func filters() {
        let list = rows([("never", counted(0), nil, "user"), ("both", counted(4), counted(1), "user"), ("plug", counted(2), nil, "neon"),
                         ("nolog", nil, SkillRowsFixture.noLogs, "user"), ("x", nil, counted(3), "user")])
        func names(_ configure: (inout SubagentsFilter) -> Void) -> [String] {
            var query = SubagentsQuery()
            configure(&query.filter)
            query.group = .none
            return query.layout(list).rows.map(\.name).sorted()
        }
        #expect(names { $0.toggle(.status, "neverRan") } == ["never"])
        #expect(names { $0.toggle(.status, "unmeasurable") } == ["nolog"])
        #expect(names { $0.toggle(.status, "neverRan"); $0.toggle(.status, "unmeasurable") } == ["never", "nolog"])
        #expect(names { $0.toggle(.cli, "both") } == ["both"])
        #expect(names { $0.toggle(.cli, "codex") } == ["both", "nolog", "x"])
        #expect(names { $0.toggle(.owner, "plugin") } == ["plug"])
        #expect(names { $0.toggle(.owner, "mine"); $0.toggle(.cli, "claude") } == ["both", "never"])
        #expect(names { $0.toggle(.owner, "plugin"); $0.toggle(.status, "neverRan") }.isEmpty)
        var filter = SubagentsFilter()
        filter.toggle(.cli, "codex")
        filter.toggle(.status, "neverRan")
        #expect(filter.chips.map { "\($0.field.chipTitle) \($0.value.chip)" } == ["Status is Never ran", "CLI is Codex"])
        filter.clear()
        #expect(!filter.isOn)
    }

    // MARK: The addable rule (V5-R63)

    @Test("In one CLI only: one CLI, the other installed, no plugin, did not go unused; most sessions first; the rest named with the reason")
    func addable() {
        let list = rows([("ran-small", counted(2), nil, "user"), ("ran-big", counted(30), nil, "user"), ("never", counted(0), nil, "user"),
                         ("plug", counted(9), nil, "neon"), ("x-only", nil, counted(5), "user"), ("both", counted(1), counted(1), "user"),
                         ("new", SkillRowsFixture.addedToday, nil, "user")])
        let result = SubagentsAddable(list, detected: both)
        #expect(result.entries.map(\.row.name) == ["ran-big", "x-only", "ran-small", "new"])
        #expect(result.entries.map(\.target) == [.codex, .claude, .codex, .codex])
        #expect(result.leftOut == ["never (never ran)", "plug (plugin-owned)"])
        #expect(SubagentsAddable(rows([("both", counted(1), counted(1), "user")]), detected: both).isEmpty, "the card is dropped when it has no row")
        #expect(SubagentsAddable([row("x-only", codex: counted(5))], detected: [.codex]).leftOut == ["x-only (Claude Code is not installed)"])
    }

    // MARK: Toasts (G10)

    @Test("the add toast says what the copy leaves out; the others name the subagent")
    func toasts() {
        let a = row("typescript-reviewer", claude: counted(3), codex: counted(1))
        #expect(SubagentsWording.addLabel(a, to: .codex) == "Added typescript-reviewer to Codex")
        #expect(SubagentsWording.addNote(to: .codex) == "Its model and tools are not copied.")
        #expect(SubagentsWording.addNote(to: .claude) == "Its model and tools are not copied, so it can use every tool.")
        #expect(SubagentsWording.removeLabel(a, from: nil) == "Removed typescript-reviewer")
        #expect(SubagentsWording.removeLabel(a, from: .codex) == "Removed the Codex copy of typescript-reviewer")
        #expect(SubagentsWording.nothingToChange(row("v", claude: counted(1), owner: "neon"), adding: false) == "v is owned by the neon plugin. SpaceVibe cannot change it.")
    }
}
