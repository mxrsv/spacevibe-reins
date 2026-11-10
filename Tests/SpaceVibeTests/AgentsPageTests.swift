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

    @Test("problems drop the core's line about hooks of other types and keep the others")
    func problemsDropOtherTypes() {
        let other = "2 hooks of other types are not shown."
        #expect(HooksWording.isOtherTypesProblem(other))
        let broken = "~/.claude/settings.json is not valid JSON."
        let loaded = LoadoutData(rows: [], scopes: [], countsByScope: [:], problems: [other, broken, "~/.codex/hooks.json could not be read."], events: [:], globalCount: 0)
        #expect(AgentsPage.problems(in: loaded) == [broken, "~/.codex/hooks.json could not be read."])
        #expect(AgentsPage.problems(in: nil).isEmpty)
        let page = AgentsPage(env: AppEnvironment(toasts: ToastCenter(announce: false)))
        #expect(page.problems.isEmpty, "nothing is read yet")
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

    @Test("the page names a failed scan only while the rows have no counts, and a failed read only while it has no rows")
    func failures() {
        let env = AppEnvironment(toasts: ToastCenter(announce: false))
        let rows = data([row("a", .skill)], globalCount: 1)
        #expect(AgentsPage(env: env, loadout: LoadoutModel(env: env, data: rows, scanFailure: "The scan failed.")).scanFailure == "The scan failed.")
        #expect(AgentsPage(env: env, loadout: LoadoutModel(env: env, data: nil, scanFailure: "The scan failed.")).scanFailure == nil)
        #expect(AgentsPage(env: env, loadout: LoadoutModel(env: env, data: rows)).scanFailure == nil)
        #expect(AgentsPage(env: env, loadout: LoadoutModel(env: env, data: nil, readFailure: "No folders.")).readFailure == "No folders.")
        #expect(AgentsPage(env: env, loadout: LoadoutModel(env: env, data: rows, readFailure: "No folders.")).readFailure == nil)
    }

    @Test("the rows of a failed scan keep every cell that was counted as not counted yet")
    func withoutCounts() {
        var counted = row("a", .skill)
        counted.cells = CoreCells(claude: .counted(runs: 3, last: nil, errors: nil), codex: .missing)
        let shown = data([counted], globalCount: 1).withoutCounts()
        #expect(shown.rows[0].cells.claude == .pending(reason: "Usage scan has not finished") && shown.rows[0].cells.codex == .missing)
    }

    // MARK: Re-reading (D1)

    private func settle(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done(), "\(what) did not happen")
    }

    private func settled(_ page: AgentsPage) -> Bool { page.loadout.isSettled && page.rules.isSettled }

    private func started(_ core: CountingAgentsCore) async throws -> AgentsPage {
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core })
        let page = AgentsPage(env: env)
        page.start()
        try await settle("the first reads") { settled(page) }
        return page
    }

    @Test("refresh reads the inventory, the usage and the rules again; a second call inside ten seconds reads nothing")
    func refreshReadsOnceInTenSeconds() async throws {
        let core = CountingAgentsCore()
        let page = try await started(core)
        let before = core.counts
        #expect(before.rows == 2 && before.scans == 1 && before.snapshots == 1)

        let t0 = Date(timeIntervalSince1970: 1_000_000)
        page.refresh(now: t0)
        try await settle("the re-reads") { settled(page) && core.counts.rows == before.rows + 2 }
        #expect(core.counts.scans == before.scans + 1 && core.counts.snapshots == before.snapshots + 1)

        let after = core.counts
        page.refresh(now: t0.addingTimeInterval(AgentsPage.refreshInterval - 1))
        try await Task.sleep(for: .milliseconds(100))
        #expect(core.counts == after, "a second refresh inside the interval reads nothing")

        page.refresh(now: t0.addingTimeInterval(AgentsPage.refreshInterval))
        try await settle("the later re-read") { settled(page) && core.counts.snapshots == after.snapshots + 1 }
    }

    @Test("the Skills and Subagents status bar names the log span once a usage result exists; before that it keeps the old source")
    func sourceNamesTheSpan() async throws {
        let page = try await started(CountingAgentsCore())
        let note = "Counted from 1 Claude Code and 1 Codex sessions since 2026-10-01"
        #expect(page.loadout.usageResult != nil)
        page.select(.skills)
        #expect(page.source == note)
        page.select(.subagents)
        #expect(page.source == note)
        let fresh = AgentsPage(env: AppEnvironment(toasts: ToastCenter(announce: false)))
        #expect(fresh.source == SkillsStatusBar.source)
        fresh.select(.subagents)
        #expect(fresh.source == SubagentsStatusBar.source)
    }

    @Test("a forced refresh reads inside the interval, and the palette entry forces it")
    func forcedRefresh() async throws {
        let core = CountingAgentsCore()
        let page = try await started(core)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        page.refresh(now: t0)
        try await settle("the first refresh") { settled(page) && core.counts.snapshots == 2 }
        page.refresh(force: true, now: t0.addingTimeInterval(1))
        try await settle("the forced refresh") { settled(page) && core.counts.snapshots == 3 }
        let action = try #require(page.paletteActions.first { $0.id == "agents.refresh" })
        #expect(action.title == "Refresh" && action.trailing == "⌘R")
        action.perform()
        try await settle("the palette refresh") { settled(page) && core.counts.snapshots == 4 }
    }

    @Test("a page that has not started reads nothing on refresh")
    func refreshBeforeStart() async throws {
        let core = CountingAgentsCore()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core })
        let page = AgentsPage(env: env)
        page.refresh(force: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(core.counts == CountingAgentsCore.Counts())
    }
}

