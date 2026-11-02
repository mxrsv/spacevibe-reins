import Foundation
import ReinsCore
import SwiftUI

/// Headless screenshots of the real Rules screen, read from the synthetic HOME before any frame is drawn (`ImageRenderer`
/// draws one frame and runs no `.task`). Selected by `REINS_SHOT_SCREEN=rules` with `REINS_TEST=1` and `REINS_SHOT_DIR`:
///
///     REINS_SHOT_SCREEN=rules scripts/dev-fixture.sh --shots <dir>
///     scripts/rules-shots.sh <dir>            # all three Codex variants
///
/// `REINS_FIXTURE_CODEX=unrestricted|both` (read by `scripts/fixture-home.mjs`) changes the Codex config; in those runs only
/// the `codex-*` shot is written so the runs do not overwrite each other.
///
/// The "written" shot makes the real write through the confirmation (`requestSet`, `confirmPending`) in the synthetic HOME,
/// draws the toast, then presses Undo through the journal and checks the grid reads as before. "Invalid" corrupts one
/// project file in the synthetic HOME for one shot and restores it. Nothing outside the synthetic HOME is touched:
/// `Roots.resolve` refuses a root under the real home when `REINS_TEST=1`.
@MainActor
enum RulesShots {
    static func isRequested(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["REINS_TEST"] == "1" && environment["REINS_SHOT_SCREEN"] == "rules"
    }

    private struct ShotFailure: LocalizedError {
        let errorDescription: String?
    }

    static func run(into directory: URL) throws {
        let env = AppEnvironment.live(toasts: ToastCenter(announce: false))
        guard env.roots != nil else { throw ShotFailure(errorDescription: env.startupProblem ?? "no roots") }
        let model = RulesModel(env: env)
        model.start()
        try settle(model)
        guard let first = model.snapshot else { throw ShotFailure(errorDescription: "no snapshot") }
        let codex = first.codex

        for choice in [AppearanceChoice.dark, .light] {
            func shot(_ name: String, _ model: RulesModel = model) throws {
                let tabs: [any ReinsTab] = TabRegistry.makeTabs().map { $0.id == RulesTab.tabID ? RulesTab(model: model) : $0 }
                let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), activeID: RulesTab.tabID)
                model.shell = shell
                let view = ShellView()
                    .reinsRoot(shell: shell, toasts: env.toasts, env: env)
                    .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
                try ShotRenderer.write(view, name: "rules-\(name)", choice: choice, to: directory)
            }
            func reset() throws {
                model.setExpanded([])
                model.revealRowActions = false
                model.draft = ""
                model.addError = nil
                env.toasts.dismiss()
                model.select(.global)
                try settle(model)
            }

            try reset()
            if codex.model == .both {
                model.setExpanded([.run, .network])
                try shot("codex-both")
                continue
            }
            if codex.unrestricted {
                model.setExpanded([.run, .network])
                try shot("codex-unrestricted")
                continue
            }

            try shot("default")
            try shot("loading", RulesModel(env: env))

            model.setExpanded([.run, .network, .push])
            model.revealRowActions = true
            try shot("expanded")
            try reset()

            // The confirmation, on the global file.
            try confirm(model, .push, .deny)
            try shot("confirm")
            model.cancelPending()
            try check(model.pending == nil, "Cancel closed the confirmation and wrote nothing")

            // The confirmation with the "a kept rule still wins" warning (academy keeps a bare Bash ask).
            try select(model, name: "spacevibe-academy", file: .shared)
            try confirm(model, .push, .allow)
            try check(model.pending?.warning != nil, "the confirmation warns when a kept rule still wins")
            try shot("confirm-warning")
            model.cancelPending()
            try reset()

            // The confirmation belongs to the scope it was previewed for.
            try boundScope(model, env: env, shot: { try shot($0) })
            try reset()

            // A project scope, expanded.
            try select(model, name: "spacevibe-academy", file: .shared)
            model.setExpanded([.run])
            try shot("project")
            try select(model, name: "spacevibe-academy", file: .local)
            try shot("project-local")
            try reset()

            // A scope whose file does not exist: the first rule creates it.
            if let empty = firstMissingFile(in: model) {
                model.select(empty)
                try settle(model)
                try check(model.snapshot?.exists == false, "the missing file is reported as missing")
                try shot("first-rule")
                try reset()
            }

