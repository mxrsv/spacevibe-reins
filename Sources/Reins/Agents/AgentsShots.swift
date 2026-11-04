import Foundation
import ReinsCore
import SwiftUI

/// Headless screenshots of the Agents page behind the switch (plan A10), read from the synthetic HOME that
/// `scripts/dev-fixture.sh --shots` writes with `REINS_FIXTURE_AGENTS=legacy|profiles|both`:
///
///     REINS_AGENTS=1 REINS_FIXTURE_AGENTS=profiles REINS_SHOT_SCREEN=agents scripts/dev-fixture.sh --shots <dir>
///
/// Every panel of both agents in both appearances, a draft with its footer, the review with a warn note, the discard
/// prompt, a real save with its Undo toast (then Undo, checked against the file), and a real failed save (the file changed
/// under the Advanced editor) whose error toast keeps the draft. The checks hold AG3: no secret of the fixture reaches a
/// panel's data, while `DISABLE_TELEMETRY` shows its value.
@MainActor
enum AgentsShots {
    static let fakeSecret = "fixture-secret-do-not-show"

    static func run(into directory: URL) throws {
        guard AgentsSwitch.isOn() else { throw ShotHarness.Failure("the Agents shots need REINS_AGENTS=1 (and REINS_TEST=1 outside a debug build)") }
        let variant = ProcessInfo.processInfo.environment["REINS_FIXTURE_AGENTS"] ?? "legacy"
        let env = AppEnvironment.live(toasts: ToastCenter(announce: false))
        guard let roots = env.roots else { throw ShotHarness.Failure(env.startupProblem ?? "no roots") }
        let model = AgentsModel(env: env)
        model.start()
        try ShotHarness.wait("the Agents read", seconds: ShotHarness.settleSeconds) { model.isSettled && model.usageScanned }
        try ShotHarness.check(model.overview?.codex.permissionModel.rawValue == variant, "the fixture's Codex permission model is \(variant)")

        for choice in [AppearanceChoice.dark, .light] {
            func shot(_ name: String) throws {
                let shell = ShotHarness.shell(around: AgentsTab(model: model), choice: choice)
                try ShotRenderer.write(ShotHarness.view(shell, env: env), name: "agents-\(variant)-\(name)", choice: choice, to: directory)
            }
            func open(_ agent: AgentKind, _ panel: AgentPanel, scope: RuleScope = .global) throws {
                env.toasts.dismiss()
                model.isReviewing = false
                model.showForShot(OpenPanel(agent: agent, panel: panel), scope: scope)
                try ShotHarness.wait("the \(agent.name) \(panel.title) panel") { model.data != nil && model.isSettled }
            }

            model.discard()
            model.request(.close)
            try shot("page")
            for panel in AgentPanel.allCases {
                try open(.codex, panel)
                try shot("codex-\(panel.rawValue)")
            }
            if variant != "legacy" { continue }
            for panel in AgentPanel.allCases {
                try open(.claude, panel)
                if panel == .mcp { model.forms.expandedServers = ["github"] }
                try shot("claude-\(panel.rawValue)")
            }
            try checkSecrets(model, roots: roots)
            try open(.claude, .rules)
            model.isEditing = true
            try shot("claude-rules-edit")
            model.isEditing = false
            model.showImport("rules/style.md")
            try shot("claude-rules-import")
            try open(.claude, .permissions, scope: .project(model.overview?.projects.first ?? ""))
            try shot("claude-permissions-project")
            try open(.claude, .permissions)
            model.draft.add(.change, "defaultMode \u{2192} Bypass", warning: AgentsWording.bypassWarning, .claude(.defaultMode("bypassPermissions")))
            model.draft.add(.add, "Bash(git push *)", tag: "Ask", tone: .warn, .claude(.addRule(.ask, "Bash(git push *)")))
            try shot("claude-permissions-draft")
            model.review()
            try shot("claude-review")
            model.isReviewing = false
            model.request(.close)
            try ShotHarness.check(model.leaving == .close && model.open != nil, "closing with a draft asks first")
            try shot("claude-discard")
            model.keepEditing()
            try saveAndUndo(model, env: env, roots: roots, shot: shot)
            try failedSave(model, env: env, roots: roots, shot: shot)
            model.request(.close)
        }
    }

