import Foundation
import Testing
@testable import SpaceVibe

/// The Hooks tab's derived facts (V5-A18): the Answer in each case, the bands, the ONE copy rule and the two small-card lists
/// it feeds, the filters and the sentences. Rows are built through `LoadoutRows.build`, as the app builds them (`HooksSynthetic`).
/// Synthetic names only (S-R2).
@Suite("Hooks model")
@MainActor
struct HooksModelTests {
    /// The core's `Events()`: Codex lacks `PostToolUseFailure`, `Notification` and others; the lists are in lifecycle order.
    private let events: [String: [String]] = [
        "claude": ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification",
                   "SubagentStart", "SubagentStop", "Stop", "SessionEnd"],
        "codex": ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop", "Interrupt",
                  "Stop", "SessionEnd"],
    ]
    private let both: [CoreCLI] = [.claude, .codex]

    private func rows(_ specs: [HooksSynthetic.Spec]) -> [LoadoutRow] { HooksSynthetic.rows(specs, events: events) }

    private func spec(_ name: String, _ event: String, _ clis: [CoreCLI] = [.claude], runs: Int = 5, dead: Bool = false, plugin: String? = nil,
                      matcher: String? = nil) -> HooksSynthetic.Spec {
        HooksSynthetic.Spec(name: name, event: event, matcher: matcher, clis: clis, runs: runs, dead: dead, plugin: plugin)
    }

    private func context(_ detected: [CoreCLI] = [.claude, .codex], codexTakesHooks: Bool = false) -> HooksContext {
        HooksContext(events: events, detected: detected, codexTakesHooks: codexTakesHooks)
    }

    private func answer(_ rows: [LoadoutRow], loaded: Bool = true, _ context: HooksContext? = nil) -> HooksAnswer {
        HooksAnswer.of(rows, isLoaded: loaded, context: context ?? self.context())
    }

    // MARK: The Answer (V5-A18)

    @Test("a problem: the sentence counts the hooks that cannot run, a row names each, no Copy row while Codex takes none")
    func oneProblem() {
        let list = rows([spec("gone", "Stop", dead: true), spec("fine", "PreToolUse")])
        let result = answer(list)
        #expect(result.sentence == "1 hook can't run." && result.dead.map(\.hookTitle) == ["gone.sh"] && result.more == 0 && result.missing.isEmpty)
    }

    @Test("several problems: the sentence counts them all, the first three are rows, the rest are \"N more\"")
    func severalProblems() {
        let list = rows((1 ... 5).map { spec("gone-\($0)", "Stop", dead: true) } + [spec("fine", "PreToolUse")])
        let result = answer(list)
        #expect(result.sentence == "5 hooks can't run." && result.dead.count == HooksAnswer.shownDead && result.more == 2)
        #expect(result.dead.map(\.hookTitle) == ["gone-1.sh", "gone-2.sh", "gone-3.sh"], "by name")
    }

    @Test("nothing needs the user")
    func healthy() {
        let result = answer(rows([spec("fine", "PreToolUse", both), spec("other", "Stop")]))
        #expect(result.sentence == "Nothing needs you." && result.dead.isEmpty && result.missing.isEmpty)
    }

    @Test("no hooks, and no inventory yet")
    func noneAndLoading() {
        #expect(answer([]).sentence == "No hooks yet.")
        #expect(answer([], loaded: false).sentence == nil, "while the inventory loads the card shows its skeleton")
        #expect(HooksAnswer.of([], isLoaded: true, context: context(), notShown: true).sentence == "No hooks to show.", "hooks of another handler kind exist: \"none\" would be false")
    }

    @Test("Codex not installed: nothing is compared, so no hook is missing in Codex even if Codex would take hooks")
    func codexNotInstalled() {
        let list = rows([spec("gone", "Stop", dead: true), spec("fine", "PreToolUse")])
        let there = context([.claude], codexTakesHooks: true)
        #expect(answer(list, there).sentence == "1 hook can't run.")
        #expect(HooksMissing(list, context: there).isEmpty && HooksCantCopy(list, context: there).isEmpty)
    }

    @Test("when Codex takes hooks: the sentence joins both halves, or says only the second; the copy row's hooks are the rule's")
    func missingInCodex() {
        let taking = context(codexTakesHooks: true)
        let list = rows([spec("gone", "Stop", dead: true), spec("a", "PreToolUse"), spec("b", "Stop"), spec("c", "Notification"), spec("both", "Stop", both)])
        let result = answer(list, taking)
        #expect(result.sentence == "1 hook can't run, 2 are missing in Codex." && result.missing.map(\.hookTitle) == ["a.sh", "b.sh"],
                "c has no Codex event and gone has no script, so neither is offered")
        #expect(answer(rows([spec("a", "PreToolUse")]), taking).sentence == "1 hook is missing in Codex.")
        #expect(answer(rows([spec("a", "PreToolUse"), spec("b", "Stop")]), taking).sentence == "2 hooks are missing in Codex.")
    }

    // MARK: The one copy rule (V5-R66)

    @Test("each reason, in the rule's order, and the rule's default: SpaceVibe writes no hook into Codex")
    func reasons() throws {
        let list = rows([spec("stop", "Stop"), spec("failure", "PostToolUseFailure"), spec("gone", "Stop", dead: true), spec("plug", "Stop", plugin: "neon")])
        func block(_ name: String, to: CoreCLI = .codex, in c: HooksContext? = nil) throws -> LoadoutRows.HookCopyBlock? {
            let row = try #require(list.first { $0.hookTitle == "\(name).sh" })
            return (c ?? context()).block(row, to: to)
        }
        #expect(try block("stop") == .notWritten(.codex))
        #expect(try block("failure") == .noEvent(.codex, event: "PostToolUseFailure"))
        #expect(try block("gone") == .scriptGone)
        #expect(try block("plug") == .plugin("neon"))
        #expect(try block("stop", in: context(codexTakesHooks: true)) == nil, "the one constant to flip")
        #expect(try block("stop", in: context([.claude])) == .notInstalled(.codex))
        #expect(LoadoutRows.codexTakesHooks == false, "the core refuses a hook copy into Codex (go-core G-fix.16)")
    }

    @Test("a Codex-only hook goes to Claude Code when Claude Code has the event; Interrupt has no Claude Code event")
    func intoClaude() throws {
        let list = rows([spec("pre", "PreToolUse", [.codex]), spec("stop", "Interrupt", [.codex])])
        #expect(context().block(list.first { $0.hookTitle == "pre.sh" }!, to: .claude) == nil)
        #expect(context().block(list.first { $0.hookTitle == "stop.sh" }!, to: .claude) == .noEvent(.claude, event: "Interrupt"))
    }

    @Test("the rule and copyPlan agree: a block is nil exactly when the copy is offered, for every hook, both ways")
    func ruleAgreesWithCopyPlan() {
        let list = rows(HooksSynthetic.sample)
        for row in list {
            for cli in CoreCLI.allCases where row.members[cli] == nil {
                let block = LoadoutRows.hookCopyBlock(row, to: cli, events: events)
                let plan = LoadoutRows.copyPlan(row, to: cli, events: events)
                #expect((block == nil) == (plan != nil), "\(row.hookTitle) to \(cli.label): \(String(describing: block)) vs \(String(describing: plan))")
                #expect(HooksWording.long(block ?? .scriptGone).isEmpty == false)
            }
        }
        // And with Codex taking hooks, the rule opens Codex up and nothing else.
        for row in list where row.members[.codex] == nil {
            let on = LoadoutRows.hookCopyBlock(row, to: .codex, events: events, codexTakesHooks: true)
            #expect(on != .notWritten(.codex), "\(row.hookTitle)")
        }
    }

    @Test("the logos: a CLI that cannot take the hook has no toggle at all; the only copy and a plugin's are not toggles")
    func logos() {
        let model = HooksModel(loadout: LoadoutModel(env: .shared, data: data(rows([
            spec("pre", "PreToolUse", [.codex]), spec("stop", "Stop"), spec("shared", "Stop", both), spec("plug", "Stop", plugin: "neon")]))))
        model.limitsResults = { [] }
        func row(_ name: String) -> LoadoutRow { model.rows.first { $0.hookTitle == "\(name).sh" }! }
        #expect(model.showsToggle(row("pre"), cli: .claude) && model.mode(row("pre"), cli: .claude) == .toggles)
        #expect(model.mode(row("pre"), cli: .codex) == .onlyCopy)
        #expect(!model.showsToggle(row("stop"), cli: .codex), "Codex cannot take it: nothing to press")
        #expect(model.mode(row("stop"), cli: .claude) == .onlyCopy)
        #expect(model.mode(row("shared"), cli: .codex) == .toggles && model.mode(row("shared"), cli: .claude) == .toggles)
        #expect(model.mode(row("plug"), cli: .claude) == .readOnly)
    }

    private func data(_ rows: [LoadoutRow]) -> LoadoutData {
        LoadoutData(rows: rows, scopes: [LoadoutScope(value: LoadoutRows.globalScope, label: "Global")], countsByScope: [:], problems: [],
                    events: events, globalCount: rows.count, home: nil)
    }

    // MARK: Bands

    @Test("shared events in lifecycle order, then Claude Code's own, then Codex's own; a one-CLI event carries that CLI")
    func bandOrder() {
        let list = rows([spec("a", "Stop", both), spec("b", "PreToolUse", both), spec("c", "Notification"), spec("d", "Interrupt", [.codex]),
                         spec("e", "SessionStart", both), spec("f", "PostToolUseFailure")])
        let layout = HooksQuery().layout(list, context: context())
        #expect(layout.bands.map(\.event) == ["SessionStart", "PreToolUse", "Stop", "PostToolUseFailure", "Notification", "Interrupt"])
        #expect(layout.bands.map(\.lead) == [nil, nil, nil, .claude, .claude, .codex])
    }

    @Test("a band with a hook that cannot run comes first, with the problem flag; the order is otherwise kept")
    func problemFirst() {
        let list = rows([spec("a", "SessionStart"), spec("b", "PostToolUse", dead: true), spec("c", "Notification", dead: true), spec("d", "Stop")])
        let layout = HooksQuery().layout(list, context: context())
        #expect(layout.bands.map(\.event) == ["PostToolUse", "Notification", "SessionStart", "Stop"])
        #expect(layout.bands.map(\.holdsProblem) == [true, true, false, false])
        #expect(layout.bands[0].rows.first?.isDeadHook == true)
    }

    @Test("a hook on an event neither CLI lists still gets its band, after the listed ones; never dropped")
    func unknownEvent() {
        let list = rows([spec("a", "Stop", both), spec("b", "FileChanged"), spec("c", "Setup", [.codex])])
        let layout = HooksQuery().layout(list, context: context())
        #expect(layout.bands.map(\.event) == ["Stop", "FileChanged", "Setup"])
        #expect(layout.bands.map(\.lead) == [nil, .claude, .codex], "an event only one CLI's hooks name carries that CLI")
    }

    @Test("a band opens by default when it holds a problem, else the first opens")
    func defaultOpen() {
        let withProblem = HooksQuery().layout(rows([spec("a", "SessionStart"), spec("b", "Stop", dead: true)]), context: context())
        #expect(HooksCanvas.opensByDefault(withProblem, 0) && !HooksCanvas.opensByDefault(withProblem, 1))
        let calm = HooksQuery().layout(rows([spec("a", "SessionStart"), spec("b", "Stop")]), context: context())
        #expect(HooksCanvas.opensByDefault(calm, 0) && !HooksCanvas.opensByDefault(calm, 1))
    }

    // MARK: The two small cards

    @Test("Can't copy to Codex lists every Claude Code hook Codex lacks with its reason, event and script reasons first; dropped when empty")
    func cantCopyCard() {
        let list = rows([spec("stop", "Stop"), spec("failure", "PostToolUseFailure"), spec("gone", "Stop", dead: true), spec("shared", "Stop", both),
                         spec("codex", "PreToolUse", [.codex])])
        let card = HooksCantCopy(list, context: context())
        #expect(card.entries.map(\.row.hookTitle) == ["failure.sh", "gone.sh", "stop.sh"])
        #expect(card.entries.map { HooksWording.short($0.block) } == ["No PostToolUseFailure event", "Script is gone", "SpaceVibe doesn't write Codex hooks"])
        #expect(HooksCantCopy(rows([spec("shared", "Stop", both)]), context: context()).isEmpty)
        #expect(HooksWording.why(card.entries).count == 3)
    }

    @Test("Missing in Codex is empty while Codex takes no hook; with it on, the rows are the ones the rule lets through")
    func missingCard() {
        let list = rows([spec("a", "PreToolUse"), spec("b", "Notification"), spec("c", "Stop", dead: true)])
        #expect(HooksMissing(list, context: context()).isEmpty)
        #expect(HooksMissing(list, context: context(codexTakesHooks: true)).rows.map(\.hookTitle) == ["a.sh"])
        #expect(HooksCantCopy(list, context: context(codexTakesHooks: true)).entries.map(\.row.hookTitle) == ["b.sh", "c.sh"])
    }

    // MARK: Filters

    @Test("CLI presence, Status and Event: AND across fields, OR within one")
    func filters() {
        let list = rows([spec("a", "Stop", both), spec("b", "Stop"), spec("c", "PreToolUse", [.codex]), spec("d", "Stop", dead: true)])
        var query = HooksQuery()
        func titles() -> [String] { query.layout(list, context: context()).rows.map(\.hookTitle).sorted() }
        query.filter.toggle(.cli, "both")
        #expect(titles() == ["a.sh"])
        query.filter.toggle(.cli, "codex")
        #expect(titles() == ["a.sh", "c.sh"], "OR within a field")
        query.filter.clear()
        query.filter.toggle(.status, "cantRun")
        #expect(titles() == ["d.sh"])
        query.filter.toggle(.event, "PreToolUse")
        #expect(titles().isEmpty, "AND across fields")
        query.filter.clear()
        query.filter.toggle(.status, "cantCopy")
        #expect(titles() == ["b.sh", "d.sh"], "Claude Code hooks Codex lacks; a's Codex copy exists and c is Codex's")
        query.filter.clear()
        query.filter.toggle(.event, "Stop")
        #expect(titles() == ["a.sh", "b.sh", "d.sh"])
    }

    @Test("the Status field offers Missing in Codex only while Codex takes hooks; Event lists the events that have a hook, in lifecycle order")
    func filterValues() {
        #expect(HooksFilterField.status.values.map(\.id) == ["cantRun", "cantCopy"])
        #expect(HooksFilterField.cli.values.map(\.id) == ["both", "claude", "codex"])
        let list = rows([spec("a", "Stop"), spec("b", "PreToolUse"), spec("c", "Interrupt", [.codex])])
        #expect(HooksQuery.eventValues(events: events, rows: list).map(\.id) == ["PreToolUse", "Stop", "Interrupt"])
    }

    // MARK: The row's facts and sentences

    @Test("a Claude Code hook with no run reads Never ran; Codex runs read Unmeasurable, never a number; the clock only where nothing counts")
    func runsAndSlot() {
        let list = rows([spec("never", "Stop", runs: 0), spec("shared", "Stop", both, runs: 1204), spec("codex", "Stop", [.codex]),
                         spec("gone", "Stop", dead: true), spec("plug", "Stop", plugin: "neon")])
        func row(_ name: String) -> LoadoutRow { list.first { $0.hookTitle == "\(name).sh" }! }
        #expect(row("never").hookRun(in: .claude) == .neverRan && HooksWording.slot(for: row("never"), home: nil) == nil)
        #expect(row("shared").hookRun(in: .claude) == .ran(1204, last: "2026-11-05") && row("shared").hookRun(in: .codex) == .unmeasurable)
        #expect(HooksWording.slot(for: row("shared"), home: nil) == nil, "Claude Code counts it: no clock on a row in both")
        #expect(HooksWording.slot(for: row("codex"), home: nil)?.mark.label == "Unmeasurable")
        #expect(HooksWording.slot(for: row("gone"), home: nil)?.mark.kind == .danger)
        #expect(HooksWording.slot(for: row("gone"), home: nil)?.sentence == "Its script /Users/demo/.claude/scripts/gone.sh is gone, so this hook can't run.")
        #expect(HooksWording.slot(for: row("plug"), home: nil)?.mark.kind == .lock)
        #expect(HooksWording.runs(.unmeasurable) == "runs Unmeasurable" && HooksWording.runs(.ran(1, last: nil)) == "1 run" && HooksWording.runs(.ran(1204, last: nil)) == "1204 runs")
    }

    @Test("the detail says one line per CLI: handler, matcher and runs, or why the hook is not there")
    func detailLines() throws {
        let list = rows([spec("shared", "PostToolUse", both, runs: 9, matcher: "Edit|Write"), spec("claude", "Stop"), spec("codex", "PreToolUse", [.codex])])
        func lines(_ name: String, _ c: HooksContext? = nil) throws -> [String] {
            HooksWording.lines(for: try #require(list.first { $0.hookTitle == "\(name).sh" }), context: c ?? context(), home: nil)
        }
        #expect(try lines("shared") == ["Claude Code: command handler, matcher Edit|Write, 9 runs.", "Codex: command handler, matcher Edit|Write, runs Unmeasurable."])
        #expect(try lines("claude") == ["Claude Code: command handler, no matcher, 5 runs.", "Codex: not there. SpaceVibe does not write hooks into Codex."])
        #expect(try lines("claude", context(codexTakesHooks: true)).last == "Codex: not there. Press A to copy it.")
        #expect(try lines("codex") == ["Claude Code: not there. Press A to copy it.", "Codex: command handler, no matcher, runs Unmeasurable."])
        #expect(try lines("claude", context([.claude])).count == 1, "a CLI that is not installed has no line")
    }

    @Test("a hook gets a name from its script, else its command; the core's line about other handler kinds is the only trace of them")
    func namesAndNotShown() throws {
        let row = try #require(rows([spec("guard", "Stop")]).first)
        #expect(row.hookTitle == "guard.sh" && row.firstHook?.command == "sh '/Users/demo/.claude/scripts/guard.sh'")
        let inline = LoadoutRows.build(CoreLoadoutRows(usage: .ready, items: [], hooks: [{
            var hook = row.firstHook!
            hook.paths = []
            hook.command = "prettier --write \"$FILE\""
            return hook
        }()], problems: [], events: events, roots: [:], countsByScope: [:], rowFlags: [:]), home: nil)
        #expect(inline.first?.hookTitle == "prettier --write \"$FILE\"")
        #expect(HooksWording.isOtherTypesProblem("2 hooks of other types are not shown.") && HooksWording.isOtherTypesProblem("1 hook of another type is not shown."))
        #expect(!HooksWording.isOtherTypesProblem("/x/settings.json is not valid JSON, so its hooks cannot be shown or changed."))
    }
}
