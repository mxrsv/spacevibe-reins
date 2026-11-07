import Foundation
import Testing
@testable import SpaceVibe

/// The Rules tab's derived facts (V5-R67, V5-R68; C18, G12): families from `RuleItem.tool`, stances, the one Codex fact per family and
/// what it may be compared with, redundant rules, and the Answer's cases (V5-A18). Pure: no core, no window.
@Suite("Rule families")
struct RuleFamiliesTests {
    private static func rule(_ text: String, _ verdict: CoreVerdict) -> CoreRule { RulesSynthetic.rule(text, verdict) }

    private static func reading(_ sandbox: String? = "workspace-write", approval: String? = "on-request", installed: Bool = true, present: Bool = true,
                                model: CoreCodexModel = .legacy, profile: String? = nil, notReadable: Bool = false) -> CodexReading {
        CodexReading(codex: RulesSynthetic.codex(sandbox: sandbox, approval: approval, present: present, model: model, profile: profile, notReadable: notReadable),
                     installed: installed)
    }

    private static func layout(_ rules: [CoreRule], _ reading: CodexReading = reading(), filter: RulesFilter = RulesFilter()) -> RulesLayout {
        RulesLayout(rules: rules, reading: reading, filter: filter)
    }

    private static func page(_ rules: [CoreRule], codex: CoreCodexPermissions = RulesSynthetic.codex(), installed: Bool = true, problems: [String] = [],
                             notReadable: Bool = false, filter: RulesFilter = RulesFilter()) -> RulesPage {
        RulesPage(snapshot: RulesSynthetic.snapshot(rules, codex: codex, problems: problems, notReadable: notReadable), failure: nil, codexInstalled: installed, filter: filter)
    }

    // MARK: Families

    @Test("a rule's family comes from its tool: Edit, Write and MultiEdit are one family, mcp__ is MCP, the rest is Other tools")
    func familyFromTool() {
        let cases: [(String?, RuleFamily)] = [
            ("Bash", .bash), ("Edit", .edit), ("Write", .edit), ("MultiEdit", .edit), ("Read", .read), ("WebFetch", .web), ("WebSearch", .web),
            ("mcp__neon__run_sql", .mcp), ("mcp__playwright", .mcp), ("Skill", .other), ("NotebookEdit", .other), ("Glob", .other), (nil, .other),
        ]
        for (tool, family) in cases {
            let name = tool ?? "nil"
            #expect(RuleFamily.of(tool: tool) == family, "\(name)")
        }
        // The tool of a parsed rule is the name before the parenthesis.
        #expect(Self.rule("Bash(git push:*)", .deny).tool == "Bash" && Self.rule("mcp__neon__run_sql", .ask).tool == "mcp__neon__run_sql")
    }

    @Test("a family's stance is its one verdict, or the count of each verdict in order")
    func stance() {
        #expect(FamilyStance([Self.rule("WebFetch", .deny), Self.rule("WebSearch", .deny)]).summary == "Deny")
        #expect(FamilyStance([Self.rule("WebFetch", .deny)]).single == .deny)
        let mixed = FamilyStance([Self.rule("Bash(a)", .deny), Self.rule("Bash(b)", .allow), Self.rule("Bash(c)", .allow), Self.rule("Bash(d)", .ask)])
        #expect(mixed.summary == "Allow 2 \u{00B7} Ask 1 \u{00B7} Deny 1" && mixed.single == nil && mixed.isMixed)
        #expect(FamilyStance([]).summary == "" && FamilyStance([]).single == nil && !FamilyStance([]).isMixed)
    }

    // MARK: Codex facts