    /// AG3: the masked Advanced text, the MCP rows and the permissions data never hold a secret of the fixture.
    private static func checkSecrets(_ model: AgentsModel, roots: Roots) throws {
        model.showForShot(OpenPanel(agent: .claude, panel: .advanced))
        try ShotHarness.wait("the Advanced panel") { model.data != nil && model.isSettled }
        guard case .advanced(let masked, _) = model.data else { throw ShotHarness.Failure("Advanced did not open") }
        try ShotHarness.check(!masked.text.contains(fakeSecret) && masked.hiddenCount >= 2, "settings.json shows no secret (\(masked.hiddenCount) hidden)")
        try ShotHarness.check(masked.text.contains("\"DISABLE_TELEMETRY\": \"1\""), "DISABLE_TELEMETRY shows its value")
        model.showForShot(OpenPanel(agent: .codex, panel: .advanced))
        try ShotHarness.wait("the Codex Advanced panel") { model.data != nil && model.isSettled }
        guard case .advanced(let toml, _) = model.data else { throw ShotHarness.Failure("Codex Advanced did not open") }
        try ShotHarness.check(!toml.text.contains(fakeSecret) && toml.text.contains("LANG = \"en_US.UTF-8\""), "config.toml shows no secret, LANG shows")
        model.showForShot(OpenPanel(agent: .claude, panel: .mcp))
        try ShotHarness.wait("the MCP panel") { model.data != nil && model.isSettled }
        try ShotHarness.check(!"\(String(describing: model.data))".contains(fakeSecret), "the MCP panel holds key names only")
    }

    /// A real save through the review: the rule lands in the file, the toast offers Undo, and Undo puts the bytes back.
    private static func saveAndUndo(_ model: AgentsModel, env: AppEnvironment, roots: Roots, shot: (String) throws -> Void) throws {
        let file = roots.claude.hookFile
        let before = try Data(contentsOf: file)
        model.discard()
        model.showForShot(OpenPanel(agent: .claude, panel: .permissions))
        try ShotHarness.wait("the permissions panel") { model.data != nil && model.isSettled }
        model.draft.add(.add, "Bash(make deploy)", tag: "Deny", tone: .danger, .claude(.addRule(.deny, "Bash(make deploy)")))
        model.review()
        model.save()
        try ShotHarness.wait("the save") { !model.isSaving && env.toasts.current != nil && model.isSettled }
        try ShotHarness.check(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("Bash(make deploy)"), "the save wrote the rule")
        try ShotHarness.check(model.draft.isEmpty && env.toasts.current?.action?.title == "Undo", "the toast offers Undo and the draft is gone")
        try shot("claude-saved")
        env.toasts.runCurrentAction()
        try ShotHarness.wait("the undo") { (try? Data(contentsOf: file)) == before && model.isSettled }
        try ShotHarness.check(true, "Undo restored settings.json byte for byte")
    }

    /// A save that fails (the file changed under the Advanced editor): an error toast names the reason, the draft stays.
    private static func failedSave(_ model: AgentsModel, env: AppEnvironment, roots: Roots, shot: (String) throws -> Void) throws {
        let file = roots.claude.hookFile
        let before = try Data(contentsOf: file)
        model.showForShot(OpenPanel(agent: .claude, panel: .advanced))
        try ShotHarness.wait("the Advanced panel") { model.data != nil && model.isSettled }
        guard case .advanced(let masked, _) = model.data else { throw ShotHarness.Failure("Advanced did not open") }
        model.draft.add(.edit, "settings.json", .advanced(masked.text.replacingOccurrences(of: "\"sonnet\"", with: "\"opus\"")))
        try (String(decoding: before, as: UTF8.self) + "\n").write(to: file, atomically: true, encoding: .utf8)
        model.save()
        try ShotHarness.wait("the failed save") { !model.isSaving && env.toasts.current?.tone == .danger }
        try ShotHarness.check(!model.draft.isEmpty, "a failed save keeps the draft")
        try shot("claude-error")
        try before.write(to: file)
        model.discard()
        env.toasts.dismiss()
    }
}
