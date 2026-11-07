import Foundation
import Testing
@testable import Reins

@Suite("Rules scopes and wording")
struct RulesScopesTests {
    // MARK: RulesPending

    private func pending(
        _ capability: CoreCapability = .run, _ verdict: CoreVerdict = .allow, label: String = "Run commands", resulting: CoreCapabilityState,
        replaces: [CoreVerdictRule] = [], writes: [CoreVerdictRule] = []
    ) -> RulesPending {
        let preview = CoreCapabilityPreview(
            capability: capability, verdict: verdict, scopeLabel: "~/.claude/settings.json", current: .none,
            resulting: resulting, replaces: replaces, writes: writes
        )
        return RulesPending(preview: preview, scope: .global, scopeTitle: "Global", capabilityLabel: label)
    }

    @Test("a write is a no-op when the file already holds the same rules, whatever their order")
    func isNoOp() {
        let push = CoreVerdictRule(verdict: .deny, rule: "Bash(git push:*)")
        let publish = CoreVerdictRule(verdict: .deny, rule: "Bash(npm publish:*)")
        #expect(pending(resulting: .deny, replaces: [push, publish], writes: [publish, push]).isNoOp)
        #expect(!pending(resulting: .deny, replaces: [push], writes: [push, publish]).isNoOp)
        #expect(!pending(resulting: .deny, replaces: [], writes: [push]).isNoOp)
    }

    @Test("when the result is what was chosen, the no-op message says the cell already reads it, and there is no warning")
    func noOpMessageWhenResultMatches() {
        let same = pending(.run, .allow, resulting: .allow)
        #expect(same.noOpMessage == "Run commands already reads Allow here.")
        #expect(same.warning == nil)
    }

    @Test("when a rule that stays wins, the no-op message names the resulting state, and a warning explains it")
    func noOpMessageWhenAKeptRuleWins() throws {
        let kept = pending(.push, .allow, label: "Push and deploy", resulting: .ask)
        #expect(kept.noOpMessage == "Push and deploy stays Ask here: a rule that stays in this file wins.")
        let warning = try #require(kept.warning)
        #expect(warning.contains("Push and deploy will read Ask, not Allow"))
    }

    // MARK: projects

