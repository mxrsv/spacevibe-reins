import Foundation
import Testing
@testable import SpaceVibe

/// V5-A6 for the Subagents tab: a logo toggle, `Add to <CLI>` and `Remove` go through the Go core, show ONE toast, and Undo puts the
/// home back byte for byte. G10 is settled here: the copy writes the name, the description and the instructions and nothing of the
/// model or the tools. Every test runs on a private copy of the synthetic fixture home (S-R1) with the real core.
@Suite("Subagents model, Go core")
@MainActor
struct SubagentsModelEngineTests {
    /// Extra files a test puts into the fixture home before the core reads it.
    private func subagents(_ fixture: CoreFixtureHome, extra: [String: String] = [:]) async throws -> (SubagentsModel, AppEnvironment, CoreClient) {
        for (relative, text) in extra {
            let url = fixture.home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let client = try fixture.client()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
        let model = SubagentsModel(loadout: LoadoutModel(env: env))
        model.loadout.start()
        try await wait("the read") { model.loadout.isSettled || model.loadout.readFailure != nil }
        try #require(model.loadout.isSettled, "the read did not settle: \(model.loadout.readFailure ?? "timed out")")
        return (model, env, client)
    }

    private func wait(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done(), "\(what) did not happen")
    }

    private func row(_ model: SubagentsModel, _ name: String) throws -> LoadoutRow {
        try #require(model.rows.first { $0.name == name }, "no subagent \(name)")
    }

    private func undo(_ model: SubagentsModel, _ env: AppEnvironment, label: String) async throws {
        env.toasts.runCurrentAction()
        try await wait("the Undo toast") { env.toasts.current?.message == "Undid \(label)" }
        try await wait("the re-read") { model.loadout.isSettled }
    }

    private func text(_ fixture: CoreFixtureHome, _ relative: String) throws -> String {
        try String(contentsOf: fixture.home.appendingPathComponent(relative), encoding: .utf8)
    }

    private let codexOnly = ".codex/agents/codex-helper.toml"
    private let pluginAgent = ".claude/plugins/cache/neon/agents/neon-helper.md"