            // A real write through the confirmation, the toast, then a real Undo.
            let before = state(model, .push)
            try confirm(model, .push, .deny)
            model.confirmPending()
            try wait("the write") { env.toasts.current != nil }
            try settle(model)
            try check(state(model, .push) == .deny, "Set Push and deploy to Deny wrote and the grid reloaded")
            try shot("written")
            env.toasts.runCurrentAction()
            try wait("the Undo") { env.toasts.current?.message.hasPrefix("Undid") == true }
            try settle(model)
            try check(state(model, .push) == before, "Undo restored the Push and deploy cell")
            try reset()

            // A real add through the add-rule row, with the engine's duplicate message inline, then removal by Undo.
            // (On a short project file, so the row and its message are inside the frame.)
            try select(model, name: "spacevibe-bench", file: .shared)
            model.draft = "Bash(npm test *)"
            model.draftVerdict = .ask
            model.submitDraft()
            try wait("the add") { env.toasts.current != nil }
            try settle(model)
            try check(model.snapshot?.rules.contains { $0.rule == "Bash(npm test *)" } == true, "Add rule wrote the rule")
            try shot("added")
            model.draft = "Bash(npm test *)"
            model.submitDraft()
            try wait("the duplicate message") { model.addError != nil }
            try check(model.addError?.contains("already") == true, "a duplicate shows the engine's message inline")
            try shot("add-error")
            env.toasts.runCurrentAction()
            try wait("the Undo of the add") { env.toasts.current?.message.hasPrefix("Undid") == true }
            try settle(model)
            try check(model.snapshot?.rules.contains { $0.rule == "Bash(npm test *)" } == false, "Undo removed the added rule")
            try reset()