    @Test("a project shows its folder name, and parent/name when another project has the same folder name")
    func projectNames() {
        let projects = RulesScopes.projects(from: ["/work/a/app", "/work/b/app", "/work/web"])
        #expect(projects == [
            RulesProject(dir: "/work/a/app", name: "a/app"),
            RulesProject(dir: "/work/b/app", name: "b/app"),
            RulesProject(dir: "/work/web", name: "web"),
        ])
    }

    // MARK: title

    private let projects = [RulesProject(dir: "/work/a/app", name: "a/app"), RulesProject(dir: "/work/web", name: "web")]

    @Test("Global reads Global whichever file the selection names")
    func titleGlobal() {
        #expect(RulesScopes.title(for: .global, projects: projects) == "Global")
        #expect(RulesScopes.title(for: RulesSelection(dir: nil, file: .local), projects: projects) == "Global")
    }

    @Test("a discovered project reads its display name, marked shared or local")
    func titleKnownProject() {
        #expect(RulesScopes.title(for: RulesSelection(dir: "/work/a/app"), projects: projects) == "a/app (shared)")
        #expect(RulesScopes.title(for: RulesSelection(dir: "/work/a/app", file: .local), projects: projects) == "a/app (local)")
    }

    @Test("a folder that is no longer discovered falls back to its folder name")
    func titleUnknownProject() {
        #expect(RulesScopes.title(for: RulesSelection(dir: "/work/gone/old-thing"), projects: projects) == "old-thing (shared)")
        #expect(RulesScopes.title(for: RulesSelection(dir: "/work/gone/old-thing", file: .local), projects: []) == "old-thing (local)")
    }

    // MARK: Rules toolbar scope options

    private let discovered = RulesScopes.projects(from: ["/work/a/app", "/work/b/app", "/work/web"])

    @Test("the options start with Global (no id), then one per project keyed by its folder and labelled with its name")
    func scopeOptionsOrder() {
        let options = RulesToolbar.scopeOptions(projects: discovered)
        #expect(options.first == ScopeOption(id: nil, label: "Global"))
        #expect(options.dropFirst().map(\.id) == ["/work/a/app", "/work/b/app", "/work/web"])
        #expect(options.dropFirst().map(\.label) == ["a/app", "b/app", "web"])
        #expect(RulesToolbar.scopeOptions(projects: []) == [ScopeOption(id: nil, label: "Global")])
    }

    @Test("every option has its own id, so the picker's checkmark marks exactly one")
    func scopeOptionIdsAreUnique() {
        let ids = RulesToolbar.scopeOptions(projects: discovered).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("the current scope is the matching option; no selected folder means Global")
    func currentScopeMatches() {
        let options = RulesToolbar.scopeOptions(projects: discovered)
        #expect(RulesToolbar.currentScope(options: options, dir: nil) == ScopeOption(id: nil, label: "Global"))
        #expect(RulesToolbar.currentScope(options: options, dir: "/work/b/app") == ScopeOption(id: "/work/b/app", label: "b/app"))
    }

    @Test("a selected folder that is no longer discovered shows as Project and keeps its folder as the id")
    func currentScopeFallback() {
        let options = RulesToolbar.scopeOptions(projects: discovered)
        #expect(RulesToolbar.currentScope(options: options, dir: "/work/gone") == ScopeOption(id: "/work/gone", label: "Project"))
    }

    // MARK: The Claude Code line on the Codex page

    private func cell(_ capability: CoreCapability, _ state: CoreCapabilityState) -> CoreCapabilityCell {
        CoreCapabilityCell(capability: capability, label: capability.rawValue, state: state, editable: state != .mixed, rules: [])
    }

    @Test("the Claude Code summary names what the file asks before and blocks, and falls back to a count")
    func claudeSummary() {
        let grid = [cell(.read, .allow), cell(.run, .mixed), cell(.network, .ask), cell(.push, .ask), cell(.secrets, .deny)]
        #expect(RulesWording.summary(grid, ruleCount: 11) == "Asks before network access and push and deploy, blocks secrets (.env)")
        #expect(RulesWording.summary([cell(.run, .mixed)], ruleCount: 2) == "2 rules here, none decides a whole row")
        #expect(RulesWording.summary([cell(.run, .none)], ruleCount: 0) == "No rules in this file")
    }

    // MARK: Snapshot and notices

    private func dto(scope: CoreRuleScope = .local, dir: String? = "/work/web", globalNotReadable: Bool = false) -> CoreRulesSnapshot {
        CoreRulesSnapshot(
            projectDirs: ["/work/web"], globalRuleCount: 2, scope: scope, dir: dir, fileLabel: ".claude/settings.local.json", exists: true,
            problems: [], rules: [], grid: [cell(.run, .ask), cell(.edit, .mixed)], codex: Self.codex(), notReadable: false,
            globalNotReadable: globalNotReadable
        )
    }

    private static func codex(model: CoreCodexModel = .legacy, warnings: [String] = []) -> CoreCodexPermissions {
        CoreCodexPermissions(
            present: true, model: model, unrestricted: false, warnings: warnings, approvalPolicy: nil, sandboxMode: nil, sandboxWorkspaceWrite: nil,
            defaultPermissions: nil, approvalsReviewer: nil, profiles: [], projects: [],
            rules: CoreCodexRulesSummary(files: 0, allow: 0, prompt: 0, forbidden: 0, other: 0, unreadable: 0, folderNotReadable: false),
            notReadable: false, skippedLines: 0
        )
    }

    @Test("a snapshot keeps the scope the core read, and a grid is editable only for a plain cell in a file that parses and can be read")
    func snapshotFromDTO() {
        let snapshot = RulesSnapshot(dto())
        #expect(snapshot.selection == RulesSelection(dir: "/work/web", file: .local))
        #expect(snapshot.selection.scope == .local("/work/web"))
        #expect(snapshot.title == "web (local)")
        #expect(snapshot.projects == [RulesProject(dir: "/work/web", name: "web")])
        #expect(snapshot.isEditable(cell(.run, .ask)) && !snapshot.isEditable(cell(.edit, .mixed)))
        #expect(RulesSnapshot(dto(scope: .global, dir: nil)).selection == .global)

        var unreadable = dto()
        unreadable.notReadable = true
        #expect(!RulesSnapshot(unreadable).isEditable(cell(.run, .ask)))
    }

    @Test("the Codex banners are the core's warnings, minus the two-models one when that has its own banner")
    func codexNotices() {
        let both = "Both default_permissions and sandbox_mode are set. Codex expects only one of them."
        let skipped = "3 lines of Codex config.toml could not be understood and were skipped, so some settings may be missing."
        #expect(RulesWording.codexNotices(Self.codex(model: .both, warnings: [both, skipped])) == [skipped])
        #expect(RulesWording.codexNotices(Self.codex(model: .both, warnings: [both])).isEmpty)
        #expect(RulesWording.codexNotices(Self.codex(warnings: [skipped])) == [skipped])
        #expect(RulesWording.codexNotices(Self.codex()).isEmpty)
    }
}