    @Test("the tab lists the global subagents of the fixture, with the sessions the logs hold")
    func rows() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, _, client) = try await subagents(fixture)
        defer { client.shutdown() }
        #expect(Set(model.rows.map(\.name)) == ["typescript-reviewer", "react-reviewer", "database-reviewer", "security-reviewer", "architect"],
                "the project's migration-reviewer is not in the global scope")
        #expect(model.answer.sentence == "1 subagent never ran." && model.answer.verdict?.name == "architect", "the logs hold no session of architect")
        #expect(model.layout.groups.map(\.title) == ["Claude Code only", "In both"] && model.layout.groups.first?.rows.first?.name == "architect")
        #expect(model.addable.entries.map(\.row.name) == ["typescript-reviewer", "react-reviewer", "database-reviewer"])
        #expect(model.detected == [.claude, .codex])
    }

    @Test("Add to Codex writes the name, the description and the instructions and nothing of the model or tools; the toast says so; Undo restores every byte")
    func addToCodexAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "typescript-reviewer")
        #expect(model.mode(target, cli: .codex) == .toggles && target.presentCLIs == [.claude])

        model.toggle(target, cli: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Added typescript-reviewer to Codex"
        #expect(env.toasts.current?.message == "\(label). Its model and tools are not copied." && env.toasts.current?.action != nil)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed == [".codex/agents/typescript-reviewer.toml"], "one file is written: the copy")
        let copy = try text(fixture, ".codex/agents/typescript-reviewer.toml")
        #expect(copy.contains("name = \"typescript-reviewer\"") && copy.contains("description = ") && copy.contains("developer_instructions = "))
        #expect(!copy.contains("model") && !copy.contains("tools"), "G10: nothing of a model or tools is written: \(copy)")
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.name == "typescript-reviewer" }?.presentCLIs == [.claude, .codex] }

        try await undo(model, env, label: label)
        let left = try await fixture.tree().difference(from: before)
        #expect(left.isEmpty, "differs from the original: \(left)")
    }

    @Test("Add to Claude Code from a Codex-only subagent writes a markdown file with a name and a description, no model and no tools line")
    func addToClaudeAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let source = "name = \"codex-helper\"\ndescription = \"Helps in Codex\"\nmodel = \"gpt-5.1-codex-mini\"\nmodel_reasoning_effort = \"medium\"\ndeveloper_instructions = \"Do the thing.\"\n"
        let (model, env, client) = try await subagents(fixture, extra: [codexOnly: source])
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "codex-helper")
        #expect(target.presentCLIs == [.codex])
        model.addToOtherCLI(target)
        try await wait("the toast") { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "Added codex-helper to Claude Code. Its model and tools are not copied, so it can use every tool.")
        let copy = try text(fixture, ".claude/agents/codex-helper.md")
        #expect(copy.hasPrefix("---\nname: codex-helper\n") && copy.contains("description: ") && copy.contains("Do the thing."))
        #expect(!copy.contains("model") && !copy.contains("tools"), "the Codex model and effort are not copied, and no tools line is written: \(copy)")
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.name == "codex-helper" }?.presentCLIs.count == 2 }
        try await undo(model, env, label: "Added codex-helper to Claude Code")
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("pressing a lit logo removes that CLI's copy only; Undo restores it")
    func removeOneCopyAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "security-reviewer")
        #expect(model.mode(target, cli: .codex) == .toggles)
        model.toggle(target, cli: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Removed the Codex copy of security-reviewer"
        #expect(env.toasts.current?.message == label)
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.name == "security-reviewer" }?.presentCLIs == [.claude] }
        try await undo(model, env, label: label)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("Remove deletes the subagent from every CLI that has it in one toast; Undo restores both files")
    func removeEverywhereAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "security-reviewer")
        model.remove(target)
        try await wait("the toast") { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "Removed security-reviewer")
        #expect(try await fixture.tree().difference(from: before) == [".claude/agents/security-reviewer.md", ".codex/agents/security-reviewer.toml"])
        try await wait("the re-read") { model.loadout.isSettled && model.rows.contains { $0.name == "security-reviewer" } == false }
        try await undo(model, env, label: "Removed security-reviewer")
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "one Undo put both files back; differs: \(changed)")
    }

    /// The last listed subagent a person may remove from every CLI, and the row that becomes current when it goes.
    private func lastRemovable(_ model: SubagentsModel) throws -> (target: LoadoutRow, expected: String) {
        let keys = model.layout.rows.map(\.key)
        model.listedKeys = keys
        let target = try #require(model.layout.rows.last { $0.plugin == nil && $0.project == nil && $0.members.values.allSatisfy(\.removable) })
        let index = try #require(keys.firstIndex(of: target.key))
        let expected = index + 1 < keys.count ? keys[index + 1] : keys[index - 1]
        try #require(expected != keys.first, "the neighbour must differ from the first row for this test to mean anything")
        return (target, expected)
    }

    @Test("removing the current subagent leaves its neighbour current, not the first row")
    func removeMovesCurrentRow() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture)
        defer { client.shutdown() }
        let (target, expected) = try lastRemovable(model)
        model.currentKey = target.key

        model.remove(target)
        #expect(model.currentKey == expected)
        try await wait("the toast") { env.toasts.current != nil }
        try await wait("the re-read") { model.loadout.isSettled && !model.rows.contains { $0.key == target.key } }
        #expect(model.current(in: model.layout.rows)?.key == expected)
    }

    @Test("a refused removal puts the key back on the row that stayed")
    func refusedRemovalPutsKeyBack() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture)
        defer { client.shutdown() }
        let (target, expected) = try lastRemovable(model)
        model.currentKey = target.key
        for case .item(let item)? in target.members.values.map({ Optional($0) }) { try FileManager.default.removeItem(atPath: item.path) }

        model.remove(target)
        #expect(model.currentKey == expected)
        try await wait("the refusal") { env.toasts.current?.tone == .danger }
        #expect(model.currentKey == target.key)
    }

    @Test("a plugin's subagent is read-only: no write, and a toast that says why")
    func pluginRefusal() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture, extra: [pluginAgent: "---\nname: neon-helper\ndescription: Helps with Neon\n---\n\nSynthetic agent.\n"])
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let plugin = try row(model, "neon-helper")
        #expect(plugin.plugin == "neon", "the core reads it as the plugin's")
        for cli in CoreCLI.allCases { #expect(model.mode(plugin, cli: cli) == .readOnly) }
        model.toggle(plugin, cli: .codex)
        #expect(env.toasts.current == nil, "a read-only logo does nothing")
        model.remove(plugin)
        #expect(env.toasts.current?.message == "neon-helper is owned by the neon plugin. SpaceVibe cannot change it.")
        model.addToOtherCLI(plugin)
        #expect(env.toasts.current?.message == "neon-helper is owned by the neon plugin. SpaceVibe cannot change it.")
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await fixture.tree().difference(from: before).isEmpty)
        #expect(SubagentsAddable(model.rows, detected: model.detected).leftOut.contains("neon-helper (plugin-owned)"))
    }

    @Test("the only copy is not a toggle: its last lit logo does nothing")
    func onlyCopy() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await subagents(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "typescript-reviewer")
        #expect(model.mode(target, cli: .claude) == .onlyCopy)
        model.toggle(target, cli: .claude)
        try await Task.sleep(for: .milliseconds(300))
        #expect(env.toasts.current == nil)
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }
}
