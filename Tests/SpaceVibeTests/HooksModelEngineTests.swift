import Foundation
import Testing
@testable import SpaceVibe

/// V5-A6 for the Hooks tab: a logo toggle, the detail's copy and `Remove` go through the Go core, show ONE toast, and Undo puts the
/// home back byte for byte. The core refuses every hook copy into Codex (go-core G-fix.16), so the tab's one rule agrees with it:
/// that refusal is proven here against the real core, and the copy that works (Codex to Claude Code) is proven with Undo. Every
/// test runs on a private copy of the synthetic fixture home (S-R1).
@Suite("Hooks model, Go core")
@MainActor
struct HooksModelEngineTests {
    private let codexHooks = ".codex/hooks.json"

    /// A Codex `hooks.json` with the fixture's `Stop` hook plus one on a shared event and one on `Interrupt`, which Claude Code lacks.
    private let codexFile = """
    {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh '%HOME%/.claude/scripts/notify-done.sh'"}]}],\
    "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo codex-pre"}]}],\
    "Interrupt":[{"hooks":[{"type":"command","command":"echo codex-interrupt"}]}]}}
    """

    private func hooks(_ fixture: CoreFixtureHome, codexOnly: Bool = false) async throws -> (HooksModel, AppEnvironment, CoreClient) {
        if codexOnly {
            let url = fixture.home.appendingPathComponent(codexHooks)
            try Data(codexFile.replacingOccurrences(of: "%HOME%", with: fixture.home.path).utf8).write(to: url)
        }
        let client = try fixture.client()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
        let model = HooksModel(loadout: LoadoutModel(env: env))
        model.loadout.start()
        try await wait("the read") { model.loadout.isSettled || model.loadout.readFailure != nil }
        try #require(model.loadout.isSettled, "the read did not settle: \(model.loadout.readFailure ?? "timed out")")
        model.limitsResults = { [] }
        return (model, env, client)
    }

