import Foundation
import Testing
@testable import ReinsCore
@testable import Reins

@Suite("Rules scopes and wording")
struct RulesScopesTests {
    // MARK: RulesPending

    private func pending(
        _ capability: Capability = .run, _ verdict: RuleVerdict = .allow, resulting: CapabilityState,
        replaces: [VerdictRule] = [], writes: [VerdictRule] = []
    ) -> RulesPending {
        let preview = CapabilityPreview(
            capability: capability, verdict: verdict, scopeLabel: "~/.claude/settings.json", current: .none,
            resulting: resulting, replaces: replaces, writes: writes
        )
        return RulesPending(preview: preview, scope: .global, scopeTitle: "Global")
    }

    @Test("a write is a no-op when the file already holds the same rules, whatever their order")
    func isNoOp() {
        let push = VerdictRule(verdict: .deny, rule: "Bash(git push:*)")
        let publish = VerdictRule(verdict: .deny, rule: "Bash(npm publish:*)")
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
        let kept = pending(.push, .allow, resulting: .ask)
        #expect(kept.noOpMessage == "Push and deploy stays Ask here: a rule that stays in this file wins.")
        let warning = try #require(kept.warning)
        #expect(warning.contains("Push and deploy will read Ask, not Allow"))
    }

    // MARK: shapeError

    @Test("an empty or blank rule is refused", arguments: ["", "   ", "\n"])
    func shapeErrorEmpty(text: String) {
        #expect(RulesScopes.shapeError(text) != nil)
    }

    @Test("a rule with a line break inside it is refused")
    func shapeErrorNewline() {
        #expect(RulesScopes.shapeError("Bash(npm test\nnpm publish)") != nil)
    }

    @Test("a rule over the length limit is refused; one exactly at the limit is not")
    func shapeErrorLength() {
        let overhead = "Bash()".utf16.count
        let atLimit = "Bash(" + String(repeating: "a", count: Rules.maxRuleLength - overhead) + ")"
        #expect(atLimit.utf16.count == Rules.maxRuleLength)
        #expect(RulesScopes.shapeError(atLimit) == nil)
        #expect(RulesScopes.shapeError(atLimit + "a") != nil)
    }

    @Test("text that is not Tool or Tool(pattern) is refused")
    func shapeErrorNotARule() {
        #expect(RulesScopes.shapeError("(npm test)") != nil)
        #expect(RulesScopes.shapeError("Bash(npm test") != nil)
    }

    @Test("a valid rule passes, with or without surrounding whitespace")
    func shapeErrorValid() {
        #expect(RulesScopes.shapeError("Bash(npm test *)") == nil)
        #expect(RulesScopes.shapeError("  Bash(npm test *)\n") == nil)
        #expect(RulesScopes.shapeError("WebFetch") == nil)
    }

    // MARK: scrub

    @Test("scrub replaces the settings file path and its symlink-resolved form with the label")
    func scrubBothForms() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root = base.appendingPathComponent("reins-scrub-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try Data("{}".utf8).write(to: real.appendingPathComponent("settings.json"))

        let given = link.appendingPathComponent("settings.json").path
        let resolved = real.appendingPathComponent("settings.json").path
        try #require(given != resolved)

        let text = "\(given) is not valid JSON; also seen as \(resolved)."
        #expect(RulesScopes.scrub(text, path: given, label: "global") == "global is not valid JSON; also seen as global.")
        #expect(RulesScopes.scrub("nothing to hide", path: given, label: "global") == "nothing to hide")
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

    // MARK: scrubbed

    private struct Unrelated: Error, Equatable {}

    /// A store over a temporary home, with no project known. The folder is removed by the caller.
    private func makeStore() throws -> (store: RulesStore, home: URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let home = base.appendingPathComponent("reins-scrubbed-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = [
            "HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
            "CODEX_HOME": home.appendingPathComponent(".codex").path, "REINS_HOME": home.appendingPathComponent(".reins").path,
            "REINS_TEST": "1",
        ]
        return (RulesStore(roots: try Roots.resolve(env: env), projects: { [] }), home)
    }

    @Test("a ReinsError that names the settings file comes back with the scope's label and the same status")
    func scrubbedReplacesThePath() throws {
        let (store, home) = try makeStore()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = try store.file(for: .global).path
        #expect(path.hasPrefix(home.path))
        let thrown = ReinsError("\(path) is not valid JSON, so Reins left it alone.", status: 409)
        #expect(throws: ReinsError("~/.claude/settings.json is not valid JSON, so Reins left it alone.", status: 409)) {
            try RulesScopes.scrubbed(store: store, scope: .global) { () throws -> Void in throw thrown }
        }
    }

    @Test("an error that is not a ReinsError passes through unchanged, and a result passes through untouched")
    func scrubbedPassesOtherThingsThrough() throws {
        let (store, home) = try makeStore()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: Unrelated()) {
            try RulesScopes.scrubbed(store: store, scope: .global) { () throws -> Void in throw Unrelated() }
        }
        #expect(try RulesScopes.scrubbed(store: store, scope: .global) { 42 } == 42)
    }

    @Test("when the scope's file cannot be resolved, the original ReinsError is rethrown as it was")
    func scrubbedKeepsTheErrorWhenThereIsNoPath() throws {
        let (store, home) = try makeStore()
        defer { try? FileManager.default.removeItem(at: home) }
        let original = ReinsError("keep /work/gone/old-thing as written", status: 409)
        #expect(throws: original) {
            try RulesScopes.scrubbed(store: store, scope: .project("/work/gone/old-thing")) { () throws -> Void in throw original }
        }
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
}