/// A core for the Agents page: empty inventory, empty rules, and a count of each read.
private final class CountingAgentsCore: UnservedCore, @unchecked Sendable {
    struct Counts: Equatable {
        var rows = 0
        var scans = 0
        var snapshots = 0
    }

    private let lock = NSLock()
    private var _counts = Counts()
    var counts: Counts { lock.withLock { _counts } }

    override func loadoutRows() async throws -> CoreLoadoutRows {
        let scanned = lock.withLock { () -> Bool in _counts.rows += 1; return _counts.scans > 0 }
        return CoreLoadoutRows(
            usage: scanned ? .ready : .scanning, items: [], hooks: [], problems: [], events: [:], roots: ["claude": "/home/demo/.claude", "codex": "/home/demo/.codex"],
            countsByScope: ["global": CoreFilterCounts(all: 0, only: .init(claude: 0, codex: 0), neverRan: 0, dead: 0)], rowFlags: [:]
        )
    }

    override func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult {
        lock.withLock { _counts.scans += 1 }
        return CoreUsageResult(
            totals: CoreUsageTotals(claude: CoreCLITotals(skill: [:], agent: [:], hook: [:]), codex: CoreCLITotals(skill: [:], agent: [:], hook: [:])),
            sessions: CoreUsageSessions(claude: 1, codex: 1),
            windows: CoreUsageWindows(claude: CoreLogWindow(files: 1, oldest: "2026-10-01", newest: nil), codex: CoreLogWindow(files: 1, oldest: "2026-10-09", newest: nil)),
            files: 2
        )
    }

    override func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot {
        lock.withLock { _counts.snapshots += 1 }
        return CoreRulesSnapshot(
            projectDirs: [], globalRuleCount: 0, scope: .global, dir: nil, fileLabel: "~/.claude/settings.json", exists: true, problems: [], rules: [], grid: [],
            codex: CoreCodexPermissions(
                present: true, model: .legacy, unrestricted: false, warnings: [], approvalPolicy: .mode("on-request"), sandboxMode: "workspace-write",
                sandboxWorkspaceWrite: nil, defaultPermissions: nil, approvalsReviewer: nil, profiles: [], projects: [],
                rules: CoreCodexRulesSummary(files: 0, allow: 0, prompt: 0, forbidden: 0, other: 0, unreadable: 0, folderNotReadable: false),
                notReadable: false, skippedLines: 0
            ),
            notReadable: false, globalNotReadable: false
        )
    }
}
