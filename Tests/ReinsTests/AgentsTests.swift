import Foundation
import ReinsCore
import Testing
@testable import Reins

/// The Agents page's logic that needs no window (plan A7, A8): the development switch, the panel width rules, the draft and
/// its review words, the card sentences and the Markdown preview's blocks.
@Suite("Agents page")
struct AgentsTests {
    @Test("the switch needs REINS_AGENTS=1, and outside a debug build REINS_TEST=1 as well")
    func agentsSwitch() {
        #expect(AgentsSwitch.isOn(environment: ["REINS_AGENTS": "1"], debugBuild: true))
        #expect(!AgentsSwitch.isOn(environment: ["REINS_AGENTS": "1"], debugBuild: false))
        #expect(AgentsSwitch.isOn(environment: ["REINS_AGENTS": "1", "REINS_TEST": "1"], debugBuild: false))
        #expect(!AgentsSwitch.isOn(environment: ["REINS_TEST": "1"], debugBuild: true))
        #expect(!AgentsSwitch.isOn(environment: [:], debugBuild: true))
        #expect(!AgentsSwitch.isOn(environment: ["REINS_AGENTS": "0", "REINS_TEST": "1"], debugBuild: false))
    }

    @Test("with the switch Agents takes Rules' place at ⌘2; without it Rules stays")
    @MainActor
    func registry() {
        #expect(TabRegistry.makeTabs(agents: true).map(\.id) == ["loadout", "agents", "activity"])
        #expect(TabRegistry.makeTabs(agents: false).map(\.id) == ["loadout", "rules", "activity"])
    }

    @Test("a later change to the same thing replaces the earlier one, and an add then remove cancels")
    func draft() {
        var draft = AgentDraft()
        draft.add(.change, "mode", .claude(.defaultMode("plan")))
        draft.add(.change, "mode", .claude(.defaultMode("acceptEdits")))
        #expect(draft.count == 1 && draft.claudeChanges == [.defaultMode("acceptEdits")])
        draft.add(.add, "rule", .claude(.addRule(.ask, "Bash(ls)")))
        draft.add(.remove, "rule", .claude(.removeRule(.ask, "Bash(ls)")))
        #expect(draft.count == 1)
        let file = URL(fileURLWithPath: "/w/CLAUDE.md")
        draft.add(.edit, "CLAUDE.md", .text(file: file, "a"))
        draft.add(.edit, "CLAUDE.md", .text(file: file, "ab"))
        #expect(draft.count == 2 && draft.text(for: file) == "ab")
        draft.add(.change, "approval", .codex(.approvalPolicy("never")))
        draft.add(.change, "approval", .codex(.approvalPolicy("untrusted")))
        #expect(draft.codexChanges == [.approvalPolicy("untrusted")])
        draft.remove { if case .text = $0 { return true } else { return false } }
        #expect(draft.text(for: file) == nil)
    }

    @Test("the review words, the hints and the scope titles")
    func wording() {
        var draft = AgentDraft()
        draft.add(.change, "x", warning: AgentsWording.bypassWarning, .claude(.defaultMode("bypassPermissions")))
        draft.add(.change, "y", warning: AgentsWording.bypassWarning, .claude(.model("opus")))
        #expect(AgentsReview.warnings(draft) == [AgentsWording.bypassWarning])
        #expect(AgentsWording.hints(panelOpen: false, hasDraft: false).map(\.keys) == ["Tab", "Return"])
        #expect(AgentsWording.hints(panelOpen: true, hasDraft: true).map(\.keys) == ["Esc", "\u{2318}S"])
        #expect(AgentsWording.scopeTitle(.local("/w/spacevibe-bench")) == "spacevibe-bench \u{00B7} Local")
    }

    @Test("the card sentences: Claude's mode and counts, Codex in the warn tone without a sandbox")
    func sentences() {
        let file = URL(fileURLWithPath: "/x")
        let claude = ClaudeSettingsEdit.read(file).applying([.defaultMode("acceptEdits"), .addRule(.ask, "Bash(git push *)"), .addRule(.deny, "Read(.env)"), .addRule(.deny, "Bash(rm *)")])
        #expect(AgentsWording.claudeSentence(claude).text == "Edits files without asking, asks before commands \u{00B7} 1 ask rule \u{00B7} 2 deny rules")
        let bypass = AgentsWording.claudeSentence(claude.applying([.defaultMode("bypassPermissions")]))
        #expect(bypass.text == "Runs every tool without asking" && bypass.warn)
        let full = CodexConfig.parse("approval_policy = \"never\"\nsandbox_mode = \"danger-full-access\"\n", file: file, exists: true)
        let sentence = AgentsWording.codexSentence(full)
        #expect(sentence.text == "Can write anywhere and never asks" && sentence.warn)
        let profile = CodexConfig.parse("""
        default_permissions = "edit"
        [permissions.edit.filesystem]
        ":workspace_roots" = "write"
        "~/.ssh" = "deny"
        [permissions.edit.network]
        enabled = true
        """, file: file, exists: true)
        let summary = AgentsWording.profileSentence(profile)
        #expect(summary.text == "Writes in workspace roots, blocks 1 path, open network" && summary.warn)
        #expect(AgentsWording.pathLabel(":workspace_roots/**/*.env") == "Workspace roots \u{203A} **/*.env")
        #expect(AgentsWording.codexPermissionsValue(full) == .count("Full access", warn: true))
    }

    @Test("hook copy warnings name a missing event or the tool names")
    func hookWording() {
        let hook = InventoryHook(id: "h", cli: .claude, event: "PreCompact", matcher: nil, command: "x", timeout: nil, async: false, owner: "user",
                                 removable: true, dead: false, paths: [], hash: "h", file: "/f", scope: .global, project: nil)
        #expect(AgentsHookWording.copyWarning(hook).contains("has no PreCompact event"))
        #expect(AgentsHookWording.runs(hook, scanned: false) == "not counted yet")
    }
}
