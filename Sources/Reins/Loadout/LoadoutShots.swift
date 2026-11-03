import Foundation
import ReinsCore
import SwiftUI

/// Headless screenshots of the real Loadout screen, read from the synthetic HOME before any frame is drawn (`ImageRenderer`
/// draws one frame and runs no `.task`). `ShotRenderer.run` starts it for `REINS_SHOT_SCREEN=loadout`; `ShotHarness` holds the
/// checks, waits and shell it shares with the Rules and Activity runs. CI runs it through `scripts/dev-fixture.sh --shots`:
///
///     REINS_SHOT_SCREEN=loadout scripts/dev-fixture.sh --shots <dir>
///
/// The "added" and "removed" shots make the real write in the synthetic HOME, draw the toast, then undo it through the journal
/// and check the row is back, so one run also exercises Add to, Remove and Undo against real files. Nothing outside the
/// synthetic HOME is touched: `Roots.resolve` refuses a root under the real home when `REINS_TEST=1`.
@MainActor
enum LoadoutShots {
    static func run(into directory: URL) throws {
        let env = AppEnvironment.live(toasts: ToastCenter(announce: false))
        guard let roots = env.roots else { throw ShotHarness.Failure(env.startupProblem ?? "no roots") }
        let model = LoadoutModel(env: env)
        model.start()
        try settle(model)

        for choice in [AppearanceChoice.dark, .light] {
            func shot(_ name: String, _ model: LoadoutModel = model, query: String? = nil) throws {
                let shell = ShotHarness.shell(around: LoadoutTab(model: model), choice: choice)
                model.shell = shell
                if let query { shell.openPalette(query: query) }
                try ShotRenderer.write(ShotHarness.view(shell, env: env), name: "loadout-\(name)", choice: choice, to: directory)
            }
            func reset() {
                model.scope = LoadoutRows.globalScope
                model.filter = .all
                model.selectedKey = nil
                model.shotKinds = nil
                model.revealRowActions = false
                env.toasts.dismiss()
            }

            try shot("default")
            try shot("loading", LoadoutModel(env: env))

            model.shotKinds = [.hook]
            model.revealRowActions = true
            try shot("hooks")
            reset()

            model.filter = .never
            try shot("never")
            model.filter = .dead
            try shot("dead")
            reset()

            if let project = model.data?.scopes.dropFirst().first?.value {
                model.scope = project
                try shot("project")
                model.filter = .dead
                try shot("empty-filter")
                reset()
            }

            try shot("palette", query: "dead")

            // Add to Codex: a real copy, the toast, then a real Undo.
            if let row = model.data?.rows.first(where: { $0.name == "ponytail" }), let id = LoadoutRows.copyPlan(row, to: .codex, events: model.data?.events ?? [:]) {
                let entry = try Mutate.copyToOther(roots: roots, id: id)
                model.reload()
                try settle(model)
                env.toasts.show(LoadoutFormat.addLabel(row: row, to: .codex), undo: {})
                try shot("added")
                reset()
                _ = try Journal.undo(roots, id: entry.id)
                model.reload()
                try settle(model)
                try checkCell(model, "ponytail", cli: .codex, matches: { $0.isMissing }, what: "Undo of Add to Codex restored the empty cell")
            }

            // Remove: a real removal from Claude Code, the toast, then a real Undo.
            if let row = model.data?.rows.first(where: { $0.name == "tdd" }), let member = row.removableMembers.first {
                let entry = try Mutate.removeItem(roots: roots, id: member.id)
                model.reload()
                try settle(model)
                env.toasts.show(LoadoutFormat.removeLabel(row: row, member: member), undo: {})
                try shot("removed")
                reset()
                _ = try Journal.undo(roots, id: entry.id)
                model.reload()
                try settle(model)
                try checkCell(model, "tdd", cli: .claude, matches: { !$0.isMissing }, what: "Undo of Remove restored the skill")
            }

            try memberChecks()
            try deadHookChecks(model, env: env, roots: roots)
        }
    }

    /// Two items with one key in one CLI: the row keeps the one the usage cells are built from (the last).
    private static func memberChecks() throws {
        func skill(_ id: String) -> InventoryItem {
            InventoryItem(id: id, cli: .claude, kind: .skill, name: "twin", entry: "SKILL.md", description: "", owner: "user", path: "/x/\(id)", file: "/x/\(id)/SKILL.md", removable: true, scope: .global, project: nil)
        }
        let snapshot = InventorySnapshot(items: [skill("first"), skill("second")], hooks: [], problems: [], roots: [:])
        let row = LoadoutRows.build(snapshot, home: nil).first
        try ShotHarness.check(row?.members[.claude]?.id == "second", "a row with two same-key items acts on the item its cell is built from")
    }

    /// The dead-hook count in the toast is the engine's, the guard outlives the write, and a double click writes once.
    private static func deadHookChecks(_ model: LoadoutModel, env: AppEnvironment, roots: Roots) throws {
        let count = model.deadHookCount(cli: .claude)
        guard count > 0 else { return }
        let direct = try Mutate.removeDeadHooks(roots: roots, cli: .claude)
        try ShotHarness.check(direct.label.hasPrefix("Removed \(count) dead hook"), "the dead-hook count matches the engine's journal label (\(direct.label))")
        _ = try Journal.undo(roots, id: direct.id)
        model.reload()
        try settle(model)

        env.toasts.dismiss()
        model.removeDeadHooks(cli: .claude)
        model.removeDeadHooks(cli: .claude)
        try ShotHarness.check(model.guardedWrites == 1, "a second click while the write runs is ignored")
        try ShotHarness.wait("the dead-hook write") { env.toasts.current != nil }
        try ShotHarness.check(env.toasts.current?.tone != .danger, "the dead-hook write succeeded")
        try ShotHarness.check(env.toasts.current?.message.hasPrefix("Removed \(count) dead hook") == true, "the toast counts every dead hook (\(env.toasts.current?.message ?? ""))")
        try ShotHarness.check(model.guardedWrites == 1, "the guard is still held right after the write finished")
        try ShotHarness.wait("the guard release") { model.guardedWrites == 0 }
        env.toasts.runCurrentAction()
        try ShotHarness.wait("the Undo of the dead hooks") { env.toasts.current?.message.hasPrefix("Undid") == true }
        try settle(model)
        try ShotHarness.check(model.deadHookCount(cli: .claude) == count, "Undo restored the dead hooks")
        env.toasts.dismiss()
    }

    private static func checkCell(_ model: LoadoutModel, _ name: String, cli: InventoryCLI, matches predicate: (UsageCellState) -> Bool, what: String) throws {
        let row = model.data?.rows.first(where: { $0.name == name })
        try ShotHarness.check(row.map { predicate($0.cells[cli]) } ?? false, what)
    }

    /// Spins the main run loop until reads, the scan and the builds are done, or the read fails.
    private static func settle(_ model: LoadoutModel) throws {
        try ShotHarness.wait("the Loadout read", seconds: ShotHarness.settleSeconds) { model.isSettled || model.readFailure != nil }
        if let failure = model.readFailure { throw ShotHarness.Failure(failure) }
    }
}
