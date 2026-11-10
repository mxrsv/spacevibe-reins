import Foundation
import Testing
@testable import SpaceVibe

/// The Rules tab's writes against the real Go core on a private copy of the synthetic home (S-R1; V5-A6): one rule's verdict, a whole
/// family's, a removal, and Undo putting the home back byte for byte, plus the page the fixture reads as. Every home comparison reads the
/// tree off the main actor (`CoreFixtureHome.tree`).
@Suite("Rules tab, Go core")
@MainActor
struct RulesTabEngineTests {
    private func model(_ fixture: CoreFixtureHome) async throws -> (RulesModel, AppEnvironment, CoreClient) {
        let client = try fixture.client()
        let toasts = ToastCenter(announce: false)
        let env = AppEnvironment(toasts: toasts, makeCoreClient: { client })
        let model = RulesModel(env: env)
        model.start()
        try await wait("the read") { model.isSettled || model.failure != nil }
        try #require(model.isSettled, "the read did not settle: \(model.failure ?? "timed out")")
        return (model, env, client)
    }

    private func wait(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done(), "\(what) did not happen")
    }

    /// The write's toast has appeared and the re-read after it has settled.
    private func written(_ model: RulesModel, _ env: AppEnvironment) async throws {
        try await wait("the write's toast") { env.toasts.current?.action != nil }
        try await wait("the re-read") { model.isSettled }
    }

    private func undone(_ model: RulesModel, _ env: AppEnvironment) async throws {
        env.toasts.runCurrentAction()
        try await wait("the Undo") { env.toasts.current?.message == RulesTabWording.undone }
        try await wait("the re-read") { model.isSettled }
    }

    private func verdict(_ model: RulesModel, _ text: String) -> CoreVerdict? { model.page.rules.first { $0.rule == text }?.verdict }

    @Test("the fixture's global file reads as the page the plan traced: 11 rules in four families, Codex known, nothing compared")
    func fixturePage() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, _, client) = try await model(fixture)
        defer { client.shutdown() }
        let page = model.page
        #expect(page.state == .ready && model.snapshot?.globalRuleCount == 11 && model.badge == 11)
        #expect(page.layout.bands.map(\.family) == [.bash, .edit, .read, .web], "the first band opens: nothing needs the user")
        #expect(page.layout.bands.map(\.rules.count) == [7, 1, 2, 1] && page.layout.bands.flatMap(\.rules).count == model.badge, "the tab's count is the rows listed")
        #expect(page.layout.bands.map(\.stance.summary) == ["Allow 4 \u{00B7} Ask 2 \u{00B7} Deny 1", "Deny", "Allow 1 \u{00B7} Deny 1", "Allow"])
        #expect(page.layout.bands.map { $0.fact?.text } == ["Sandbox: workspace-write", "Sandbox: workspace-write", nil, nil])
        #expect(page.reading.note == "Codex is read only here. Approval policy on-request, from ~/.codex/config.toml.")
        #expect(page.answer.sentence == "Codex's sandbox is workspace-write, so it opens or closes no tool outright." && !page.layout.hasComparison && page.layout.redundant.isEmpty)
    }

    @Test("one rule's verdict: one write, one toast, and Undo restores the home byte for byte")
    func oneRule() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let rule = try #require(model.page.rules.first { $0.rule == "Bash(git status:*)" })

        model.set(rule, to: .ask)
        try await written(model, env)
        #expect(env.toasts.current?.message == "Bash(git status:*) is now Ask in Claude Code")
        #expect(verdict(model, "Bash(git status:*)") == .ask)
        #expect(try await fixture.tree().difference(from: before) == [".claude/settings.json"], "only settings.json changed")
        try await undone(model, env)
        #expect(verdict(model, "Bash(git status:*)") == .allow)
        #expect(try await fixture.tree().difference(from: before).isEmpty, "Undo put the home back")
    }

    @Test("a whole family: one write per rule that differs, ONE toast, and one Undo that puts every rule back, byte for byte")
    func wholeFamily() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()

        model.set(.bash, to: .ask)
        try await written(model, env)
        #expect(env.toasts.current?.message == "Bash is now Ask in Claude Code (5 rules changed)", "four allowed and one denied; the two that ask stay")
        let bash = model.page.rules.filter { RuleFamily.of(tool: $0.tool) == .bash }
        #expect(bash.count == 7 && bash.allSatisfy { $0.verdict == .ask })
        #expect(model.page.layout.bands.first { $0.family == .bash }?.stance.summary == "Ask")
        #expect(model.page.rules.filter { RuleFamily.of(tool: $0.tool) != .bash }.map(\.verdict).filter { $0 == .ask }.isEmpty, "no other family changed")
        #expect(try await fixture.tree().difference(from: before) == [".claude/settings.json"])
        try await undone(model, env)
        #expect(try await fixture.tree().difference(from: before).isEmpty, "one Undo put all five rules back")
        #expect(model.page.layout.bands.first { $0.family == .bash }?.stance.summary == "Allow 4 \u{00B7} Ask 2 \u{00B7} Deny 1")
    }

    @Test("a family that already has the verdict writes nothing and shows a message with no Undo")
    func familyAlreadyThere() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        model.set(.edit, to: .deny)
        try await wait("the message") { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "Edit/Write is already Deny in Claude Code." && env.toasts.current?.action == nil)
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }

    @Test("Remove writes one entry, the rule leaves its band, and Undo brings the file back byte for byte")
    func remove() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let rule = try #require(model.page.rules.first { $0.rule == "Read(.env*)" })

        model.removeRule(rule)
        try await written(model, env)
        #expect(env.toasts.current?.message == "Removed Read(.env*) from ~/.claude/settings.json")
        #expect(verdict(model, "Read(.env*)") == nil && model.page.layout.bands.first { $0.family == .read }?.rules.count == 1)
        #expect(model.badge == 10)
        try await undone(model, env)
        #expect(verdict(model, "Read(.env*)") == .deny && model.badge == 11)
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }

    /// The last listed rule, the rule that becomes current when it goes, and the ids listed.
    private func lastRule(_ model: RulesModel) throws -> (target: CoreRule, expected: String) {
        let rules = model.page.layout.bands.flatMap(\.rules)
        let ids = rules.map(\.id)
        model.listedKeys = ids
        let target = try #require(rules.last)
        let index = try #require(ids.firstIndex(of: target.id))
        let expected = index + 1 < ids.count ? ids[index + 1] : ids[index - 1]
        try #require(expected != ids.first, "the neighbour must differ from the first row for this test to mean anything")
        return (target, expected)
    }

    @Test("removing the current rule leaves its neighbour current, not the first row")
    func removeMovesCurrentRule() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let (target, expected) = try lastRule(model)
        model.currentID = target.id

        model.removeRule(target)
        #expect(model.currentID == expected)
        try await written(model, env)
        #expect(model.current(in: model.page.layout.bands.flatMap(\.rules))?.id == expected)
    }

    @Test("a refused removal puts the key back on the rule that stayed")
    func refusedRemovalPutsKeyBack() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let (target, expected) = try lastRule(model)
        model.currentID = target.id
        // The rule is gone from the file before the write, so the core cannot find it.
        try Data("{}".utf8).write(to: fixture.home.appendingPathComponent(".claude/settings.json"))

        model.removeRule(target)
        #expect(model.currentID == expected)
        try await wait("the refusal") { env.toasts.current?.tone == .danger }
        #expect(model.currentID == target.id)
    }

    @Test("a settings file that does not parse hides every rule with the core's sentence, and a write is refused with nothing changed")
    func invalidFile() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await model(fixture)
        defer { client.shutdown() }
        let rule = try #require(model.page.rules.first)
        let file = fixture.home.appendingPathComponent(".claude/settings.json")
        try Data("{ \"permissions\": ".utf8).write(to: file)
        let broken = try await fixture.tree()

        model.refresh()
        try await wait("the invalid read") { if case .invalid = model.page.state { true } else { false } }
        #expect(model.page.state == .invalid("~/.claude/settings.json is not valid JSON."), "\(model.page.state)")
        #expect(model.page.answer.showsRetry && model.page.layout.bands.isEmpty && model.page.isListEmpty)
        #expect(model.badge == nil, "the tab's count is unknown, not 0")

        model.set(rule, to: .deny)
        model.removeRule(rule)
        try await Task.sleep(for: .milliseconds(300))
        #expect(env.toasts.current == nil, "a write on an unreadable file does not start")
        #expect(try await fixture.tree().difference(from: broken).isEmpty, "nothing was written over the file")
    }
}