    private func wait(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done(), "\(what) did not happen")
    }

    private func row(_ model: HooksModel, _ title: String) throws -> LoadoutRow {
        try #require(model.rows.first { $0.hookTitle == title }, "no hook \(title)")
    }

    private func undo(_ model: HooksModel, _ env: AppEnvironment, label: String) async throws {
        env.toasts.runCurrentAction()
        try await wait("the Undo toast") { env.toasts.current?.message == "Undid \(label)" }
        try await wait("the re-read") { model.loadout.isSettled }
    }

    @Test("the tab lists the global hooks of the fixture: two cannot run, one is in both CLIs, and Codex's run count is Unmeasurable")
    func rows() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, _, client) = try await hooks(fixture)
        defer { client.shutdown() }
        #expect(model.rows.count == 7)
        #expect(Set(model.rows.filter(\.isDeadHook).map(\.hookTitle)) == ["notify.sh", "tsc-watch.sh"])
        let stop = try row(model, "notify-done.sh")
        #expect(stop.presentCLIs == [.claude, .codex] && stop.hookRun(in: .codex) == .unmeasurable && stop.hookRun(in: .claude) == .ran(203, last: stop.hookRun(in: .claude).lastDay))
        #expect(model.answer.sentence == "2 hooks can't run." && model.answer.missing.isEmpty)
        #expect(model.layout.bands.first?.holdsProblem == true && model.layout.bands.last?.holdsProblem == false)
        #expect(model.notShown.isEmpty, "the fixture has no hook of another handler kind")
    }

    @Test("the core refuses a hook copy into Codex with its own sentence, and the tab's rule says the same before any call; nothing is written")
    func codexRefusal() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await hooks(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "guard-destructive.sh")
        let id = try #require(target.members[.claude]?.id)
        do {
            _ = try await client.loadoutCopyToOther(id: id)
            Issue.record("the core copied a hook into Codex")
        } catch {
            #expect(AppEnvironment.message(error) == "SpaceVibe does not copy hooks into Codex.")
        }
        #expect(model.context.block(target, to: .codex) == .notWritten(.codex))
        #expect(LoadoutRows.copyPlan(target, to: .codex, events: model.events) == nil && !model.showsToggle(target, cli: .codex))
        model.copy(target, to: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "SpaceVibe does not write hooks into Codex." && env.toasts.current?.action == nil)
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }

    @Test("a Codex-only hook copied to Claude Code writes settings.json only, the toast carries the matcher note, Undo restores every byte")
    func copyToClaudeAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await hooks(fixture, codexOnly: true)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "echo codex-pre")
        #expect(target.presentCLIs == [.codex] && model.mode(target, cli: .claude) == .toggles && model.showsToggle(target, cli: .claude))

        model.toggle(target, cli: .claude)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Copied echo codex-pre to Claude Code"
        #expect(env.toasts.current?.message == "\(label). \(HooksWording.matcherNote)" && env.toasts.current?.action != nil)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed == [".claude/settings.json"], "one file is written: Claude Code's settings")
        let settings = try String(contentsOf: fixture.home.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains("echo codex-pre"), "the command is in Claude Code's settings")
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.hookTitle == "echo codex-pre" }?.presentCLIs.count == 2 }

        try await undo(model, env, label: label)
        let left = try await fixture.tree().difference(from: before)
        #expect(left.isEmpty, "differs from the original: \(left)")
    }

    @Test("a Codex-only hook on an event Claude Code lacks cannot be copied: no toggle, and `a` says why; nothing is written")
    func interruptHasNoClaudeEvent() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await hooks(fixture, codexOnly: true)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "echo codex-interrupt")
        #expect(!model.showsToggle(target, cli: .claude) && model.mode(target, cli: .claude) == .readOnly)
        #expect(model.context.block(target, to: .claude) == .noEvent(.claude, event: "Interrupt"))
        model.copyToOtherCLI(target)
        try await wait("the toast") { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "Claude Code has no Interrupt event.")
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }

    @Test("Remove on a hook whose script is gone deletes it from the settings file in one toast; Undo restores every byte")
    func removeDeadAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await hooks(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "notify.sh")
        #expect(target.isDeadHook && HooksWording.slot(for: target, home: nil)?.offersRemove == true)
        model.remove(target)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Removed notify.sh"
        #expect(env.toasts.current?.message == label && env.toasts.current?.action != nil)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed == [".claude/settings.json"])
        try await wait("the re-read") { model.loadout.isSettled && !model.rows.contains { $0.hookTitle == "notify.sh" } }
        #expect(model.answer.sentence == "1 hook can't run." && model.rows.count == 6)

        try await undo(model, env, label: label)
        let left = try await fixture.tree().difference(from: before)
        #expect(left.isEmpty, "differs from the original: \(left)")
        #expect(model.answer.sentence == "2 hooks can't run.")
    }

    @Test("pressing a lit Codex logo removes Codex's copy only; Undo restores it; the Claude Code logo of the same row is the only copy then")
    func removeCodexCopyAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await hooks(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "notify-done.sh")
        #expect(model.mode(target, cli: .codex) == .toggles && model.mode(target, cli: .claude) == .toggles)
        model.toggle(target, cli: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Removed the Codex copy of notify-done.sh"
        #expect(env.toasts.current?.message == label)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed == [codexHooks], "Codex's hook file changed, Claude Code's did not")
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.hookTitle == "notify-done.sh" }?.presentCLIs == [.claude] }
        let alone = try row(model, "notify-done.sh")
        #expect(model.mode(alone, cli: .claude) == .onlyCopy, "the only copy is not a toggle")
        try await undo(model, env, label: label)
        let left = try await fixture.tree().difference(from: before)
        #expect(left.isEmpty, "differs from the original: \(left)")
    }

    @Test("a plugin's hook is read-only: no Remove, no toggle, and the write path refuses it")
    func pluginRefusal() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let plugin = ".claude/plugins/cache/neon/hooks/hooks.json"
        let file = fixture.home.appendingPathComponent(plugin)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo plugin-stop"}]}]}}"#.utf8).write(to: file)
        let (model, env, client) = try await hooks(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let target = try row(model, "echo plugin-stop")
        #expect(target.plugin == "neon" && model.mode(target, cli: .claude) == .readOnly)
        #expect(HooksWording.slot(for: target, home: nil)?.mark.kind == .lock)
        model.remove(target)
        try await wait("the toast") { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "echo plugin-stop is owned by the neon plugin. SpaceVibe cannot change it.")
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }
}

private extension HookRun {
    var lastDay: String? {
        if case .ran(_, let last) = self { last } else { nil }
    }
}
