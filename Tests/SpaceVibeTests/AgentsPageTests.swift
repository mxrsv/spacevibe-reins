import Foundation
import SwiftUI
import Testing
@testable import SpaceVibe

/// The Agents page's own logic (tabs and counts) and the sidebar's CLI status derivation, with synthetic data only.
@MainActor
@Suite("Agents page and sidebar facts")
struct AgentsPageTests {
    private func row(_ name: String, _ kind: LoadoutKind, project: String? = nil) -> LoadoutRow {
        LoadoutRow(
            key: "\(kind):\(project ?? ""):\(name)", kind: kind, project: project, members: [:],
            cells: CoreCells(claude: .missing, codex: .missing), flags: CoreRowFlags(one: false, neverRan: false, dead: false),
            name: name, detail: "", plugin: nil, errors: 0, runs: 0, addedNote: nil
        )
    }

    private func data(_ rows: [LoadoutRow], globalCount: Int) -> LoadoutData {
        LoadoutData(rows: rows, scopes: [], countsByScope: [:], problems: [], events: [:], globalCount: globalCount)
    }

    private func entry(_ cli: CoreLimitsCLI, _ state: CoreLimitsState) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: state, plan: nil, source: nil, at: nil, windows: [])
    }

    @Test("the tabs are Skills, Subagents, Hooks and Rules in that order, each with its own glyph and tone")
    func categories() {
        #expect(AgentsCategory.allCases.map(\.title) == ["Skills", "Subagents", "Hooks", "Rules"])
        #expect(AgentsCategory.allCases.map(\.tone) == [.skill, .subagent, .hook, .rule])
        #expect(AgentsCategory.allCases.map(\.glyph.iconName) == ["flash-line", "robot-line", "fish-symbol-line", "list-checks-duotone"])
    }

    @Test("selecting by index follows the tab order, and an index outside the four does nothing")
    func selectByIndex() {
        let page = AgentsPage(env: AppEnvironment(toasts: ToastCenter(announce: false)))
        #expect(page.selected == .skills)
        page.select(index: 3)
        #expect(page.selected == .rules)
        page.select(index: 4)
        page.select(index: -1)
        #expect(page.selected == .rules)
        page.select(.hooks)
        #expect(page.selected == .hooks)
    }

    @Test("counts show nothing until the reads land: no 0 for a number that is not known")
    func countsUnknown() {
        let counts = AgentsCounts(loadout: nil, rules: nil)
        #expect(counts.total == nil && counts.skills == nil && counts.rules == nil)
        #expect(AgentsCategory.allCases.allSatisfy { counts.count(for: $0) == nil })
        let page = AgentsPage(env: AppEnvironment(toasts: ToastCenter(announce: false)))
        #expect(page.badge == nil)
    }

    @Test("a tab counts the global scope's rows of its kind; the total is the core's global count; Rules is its own read")
    func countsByKind() {
        let rows = [row("a", .skill), row("b", .skill), row("c", .agent), row("d", .hook), row("p", .skill, project: "/work/app")]
        let counts = AgentsCounts(loadout: data(rows, globalCount: 4), rules: 11)
        #expect(counts.skills == 2 && counts.subagents == 1 && counts.hooks == 1 && counts.rules == 11)
        #expect(counts.total == 4)
        #expect(AgentsCategory.allCases.map { counts.count(for: $0) } == [2, 1, 1, 11])
    }

    @Test("a loaded Loadout with no Rules read yet still counts the three kinds")
    func countsWithoutRules() {
        let counts = AgentsCounts(loadout: data([row("a", .skill)], globalCount: 1), rules: nil)
        #expect(counts.skills == 1 && counts.rules == nil)
    }

    @Test("every limits state maps to one sidebar state, or none when the shell cannot tell")
    func cliStatus() {
        let expected: [CoreLimitsState: SidebarCLIState?] = [
            .measured: .reading, .notRecorded: .reading, .notInstalled: .notInstalled, .notMeasurable: .noLog, .unreadable: nil,
        ]
        for (state, shown) in expected {
            #expect(CLIStatusDerivation.state(of: entry(.claude, state)) == shown, "\(state)")
        }
        #expect(CLIStatusDerivation.state(of: nil) == nil)
        #expect([SidebarCLIState.reading, .notInstalled, .noLog].map(\.label) == ["reading", "not installed", "no log"])
        #expect(SidebarCLIState.reading.isOK && !SidebarCLIState.notInstalled.isOK && !SidebarCLIState.noLog.isOK)
    }

    @Test("the sidebar count is spoken by what it counts, never as items")
    func spokenTotal() {
        #expect(AgentsPage.spokenTotal(22) == "22 skills, subagents and hooks")
        #expect(AgentsPage.spokenTotal(1) == "1 skill, subagent or hook")
    }
}
