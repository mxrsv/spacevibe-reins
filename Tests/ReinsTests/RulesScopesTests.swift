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
}
