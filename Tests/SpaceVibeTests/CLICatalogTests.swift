import Foundation
import Testing
@testable import SpaceVibe

/// `CLICatalog` (MC27, MC-R2, MC-R4, MC-R5): the facts come from `clis.list` and the look from `CLIRegistry`; an id the core did
/// not list, or one the owner turned off, is dropped from every core result before a page reads it; a copy goes only where
/// the format matches; a kind a CLI lacks reads as absent, never as 0 and never as an add target.
@Suite("CLI catalog: facts from clis.list, one filter", .fixtureCLIs)
struct CLICatalogTests {
    private typealias F = SkillRowsFixture

    // MARK: Synthetic CLIs (never a real one's name)

    /// Codex's facts under another id and name: every concept, the same copy formats.
    static func twin(_ id: String, label: String, installed: Bool = true) -> CoreCLIInfo {
        var info = CLICatalogFixture.info(.codex)
        info.id = CLIID(id)
        info.label = label
        info.installed = installed
        return info
    }

    /// A CLI with skills and subagents but no hooks at all.
    static func withoutHooks() -> CoreCLIInfo {
        var info = twin("nohooks", label: "No Hooks CLI")
        info.kinds = info.kinds.map { kind in
            guard kind.kind == .hook else { return kind }
            return CoreKindInfo(kind: .hook, support: .absent, runs: nil, notLoggedReason: nil, copyFormat: nil)
        }
        info.logsHookRuns = false
        return info
    }

    // MARK: Facts and looks

    @Test("every fact a page reads comes from clis.list, and the look from the table")
    func factsComeFromTheList() throws {
        let catalog = CLICatalogFixture.catalog
        #expect(catalog.all.map(\.id) == [.claude, .codex, .gemini], "the core's registry order")
        let codex = try #require(catalog.info(for: .codex))
        #expect(codex.label == "Codex" && codex.limitsReading == .lastTurn && !codex.logsHookRuns && codex.readsSessionLog)
        #expect(codex.approvalLimitCode == "codex-tool-silent" && !codex.subagentWithoutToolsGetsEveryTool)
        #expect(codex.mark?.fileName == CLIRegistry.look(.codex).mark?.fileName)
        let gemini = try #require(catalog.info(for: .gemini))
        #expect(!gemini.installed && gemini.concepts == [.limits] && !gemini.hasKind(.skill))
        #expect(catalog.inventoryCLIs == [.claude, .codex] && catalog.limitsCLIs == [.claude, .codex, .gemini])

        // The label is the core's: a renamed entry reads the new name, with the same look.
        var renamed = CLICatalogFixture.list
        renamed[1].label = "Codex CLI"
        let other = CLICatalog(list: renamed)
        #expect(other.identity(.codex).label == "Codex CLI")
        #expect(other.identity(.codex).mark?.fileName == "codex-blossom-white.svg")
    }

    @Test("a CLI the core lists with no look takes the neutral look, never another CLI's")
    func neutralLook() throws {
        let catalog = CLICatalog(list: CLICatalogFixture.list + [Self.twin("newcli", label: "New CLI")])
        let new = try #require(catalog.info(for: CLIID("newcli")))
        #expect(new.label == "New CLI")
        #expect(new.mark == nil, "no mark: CLIMark draws the tone's dot")
        #expect(new.tone.fillValue.light == CLIRegistry.neutral.tone.fillValue.light)
        #expect(new.tone.fillValue.dark == CLIRegistry.neutral.tone.fillValue.dark)
        #expect(catalog.inventoryCLIs == [.claude, .codex, CLIID("newcli")])
    }

    @Test("an id clis.list did not return is not shown: no facts, no list, no look of its own")
    func unlistedIsNotShown() {
        let catalog = CLICatalogFixture.catalog
        let cursor = CLIID("cursor")
        #expect(catalog.info(for: cursor) == nil && !catalog.isShown(cursor))
        #expect(!catalog.inventoryCLIs.contains(cursor) && !catalog.limitsCLIs.contains(cursor))
        #expect(catalog.identity(cursor).label == "cursor" && catalog.identity(cursor).concepts.isEmpty)
        #expect(CLICatalog.empty.shown.isEmpty)
    }

    // MARK: Unknown ids on the wire