            // An invalid file: corrupt one project file for one shot.
            try withBrokenFile(model, name: "spacevibe-api") {
                try select(model, name: "spacevibe-api", file: .shared)
                try check(model.snapshot?.problems.isEmpty == false, "an invalid file is reported")
                let home = ProcessInfo.processInfo.environment["HOME"] ?? "/nonexistent"
                try check(model.snapshot?.problems.allSatisfy { !$0.contains(home) } == true, "no absolute path in the problem text")
                try shot("invalid")
            }
            try reset()
        }
    }

    // MARK: Scope binding

    /// Stale preview, vanished project, write target, the no-op wording and repeated rules, all on synthetic project files
    /// that are put back byte for byte.
    private static func boundScope(_ model: RulesModel, env: AppEnvironment, shot: (String) throws -> Void) throws {
        guard let project = model.snapshot?.projects.first(where: { $0.name == "spacevibe-academy" }),
              let bench = model.snapshot?.projects.first(where: { $0.name == "spacevibe-bench" }) else { throw ShotFailure(errorDescription: "no academy or bench project") }
        let claudeDir = URL(fileURLWithPath: project.dir).appendingPathComponent(".claude")
        let projectFile = claudeDir.appendingPathComponent("settings.json")
        let globalFile = URL(fileURLWithPath: env.roots?.claude.root.path ?? "/nonexistent").appendingPathComponent("settings.json")
        let projectBefore = try Data(contentsOf: projectFile)
        let globalBefore = try Data(contentsOf: globalFile)
        defer { try? projectBefore.write(to: projectFile) }

        // 1. A preview that finishes after the scope changed must not open a dialog.
        try select(model, name: project.name, file: .shared)
        model.requestSet(.push, to: .allow)
        model.select(.global)
        try settle(model)
        try check(model.pending == nil, "a preview that finishes after a scope switch opens no dialog")

        // 2. The project vanishes at a refresh: the open dialog closes and nothing can write to Global.
        try select(model, name: project.name, file: .shared)
        try confirm(model, .push, .allow)
        try check(model.pending?.scope == .project(project.dir), "the dialog holds the scope it was previewed for")
        let hidden = project.dir + "/.claude-hidden"
        try FileManager.default.moveItem(atPath: project.dir + "/.claude", toPath: hidden)
        defer { try? FileManager.default.moveItem(atPath: hidden, toPath: project.dir + "/.claude") }
        model.refresh()
        try settle(model)
        try check(model.snapshot?.selection == .global, "a refresh after the project vanished falls back to Global")
        try check(model.pending == nil, "the dialog for the vanished project closed")
        model.confirmPending()
        try settle(model)
        try check(try Data(contentsOf: globalFile) == globalBefore, "Global settings.json is unchanged")
        try FileManager.default.moveItem(atPath: hidden, toPath: project.dir + "/.claude")
        model.refresh()
        try settle(model)

        // 3. Confirm writes to the previewed project only.
        try select(model, name: project.name, file: .shared)
        try confirm(model, .push, .allow)
        try check(model.pending?.location.contains("spacevibe-academy") == true, "the dialog names the scope it writes to")
        try shot("confirm-scope")
        model.confirmPending()
        try wait("the write") { env.toasts.current?.message.hasPrefix("Set Push") == true }
        try settle(model)
        try check(try Data(contentsOf: projectFile) != projectBefore, "the previewed project file was written")
        try check(try Data(contentsOf: globalFile) == globalBefore, "Global settings.json is still unchanged")

        // 4. The file now holds the allow rules and a broader Ask wins: the click changes nothing, and says so.
        try check(state(model, .push) == .ask, "the cell reads Ask because a broader rule wins")
        model.requestSet(.push, to: .allow)
        try wait("the no-op toast") { env.toasts.current?.message.contains("stays") == true }
        try check(model.pending == nil, "a write that changes nothing opens no dialog")
        try check(env.toasts.current?.message == "Push and deploy stays Ask here: a rule that stays in this file wins.", "the toast names the cell's real state")
        try shot("noop")

        // 5. A hand-edited file that repeats a rule: one row per entry.
        let benchFile = URL(fileURLWithPath: bench.dir).appendingPathComponent(".claude/settings.json")
        let benchBefore = try Data(contentsOf: benchFile)
        defer { try? benchBefore.write(to: benchFile) }
        guard var json = try JSONSerialization.jsonObject(with: benchBefore) as? [String: Any] else { throw ShotFailure(errorDescription: "bench settings is not an object") }
        var permissions = json["permissions"] as? [String: Any] ?? [:]
        permissions["allow"] = ((permissions["allow"] as? [String]) ?? []) + ["Bash(echo twice)", "Bash(echo twice)"]
        json["permissions"] = permissions
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: benchFile)
        env.toasts.dismiss()
        try select(model, name: bench.name, file: .shared)
        let twice = model.snapshot?.rules.filter { $0.rule == "Bash(echo twice)" } ?? []
        try check(twice.count == 2 && twice[0].id == twice[1].id, "the repeated rule is listed twice with one id")
        try shot("duplicate-rules")
        try benchBefore.write(to: benchFile)
        try projectBefore.write(to: projectFile)
        model.refresh()
        try settle(model)
    }

    // MARK: Steps

    private static func state(_ model: RulesModel, _ capability: Capability) -> CapabilityState? {
        model.snapshot?.grid.first { $0.capability == capability }?.state
    }

    private static func confirm(_ model: RulesModel, _ capability: Capability, _ verdict: RuleVerdict) throws {
        model.requestSet(capability, to: verdict)
        try wait("the confirmation") { model.pending != nil }
    }

    private static func select(_ model: RulesModel, name: String, file: RulesFileKind) throws {
        guard let project = model.snapshot?.projects.first(where: { $0.name == name }) else { throw ShotFailure(errorDescription: "no project named \(name)") }
        model.select(RulesSelection(dir: project.dir, file: file))
        try settle(model)
    }

    private static func firstMissingFile(in model: RulesModel) -> RulesSelection? {
        for project in model.snapshot?.projects ?? [] {
            for (file, name) in [(RulesFileKind.shared, "settings.json"), (.local, "settings.local.json")]
            where !FileManager.default.fileExists(atPath: (project.dir as NSString).appendingPathComponent(".claude/\(name)")) {
                return RulesSelection(dir: project.dir, file: file)
            }
        }
        return nil
    }

    private static func withBrokenFile(_ model: RulesModel, name: String, _ body: () throws -> Void) throws {
        guard let project = model.snapshot?.projects.first(where: { $0.name == name }) else { return }
        let url = URL(fileURLWithPath: project.dir).appendingPathComponent(".claude/settings.json")
        let original = try Data(contentsOf: url)
        defer { try? original.write(to: url) }
        try Data("{ not json".utf8).write(to: url)
        try body()
    }

    private static func check(_ condition: Bool, _ what: String) throws {
        guard condition else { throw ShotFailure(errorDescription: "check failed: \(what)") }
        print("ok: \(what)")
    }

    /// Spins the main run loop until the read is done.
    private static func settle(_ model: RulesModel) throws {
        try wait("the Rules read") { model.isSettled }
    }

    private static func wait(_ what: String, until done: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard done() else { throw ShotFailure(errorDescription: "\(what) did not finish in 60 s") }
    }
}