    @Test("Bash and Edit/Write carry Codex's sandbox mode; Read, Web, MCP and Other tools carry nothing (G12)")
    func factPerFamily() {
        let reading = Self.reading("workspace-write")
        #expect(CodexFact.of(.bash, reading)?.text == "Sandbox: workspace-write")
        #expect(CodexFact.of(.edit, reading)?.text == "Sandbox: workspace-write")
        for family in [RuleFamily.read, .web, .mcp, .other] { #expect(CodexFact.of(family, reading) == nil, "\(family.title)") }
    }

    @Test("only a fact that says on or off is compared: full access writes anywhere, read only edits nothing only while approvals are never, a workspace is neither; Bash never")
    func comparableFacts() {
        #expect(CodexFact.of(.edit, Self.reading("danger-full-access"))?.isOpen == true)
        #expect(CodexFact.of(.edit, Self.reading("read-only", approval: "never"))?.isOpen == false)
        for approval in ["on-request", "untrusted", "on-failure", nil] { #expect(CodexFact.of(.edit, Self.reading("read-only", approval: approval))?.isOpen == nil, "read-only and \(approval ?? "no policy"): Codex may ask to go past it") }
        #expect(CodexFact.of(.edit, Self.reading("workspace-write"))?.isOpen == nil)
        for mode in ["danger-full-access", "read-only", "workspace-write"] { #expect(CodexFact.of(.bash, Self.reading(mode))?.isOpen == nil, "\(mode)") }
    }

    @Test("a setting that reads as text, not a word, is not shown")
    func textIsHidden() {
        #expect(CodexFact.of(.bash, Self.reading("Some Secret Token 12345"))?.value == CodexWording.hiddenText)
    }

    @Test("an unknown Codex reading holds no fact and says why: not installed, not readable, no file, two models, a profile, no sandbox_mode")
    func unknownReadings() {
        let cases: [(CodexReading, String)] = [
            (Self.reading(installed: false), "installed"),
            (Self.reading(notReadable: true), "can't be read"),
            (Self.reading(present: false), "no ~/.codex/config.toml"),
            (Self.reading(model: .both), "two permission models"),
            (Self.reading(model: .profiles, profile: "work"), "profile"),
            (Self.reading(profile: "work"), "profile"),
            (Self.reading(nil), "sandbox_mode is not set"),
        ]
        for (reading, words) in cases {
            #expect(reading.codex == nil, "\(words)")
            #expect(CodexFact.of(.edit, reading) == nil && CodexFact.of(.bash, reading) == nil, "\(words)")
            let answer = RulesAnswer.of(state: .ready, layout: Self.layout(RulesSynthetic.sample, reading), reading: reading).sentence ?? ""
            #expect(answer.hasPrefix("Nothing to compare:") && answer.contains(words), "\(words): \(answer)")
        }
        #expect(CodexReading(codex: nil, installed: true) == .unknown(.notRead))
    }

    @Test("the note under the bands names the approval policy as written, 'granular' for the table form, 'not set' when absent, and hides free text")
    func note() {
        func note(_ approval: String?) -> String? { CodexReading(codex: RulesSynthetic.codex(approval: approval), installed: true).note }
        #expect(note("on-request") == "Codex is read only here. Approval policy on-request, from ~/.codex/config.toml.")
        #expect(note(nil) == "Codex is read only here. Approval policy not set, from ~/.codex/config.toml.")
        #expect(note("My Token 1234") == "Codex is read only here. Approval policy \(CodexWording.hiddenText), from ~/.codex/config.toml.")
        var granular = RulesSynthetic.codex()
        granular.approvalPolicy = .granular([])
        #expect(CodexReading(codex: granular, installed: true).note == "Codex is read only here. Approval policy granular, from ~/.codex/config.toml.")
        #expect(Self.reading(installed: false).note == nil && Self.reading(notReadable: true).note == nil)
        #expect(Self.reading(model: .both).note?.contains("two permission models") == true)
    }

    // MARK: Mismatch and bands

    @Test("a family open in Codex and denied in Claude Code (or off in Codex and allowed) is flagged, comes first and opens")
    func mismatch() {
        let open = Self.layout(RulesSynthetic.sample, Self.reading("danger-full-access"))
        #expect(open.mismatches.map(\.family) == [.edit])
        #expect(open.bands.first?.family == .edit && open.bands.first?.holdsProblem == true)
        #expect(open.bands.map(\.family) == [.edit, .bash, .read, .web, .mcp, .other], "the flagged band first, then family order")
        #expect(RulesCanvas.opensByDefault(open, 0) && !RulesCanvas.opensByDefault(open, 1), "only the flagged band opens")
        // Off in Codex and allowed in Claude Code.
        let off = Self.layout([Self.rule("Edit(src/**)", .allow), Self.rule("Bash(ls:*)", .allow)], Self.reading("read-only", approval: "never"))
        #expect(off.mismatches.map(\.family) == [.edit])
        #expect(Self.layout([Self.rule("Edit(src/**)", .allow)], Self.reading("read-only")).mismatches.isEmpty, "read only with approvals on is not off")
        // Open in Codex with nothing denied, off in Codex with nothing allowed: no problem.
        #expect(Self.layout([Self.rule("Edit(src/**)", .allow)], Self.reading("danger-full-access")).mismatches.isEmpty)
        #expect(Self.layout([Self.rule("Edit(src/**)", .deny)], Self.reading("read-only", approval: "never")).mismatches.isEmpty)
        #expect(Self.layout(RulesSynthetic.sample, Self.reading("workspace-write")).mismatches.isEmpty)
    }

    @Test("Web is never flagged: Codex's network_access is its commands' network, not its web search (G12)")
    func webIsNotCompared() {
        for mode in ["danger-full-access", "read-only", "workspace-write"] {
            #expect(Self.layout([Self.rule("WebFetch", .deny)], Self.reading(mode)).mismatches.isEmpty, "\(mode)")
            #expect(Self.layout([Self.rule("WebSearch", .allow)], Self.reading(mode)).mismatches.isEmpty, "\(mode)")
        }
    }

    @Test("nothing needs the user: the first band opens; the Filter leaves the bands that have a match; unfiltered counts stay for the Answer")
    func filterAndDefaults() {
        let calm = Self.layout(RulesSynthetic.sample, Self.reading("workspace-write"))
        #expect(RulesCanvas.opensByDefault(calm, 0) && !RulesCanvas.opensByDefault(calm, 1))
        var filter = RulesFilter()
        filter.toggle(.verdict, "ask")
        let asked = Self.layout(RulesSynthetic.sample, Self.reading("workspace-write"), filter: filter)
        #expect(asked.bands.map(\.family) == [.bash, .mcp, .other], "Bash, MCP and Skill have an ask rule")
        #expect(asked.bands.first?.rules.count == 5 && asked.bands.first?.all.count == 24)
        filter.toggle(.verdict, "deny")
        #expect(Self.layout(RulesSynthetic.sample, Self.reading(), filter: filter).bands.first { $0.family == .web }?.rules.count == 2, "OR within a field")
        filter.clear()
        filter.toggle(.verdict, "allow")
        #expect(Self.layout([Self.rule("WebFetch", .deny)], filter: filter).bands.isEmpty, "a Filter that matches nothing leaves no band")
    }

    @Test("every rule is listed once: the rows of all bands are the rules, in a family each, and a rule written twice is one row")
    func countEqualsRows() {
        let rules = RulesSynthetic.sample + [Self.rule("Bash(ls:*)", .allow), Self.rule("Skill(deploy)", .ask)]
        let layout = Self.layout(rules)
        #expect(layout.bands.flatMap(\.rules).count == RulesSynthetic.sample.count, "the two copies add no row")
        #expect(Set(layout.bands.flatMap(\.rules).map(\.id)).count == layout.bands.flatMap(\.rules).count)
        #expect(layout.bands.first { $0.family == .other }?.rules.map(\.rule) == ["Skill(deploy)"], "a rule outside the five families is listed")
        #expect(Self.layout(RulesSynthetic.many).bands.flatMap(\.rules).count == 60)
    }

    // MARK: Redundant rules

    @Test("a Bash prefix covers a longer command of the same verdict, in both spellings; a different verdict never")
    func bashPrefix() {
        let sample = RedundantRules.of(RulesSynthetic.sample)
        #expect(sample.map(\.rule.rule) == ["Bash(git push --force:*)"] && sample.first?.by.rule == "Bash(git push:*)")
        #expect(RedundantRules.of([Self.rule("Bash(git push *)", .deny), Self.rule("Bash(git push --force *)", .deny)]).map(\.rule.rule) == ["Bash(git push --force *)"])
        #expect(RedundantRules.of([Self.rule("Bash(git push:*)", .deny), Self.rule("Bash(git push --force)", .deny)]).map(\.rule.rule) == ["Bash(git push --force)"])
        #expect(RedundantRules.of([Self.rule("Bash(git push:*)", .ask), Self.rule("Bash(git push --force:*)", .deny)]).isEmpty)
        #expect(RedundantRules.of([Self.rule("Bash(git pushy:*)", .deny), Self.rule("Bash(git push:*)", .deny)]).isEmpty, "a prefix ends at a word")
        #expect(RedundantRules.of([Self.rule("Bash(git push)", .deny), Self.rule("Bash(git push:*)", .deny)]).map(\.rule.rule) == ["Bash(git push)"], "the exact command is the covered one")
        #expect(!RedundantRules.covers(Self.rule("Bash(git push)", .deny), Self.rule("Bash(git push:*)", .deny)), "an exact command covers nothing")
    }

    @Test("a bare tool covers any rule of that tool, mcp__server covers its tools, and two rules that cover each other keep the earlier")
    func wideAndMcp() {
        #expect(RedundantRules.of([Self.rule("Bash", .allow), Self.rule("Bash(ls:*)", .allow), Self.rule("Bash(ls:*)", .deny)]).map(\.rule.id) == ["global:allow:Bash(ls:*)"])
        #expect(RedundantRules.of([Self.rule("Edit(src/**)", .allow), Self.rule("Edit", .allow)]).map(\.rule.rule) == ["Edit(src/**)"])
        #expect(RedundantRules.of([Self.rule("Edit", .allow), Self.rule("Write(src/**)", .allow)]).isEmpty, "Edit does not cover Write: only the same tool counts")
        #expect(RedundantRules.of([Self.rule("mcp__neon", .allow), Self.rule("mcp__neon__run_sql", .allow), Self.rule("mcp__neon2__x", .allow)]).map(\.rule.rule) == ["mcp__neon__run_sql"])
        // `Bash` and `Bash(*)` cover each other: the later one is the redundant one.
        #expect(RedundantRules.of([Self.rule("Bash", .allow), Self.rule("Bash(*)", .allow)]).map(\.rule.rule) == ["Bash(*)"])
        #expect(RedundantRules.of([Self.rule("Bash(git push:*)", .deny), Self.rule("Bash(git push *)", .deny)]).map(\.rule.rule) == ["Bash(git push *)"])
    }

    @Test("a rule written twice is one rule: it is never redundant by its own copy, so Remove never takes the covering one")
    func duplicates() {
        #expect(RedundantRules.of([Self.rule("Bash(ls:*)", .allow), Self.rule("Bash(ls:*)", .allow)]).isEmpty)
        #expect(RulesSynthetic.healthy.count == RulesSynthetic.sample.count - 1 && RedundantRules.of(RulesSynthetic.healthy).isEmpty)
    }

    // MARK: The Answer (V5-A18)

    @Test("one problem: the family, which side is open, and the Claude Code row to change; a mixed family says 'partly'")
    func oneProblem() {
        let page = Self.page(RulesSynthetic.sample, codex: RulesSynthetic.codex(sandbox: "danger-full-access"))
        #expect(page.answer.sentence == "Edit/Write: open in Codex, partly denied in Claude Code.")
        #expect(page.answer.family?.family == .edit && page.answer.family?.fact?.text == "Sandbox: danger-full-access" && page.answer.family?.allStance.single == nil)
        #expect(page.answer.alsoLine == nil)
        let whole = Self.page([Self.rule("Edit(~/.ssh/**)", .deny)], codex: RulesSynthetic.codex(sandbox: "danger-full-access"))
        #expect(whole.answer.sentence == "Edit/Write: open in Codex, denied in Claude Code." && whole.answer.family?.allStance.single == .deny)
        let off = Self.page([Self.rule("Edit(src/**)", .allow)], codex: RulesSynthetic.codex(sandbox: "read-only", approval: "never"))
        #expect(off.answer.sentence == "Edit/Write: off in Codex, allowed in Claude Code.")
    }

    @Test("several problems: the first family is named and the others follow as 'Also'")
    func severalProblems() {
        #expect(RulesAnswer(sentence: "x", also: [.web, .mcp]).alsoLine == "Also Web, MCP.")
        #expect(RulesAnswer(sentence: "x", also: [.read]).alsoLine == "Also Read.")
        #expect(RulesAnswer(sentence: "x").alsoLine == nil)
    }

    @Test("nothing needs the user: the plain sentence, no family row and no fix, but only when a family was compared; else it says nothing was")
    func healthy() {
        let full = Self.page(RulesSynthetic.healthy, codex: RulesSynthetic.codex(sandbox: "danger-full-access"))
        #expect(full.layout.hasComparison && full.layout.mismatches.isEmpty == false, "the ssh deny against full access is a problem; take it out below")
        let calm = Self.page(RulesSynthetic.healthy.filter { $0.rule != "Edit(~/.ssh/**)" }, codex: RulesSynthetic.codex(sandbox: "danger-full-access"))
        #expect(calm.layout.hasComparison)
        #expect(calm.answer.sentence == "No tool is open in one CLI and denied in the other." && calm.answer.family == nil && !calm.answer.showsRetry)
        // A workspace sandbox says neither open nor off for any family: nothing was compared, so no clean result is claimed.
        let workspace = Self.page(RulesSynthetic.sample)
        #expect(!workspace.layout.hasComparison && workspace.layout.mismatches.isEmpty)
        #expect(workspace.answer.sentence == "Codex's sandbox is workspace-write, so it opens or closes no tool outright." && workspace.answer.family == nil)
        #expect(workspace.answer.detail == "Edit/Write would show as open under danger-full-access, or as off under read-only with approvals never." && !workspace.answer.showsRetry)
        // The sandbox value is the one the core read, not a typed one; a value that is not a plain word stays hidden.
        #expect(Self.page(RulesSynthetic.sample, codex: RulesSynthetic.codex(sandbox: "Some Secret 12345")).answer.sentence?.contains(CodexWording.hiddenText) == true)
        // Read only with approvals on can be stepped past: neither open nor off, so the same sentence names read-only.
        #expect(Self.page(RulesSynthetic.sample, codex: RulesSynthetic.codex(sandbox: "read-only", approval: "on-request")).answer.sentence
                == "Codex's sandbox is read-only, so it opens or closes no tool outright.")
        #expect(workspace.layout.redundant.count == 1, "a redundant rule is not a problem for the Answer")
        // Full access with no Edit/Write rule: no family with rules has a comparable fact.
        let noEdit = Self.page([Self.rule("Bash(ls:*)", .allow)], codex: RulesSynthetic.codex(sandbox: "danger-full-access"))
        #expect(!noEdit.layout.hasComparison)
        #expect(noEdit.answer.sentence == "Codex's sandbox is danger-full-access, and Claude Code has no Edit/Write rule to compare with it." && noEdit.answer.detail == nil)
    }

    @Test("no data: loading has no sentence; no rules, Codex not installed and an unreadable file each say so")
    func otherStates() {
        #expect(RulesPage(snapshot: nil, failure: nil, codexInstalled: true, filter: RulesFilter()).answer.sentence == nil)
        #expect(RulesPage(snapshot: nil, failure: nil, codexInstalled: true, filter: RulesFilter()).state == .loading)
        #expect(Self.page([]).answer.sentence == "Claude Code has no rules yet.")
        #expect(Self.page(RulesSynthetic.sample, installed: false).answer.sentence == "Nothing to compare: Codex is not installed.")
        let failed = RulesPage(snapshot: nil, failure: "The core could not be started.", codexInstalled: true, filter: RulesFilter())
        #expect(failed.state == .unreadable("The core could not be started.") && failed.answer.sentence == "Can't read Claude Code's rules." && failed.answer.showsRetry)
        #expect(failed.answer.detail == "The core could not be started.")
    }

    @Test("an invalid settings file hides every rule, names the core's own sentence and offers Retry; so does an unreadable one")
    @MainActor func invalid() {
        let problem = "~/.claude/settings.json is not valid JSON."
        let page = Self.page(RulesSynthetic.sample, problems: [problem])
        #expect(page.state == .invalid(problem) && page.layout.bands.isEmpty && page.layout.redundant.isEmpty && page.isListEmpty)
        #expect(page.answer.sentence == "Can't read Claude Code's rules." && page.answer.detail == problem && page.answer.showsRetry)
        #expect(RulesTabWording.hiddenUntilParses == "Rules stay hidden until ~/.claude/settings.json parses, so SpaceVibe writes nothing over it.")
        #expect(RulesModel(env: AppEnvironment(toasts: ToastCenter(announce: false)), snapshot: RulesSynthetic.snapshot([], problems: [problem])).badge == nil)
        let unreadable = Self.page([], notReadable: true)
        #expect(unreadable.state == .invalid(RulesWording.globalNotReadable) && unreadable.answer.showsRetry)
    }

    @Test("the tab shows the global scope only: a snapshot of another scope reads as loading")
    func globalOnly() {
        let project = CoreRulesSnapshot(
            projectDirs: ["/work/web"], globalRuleCount: 1, scope: .project, dir: "/work/web", fileLabel: ".claude/settings.json", exists: true, problems: [],
            rules: [Self.rule("Bash(ls:*)", .allow)], grid: [], codex: RulesSynthetic.codex(), notReadable: false, globalNotReadable: false
        )
        let page = RulesPage(snapshot: RulesSnapshot(project), failure: nil, codexInstalled: true, filter: RulesFilter())
        #expect(page.state == .loading && page.rules.isEmpty)
    }

    @Test("the toasts name what changed and how many rules a family change touched")
    func wording() {
        #expect(RulesTabWording.familyChanged(.bash, to: .ask, count: 6) == "Bash is now Ask in Claude Code (6 rules changed)")
        #expect(RulesTabWording.familyChanged(.edit, to: .deny, count: 1) == "Edit/Write is now Deny in Claude Code (1 rule changed)")
        #expect(RulesTabWording.familyUnchanged(.read, to: .deny) == "Read is already Deny in Claude Code.")
        #expect(RulesTabWording.ruleChanged("Bash(ls:*)", to: .deny) == "Bash(ls:*) is now Deny in Claude Code")
        #expect(RulesTabWording.removed("Bash(ls:*)") == "Removed Bash(ls:*) from ~/.claude/settings.json")
        #expect(RulesTabWording.undone == "Undone. ~/.claude/settings.json is back to how it was.")
        #expect(CoreVerdict.allCases.map(RulesTabWording.meaning) == ["Claude Code runs it without asking.", "Claude Code asks you each time.", "Claude Code blocks it."])
    }
}