    @Test("a report with an unknown cli decodes without failing, and the filter drops it from sessions, failures, files and limits")
    func unknownCLIInReport() throws {
        let json = #"""
        {"sessions":[{"cli":"codex","id":"a","title":"t","project":null,"pid":7,"state":"running","stateReason":"r","reasonCode":null,"currentTool":null,"ageMs":null,"lastWriteAgoMs":null,"cost":null,"costNote":null},
                     {"cli":"cursor","id":"b","title":"u","project":null,"pid":8,"state":"running","stateReason":"r","reasonCode":null,"currentTool":null,"ageMs":null,"lastWriteAgoMs":null,"cost":null,"costNote":null}],
         "failures":[{"kind":"command","cli":"cursor","key":"k","title":"x","count":1,"exit":1,"reason":"r","projects":[],"sessions":1,"first":null,"last":null,"laterPass":null,"hook":null}],
         "files":[{"path":"/p/a","label":"a","edits":2,"sessions":1,"last":null,"clis":["cursor"],"projects":[]},
                  {"path":"/p/b","label":"b","edits":1,"sessions":1,"last":null,"clis":["claude","cursor"],"projects":[]}],
         "unmeasurable":[{"cli":"cursor","code":"cursor-x","text":"x"}],"stats":{"logs":0,"truncated":0}}
        """#
        let report = try JSONDecoder().decode(CoreActivityReport.self, from: Data(json.utf8))
        #expect(report.sessions.map(\.cli.rawValue) == ["codex", "cursor"], "decoding keeps the id")
        let shown = CLICatalog.current.shown(report)
        #expect(shown.sessions.map(\.id) == ["a"])
        #expect(shown.failures.isEmpty && shown.unmeasurable.isEmpty)
        #expect(shown.files.map(\.path) == ["/p/b"] && shown.files[0].clis == [.claude])
        #expect(GlanceEntries(report: shown).all.map(\.cli) == [.codex], "the widget never shows it")

        let limits = try JSONDecoder().decode(CoreLimitsResult.self, from: Data(#"""
        {"limits":[{"cli":"cursor","state":"notMeasurable","plan":null,"source":null,"at":null,"windows":[]},
                   {"cli":"claude","state":"notRecorded","plan":null,"source":null,"at":null,"windows":[]}]}
        """#.utf8))
        #expect(CLICatalog.current.shown(limits.limits).map(\.cli) == [.claude])
    }

    @Test("an inventory with an unknown cli decodes without failing, and no row, cell, event or root of it reaches the page")
    func unknownCLIInInventory() throws {
        var rows = F.snapshot([("a", F.counted(2), nil, "user", nil)])
        // The wire adds a CLI the shell has never heard of: its own skill, a cell on the Claude skill, events and a root.
        let foreign = F.item("b", cli: CLIID("cursor"), cells: CoreCells([.claude: .missing, .codex: .missing, CLIID("cursor"): F.counted(1)]))
        rows.items[0].cells?[CLIID("cursor")] = .missing
        rows.items.append(foreign)
        rows.events.append(CoreCLIEvents(cli: CLIID("cursor"), events: ["Stop"]))
        rows.roots.append(CoreCLIRoot(cli: CLIID("cursor"), root: "/home/demo/.cursor"))
        let decoded = try JSONDecoder().decode(CoreLoadoutRows.self, from: JSONEncoder().encode(rows))
        #expect(decoded.items.count == 2)

        let shown = CLICatalog.current.shown(decoded)
        #expect(shown.items.map(\.name) == ["a"])
        #expect(shown.items[0].cells?.clis == [.claude, .codex])
        #expect(shown.events.map(\.cli) == [.claude, .codex] && shown.roots.map(\.cli) == [.claude, .codex])
        let data = LoadoutData.build(raw: shown)
        #expect(data.rows.map(\.name) == ["a"] && data.rows[0].presentCLIs == [.claude])
        #expect(data.events.keys.sorted { $0.rawValue < $1.rawValue } == [.claude, .codex])
    }

    // MARK: Copy targets

    @Test("a copy goes only to a shown CLI that writes the kind in the same format; today that is the other CLI")
    func copyTargets() {
        let fixture = CLICatalogFixture.catalog
        for kind in [CoreKind.skill, .agent, .hook] {
            #expect(fixture.copyTargets(for: kind, from: .claude) == [.codex], "\(kind)")
            #expect(fixture.copyTargets(for: kind, from: .codex) == [.claude], "\(kind)")
        }
        #expect(fixture.copyTargets(for: .skill, from: .gemini).isEmpty, "Gemini CLI has no skills")

        var otherFormat = Self.twin("folders", label: "Other Format CLI")
        otherFormat.kinds[0].copyFormat = "markdownFile"
        var readOnly = Self.twin("readonly", label: "Read Only CLI")
        readOnly.kinds[0].support = .readOnly
        let wide = CLICatalog(list: CLICatalogFixture.list + [otherFormat, readOnly, Self.withoutHooks(), Self.twin("spare", label: "Spare CLI")],
                              disabled: [CLIID("spare")])
        #expect(wide.copyTargets(for: .skill, from: .claude) == [.codex, CLIID("nohooks")],
                "not another format, not read-only, not a CLI turned off")
        #expect(wide.copyTargets(for: .hook, from: .claude) == [.codex, CLIID("folders"), CLIID("readonly")], "not a CLI without hooks")
        #expect(wide.copySources(for: .skill, to: .codex) == [.claude, CLIID("readonly"), CLIID("nohooks")],
                "a read-only CLI can be copied from, never into")
    }

    // MARK: Turning a CLI off (MC-R4)

    static func codexOff() -> CLICatalog { CLICatalog(list: CLICatalogFixture.list, disabled: [.codex]) }

    @Test("a CLI turned off leaves every list, every result and the missing-in comparison")
    func turnedOff() throws {
        let off = Self.codexOff()
        #expect(off.all.count == 3 && off.shown.map(\.id) == [.claude, .gemini])
        #expect(off.inventoryCLIs == [.claude] && off.limitsCLIs == [.claude, .gemini])
        #expect(!off.isEnabled(.codex) && off.isEnabled(.claude) && off.isEnabled(CLIID("never-listed")))
        #expect(off.identity(.codex).label == "Codex", "a CLI that is off keeps its name where a page still names it")

        // Built as the app builds rows: the skill in both CLIs is Claude Code's only; nothing offers Codex as a target.
        try CLICatalog.$scoped.withValue(off) {
            let raw = F.snapshot([("both", F.counted(2), F.counted(1), "user", nil), ("claudeOnly", F.counted(0), nil, "user", nil),
                                  ("codexOnly", nil, F.counted(3), "user", nil)])
            let data = LoadoutData.build(raw: off.shown(raw))
            #expect(data.rows.map(\.name).sorted() == ["both", "claudeOnly"], "a row only Codex has is gone")
            let both = try #require(data.rows.first { $0.name == "both" })
            #expect(both.presentCLIs == [.claude] && both.cells.clis == [.claude])
            let claudeOnly = try #require(data.rows.first { $0.name == "claudeOnly" })
            #expect(LoadoutRows.copyPlan(claudeOnly, to: .codex, events: data.events) == nil)
            #expect(claudeOnly.copyTarget(from: .claude) == nil, "the `a` key has nowhere to go")
            let verdict = SkillsWording.verdict(for: claudeOnly, status: .neverRan, detected: [.claude])
            #expect(verdict.map { !$0.text.contains("Codex") && $0.small?.contains("Codex") != true } == true, "no \"missing in Codex\"")
            #expect(SkillsFilterField.cli.values.map(\.id).contains("codex") == false, "no Codex filter")
        }

        let report = try JSONDecoder().decode(CoreActivityReport.self, from: Data(#"""
        {"sessions":[{"cli":"codex","id":"a","title":"t","project":null,"pid":7,"state":"running","stateReason":"r","reasonCode":null,"currentTool":null,"ageMs":null,"lastWriteAgoMs":null,"cost":null,"costNote":null}],
         "failures":[],"files":[],"unmeasurable":[{"cli":"codex","code":"codex-tool-silent","text":"x"}],"stats":{"logs":1,"truncated":0}}
        """#.utf8))
        #expect(off.shown(report).sessions.isEmpty && off.shown(report).unmeasurable.isEmpty)
    }

    @Test("with a CLI off the chip counts and row flags are counted again without it")
    func countsWithoutTheHiddenCLI() throws {
        let off = Self.codexOff()
        var raw = F.snapshot([("both", F.counted(2), F.counted(1), "user", nil), ("codexOnly", nil, F.counted(3), "user", nil)])
        raw.countsByScope = ["global": CoreFilterCounts(all: 2, only: .of([.claude: 0, .codex: 1]), neverRan: 0, dead: 0)]
        raw.rowFlags = ["skill::both": CoreRowFlags(one: false, neverRan: false, dead: false),
                        "skill::codexOnly": CoreRowFlags(one: true, neverRan: false, dead: false)]
        let shown = off.shown(raw)
        #expect(shown.countsByScope["global"] == CoreFilterCounts(all: 1, only: .of([.claude: 1]), neverRan: 0, dead: 0))
        #expect(shown.rowFlags == ["skill::both": CoreRowFlags(one: true, neverRan: false, dead: false)])
        // Nothing hidden: the core's own numbers pass through untouched.
        #expect(CLICatalogFixture.catalog.shown(raw).countsByScope == raw.countsByScope)
        #expect(CLICatalogFixture.catalog.shown(raw).rowFlags == raw.rowFlags)
    }

    @Test("counting again follows the core's rule: on the fixture home after a scan it gives the core's counts and flags", .timeLimit(.minutes(1)))
    func recountMatchesTheCore() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        _ = try await client.usageScan(progress: nil)
        let rows = try await client.loadoutRows()
        #expect(rows.usage == .ready && rows.countsByScope.count > 1, "a global scope and at least one project")
        #expect(CLICatalog.countsByScope(items: rows.items, hooks: rows.hooks, clis: CLICatalogFixture.catalog.inventoryCLIs) == rows.countsByScope)
        #expect(CLICatalog.rowFlags(items: rows.items, hooks: rows.hooks, clis: CLICatalogFixture.catalog.inventoryCLIs) == rows.rowFlags)
    }

    // MARK: Absent kinds (MC-R5)

    /// Claude Code and a CLI without hooks; the core writes `absent` for that CLI on every hook row.
    static func absentCatalog() -> CLICatalog {
        CLICatalog(list: [CLICatalogFixture.info(.claude), Self.withoutHooks()])
    }

    @Test("a hook row in a CLI without hooks reads absent: no count, no add target, its own sentence")
    func absentHooks() throws {
        let catalog = Self.absentCatalog()
        let nohooks = CLIID("nohooks")
        try CLICatalog.$scoped.withValue(catalog) {
            let hook = CoreInventoryHook(
                id: "claude:hook:h1", cli: .claude, kind: .hook, event: "Stop", matcher: nil, command: "/home/demo/x.sh", timeout: nil, async: false,
                owner: "user", removable: true, dead: false, paths: [], hash: "h1", file: "/home/demo/.claude/settings.json", scope: .global,
                project: nil, key: "hook::h1", cells: CoreCells([.claude: .counted(runs: 4, last: nil, errors: 0), nohooks: .absent]), usage: nil)
            let raw = CoreLoadoutRows(usage: .ready, items: [], hooks: [hook], problems: [], events: .of([.claude: ["Stop"]]),
                                      roots: .of([.claude: "/home/demo/.claude"]), countsByScope: [:], rowFlags: [:])
            let data = LoadoutData.build(raw: catalog.shown(raw))
            let row = try #require(data.rows.first)
            #expect(row.cells[nohooks] == .absent && row.hookRun(in: nohooks) == .absent)
            #expect(HooksWording.runs(.absent).isEmpty, "never a 0")
            #expect(LoadoutRows.copyPlan(row, to: nohooks, events: data.events) == nil)
            #expect(LoadoutRows.hookCopyBlock(row, to: nohooks, events: data.events) == .absent(nohooks))
            #expect(row.copyTarget(from: .claude) == nil)
            let context = HooksContext(events: data.events, detected: [.claude, nohooks])
            #expect(HooksWording.lines(for: row, context: context, home: nil).contains("No Hooks CLI has no hooks."))
            #expect(HooksWording.short(.absent(nohooks)) == "No Hooks CLI has no hooks")
            #expect(LoadoutRows.logoMode(row, cli: nohooks, events: data.events) == .readOnly)
            // Absent is not present: the row is in one CLI.
            #expect(CLICatalog.filterCounts(CLICatalog.countedRows(items: [], hooks: [hook]), clis: [.claude, nohooks]).only
                    == .of([.claude: 1, nohooks: 0]))
        }
    }

    @Test("a skill cell of a CLI without skills reads absent in the pane, never 0, and is not a place to add")
    func absentSkills() throws {
        var info = Self.twin("noskills", label: "No Skills CLI")
        info.kinds[0] = CoreKindInfo(kind: .skill, support: .absent, runs: nil, notLoggedReason: nil, copyFormat: nil)
        let catalog = CLICatalog(list: [CLICatalogFixture.info(.claude), info])
        let noskills = CLIID("noskills")
        try CLICatalog.$scoped.withValue(catalog) {
            let item = F.item("a", cli: .claude, cells: CoreCells([.claude: F.counted(5), noskills: .absent]))
            let raw = CoreLoadoutRows(usage: .ready, items: [item], hooks: [], problems: [], events: [], roots: [], countsByScope: [:], rowFlags: [:])
            let row = try #require(LoadoutData.build(raw: catalog.shown(raw)).rows.first)
            #expect(row.skillUsage.cells[noskills] == .absent && row.skillUsage.present == [.claude])
            let meter = SkillsWording.meter(for: row, cli: noskills, maxSessions: 5, now: F.now)
            #expect(meter.status == "No Skills CLI has no skills" && meter.figure == nil && meter.share == nil)
            #expect(LoadoutRows.copyPlan(row, to: noskills, events: [:]) == nil)
            #expect(LoadoutRows.logoMode(row, cli: noskills, events: [:]) == .readOnly)
            let plan = LoadoutRows.addWrites([row], to: noskills, events: [:])
            #expect(plan.steps.isEmpty && plan.skipped == 1)
        }
    }
}
