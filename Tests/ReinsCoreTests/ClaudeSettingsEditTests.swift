import Foundation
import Testing
@testable import ReinsCore

/// Agents plan A3 (AG2, AG3): the Claude Code panels' edits at every scope write only the edit, undo to the original
/// bytes, share one journal entry per save, and the Advanced save keeps masked secrets byte for byte.
@Suite("ClaudeSettingsEdit")
struct ClaudeSettingsEditTests {
    static let canary = "CANARY-sk-live-0123456789"
    static let settings = """
    {
      "model": "sonnet",
      "env": {
        "DISABLE_TELEMETRY": "1",
        "ANTHROPIC_API_KEY": "\(canary)"
      },
      "permissions": {
        "defaultMode": "default",
        "allow": ["Read(*)", "Bash(git status)"],
        "deny": ["Bash(rm -rf:*)"],
        "additionalDirectories": ["/w/shared"]
      },
      "hooks": {
        "Stop": [{ "hooks": [{ "type": "command", "command": "afplay done.aiff" }] }]
      }
    }

    """

    struct Sandbox {
        let home: TempHome
        let roots: Roots
        let project: URL

        init() throws {
            home = try TempHome()
            roots = try home.roots
            project = home.url("work/app")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        }

        /// The settings file of a scope, written with the shared fixture.
        func file(_ scope: RuleScope) throws -> URL {
            let store = RulesStore(roots: roots, projects: { [project.path] })
            let url = try store.file(for: scope)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(ClaudeSettingsEditTests.settings.utf8).write(to: url)
            return url
        }
    }

    /// The part of `before` that `after` replaced: everything between their common prefix and common suffix.
    static func changedRegion(_ before: String, _ after: String) -> String {
        let a = Array(before.utf8), b = Array(after.utf8)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        return String(decoding: a[prefix..<(a.count - suffix)], as: UTF8.self)
    }

    static func scopes(_ sandbox: Sandbox) -> [RuleScope] {
        [.global, .project(sandbox.project.path), .local(sandbox.project.path)]
    }

    @Test("every scope: a save writes exactly its edits, in one journal entry, and Undo restores the bytes")
    func saveAndUndo() throws {
        let sandbox = try Sandbox()
        for scope in Self.scopes(sandbox) {
            let file = try sandbox.file(scope)
            let before = try Data(contentsOf: file)
            let entry = try #require(try AgentSave.save(sandbox.roots, label: "Permissions at \(scope.kind)", changes: [
                ClaudeSettingsEdit.fileChange(file, [.defaultMode("acceptEdits"), .addRule(.ask, "Bash(git push *)")]),
            ]))
            #expect(entry.ops.count == 1)
            let after = try String(contentsOf: file, encoding: .utf8)
            // The bytes that differ lie inside the permissions block: model, env and hooks are untouched.
            let region = Self.changedRegion(Self.settings, after)
            #expect(region.hasPrefix("default") && !region.contains("model") && !region.contains("env") && !region.contains("hooks"))
            #expect(after.contains(Self.canary))
            let read = ClaudeSettingsEdit.read(file)
            #expect(read.defaultMode == "acceptEdits" && read.ask == ["Bash(git push *)"] && read.allow == ["Read(*)", "Bash(git status)"])
            _ = try Journal.undo(sandbox.roots, id: entry.id)
            #expect(try Data(contentsOf: file) == before)
        }
    }

    @Test("folders, model and hooks edit only their own region")
    func otherFields() throws {
        let sandbox = try Sandbox()
        let file = try sandbox.file(.global)
        try AgentSave.save(sandbox.roots, label: "Edits", changes: [ClaudeSettingsEdit.fileChange(file, [
            .addDirectory("/w/docs"), .removeDirectory("/w/shared"), .model("opus"),
            .addHook(event: "PostToolUse", matcher: "Edit", command: "prettier --write"),
            .removeHook(event: "Stop", matcher: nil, command: "afplay done.aiff"),
        ])])
        let read = ClaudeSettingsEdit.read(file)
        #expect(read.additionalDirectories == ["/w/docs"])
        #expect(read.model == "opus")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("prettier --write") && !text.contains("afplay"))
        #expect(text.contains(#""DISABLE_TELEMETRY": "1""#) && text.contains(Self.canary))
        // Removing the model and the mode ("Same as Global") drops the keys.
        try AgentSave.save(sandbox.roots, label: "Unset", changes: [ClaudeSettingsEdit.fileChange(file, [.model(nil), .defaultMode(nil)])])
        let unset = ClaudeSettingsEdit.read(file)
        #expect(unset.model == nil && unset.defaultMode == nil)
    }

    @Test("a rule must be Tool or Tool(pattern), and a duplicate names the group that holds it")
    func ruleChecks() throws {
        let sandbox = try Sandbox()
        let read = ClaudeSettingsEdit.read(try sandbox.file(.global))
        #expect(try ClaudeSettingsEdit.checkNewRule(" Bash(npm test *) ", in: read) == "Bash(npm test *)")
        #expect(throws: ReinsError.self) { try ClaudeSettingsEdit.checkNewRule("not a rule(", in: read) }
        do {
            _ = try ClaudeSettingsEdit.checkNewRule("Bash(rm -rf:*)", in: read)
            Issue.record("a duplicate was accepted")
        } catch let error as ReinsError {
            #expect(error.message.contains("Deny"))
        }
    }

    @Test("Advanced: an unchanged secret keeps its bytes, an edit elsewhere lands, a changed file is refused")
    func advanced() throws {
        let sandbox = try Sandbox()
        let file = try sandbox.file(.global)
        let masked = try SecretMask.maskJSON(Self.settings)
        #expect(!masked.text.contains(Self.canary) && masked.text.contains(#""DISABLE_TELEMETRY": "1""#))
        let edited = masked.text.replacingOccurrences(of: #""model": "sonnet""#, with: #""model": "haiku""#)
        let check: @Sendable (String) throws -> Void = { text in _ = try FileEdit.parseObject(text, file: file) }
        let entry = try #require(try AgentSave.save(sandbox.roots, label: "Advanced", changes: [
            AgentSave.advancedChange(file, masked: masked, edited: edited, check: check),
        ]))
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.settings.replacingOccurrences(of: #""model": "sonnet""#, with: #""model": "haiku""#))
        _ = try Journal.undo(sandbox.roots, id: entry.id)
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.settings)

        try Data((Self.settings + " ").utf8).write(to: file)
        #expect(throws: ReinsError.self) {
            try AgentSave.save(sandbox.roots, label: "Advanced", changes: [AgentSave.advancedChange(file, masked: masked, edited: edited, check: check)])
        }
    }

    @Test("managed settings are never written, and a failed second file rolls the first back")
    func guards() throws {
        let sandbox = try Sandbox()
        let managed = URL(fileURLWithPath: AgentSave.managedFolder).appendingPathComponent("managed-settings.json")
        do {
            try AgentSave.save(sandbox.roots, label: "Managed", changes: [ClaudeSettingsEdit.fileChange(managed, [.model("opus")])])
            Issue.record("a managed file was accepted")
        } catch let error as ReinsError {
            #expect(error.status == 403)
        }
        let global = try sandbox.file(.global)
        let before = try Data(contentsOf: global)
        let broken = try sandbox.home.write("work/app/.claude/settings.json", "{ not json")
        #expect(throws: ReinsError.self) {
            try AgentSave.save(sandbox.roots, label: "Two files", changes: [
                ClaudeSettingsEdit.fileChange(global, [.model("opus")]),
                ClaudeSettingsEdit.fileChange(broken, [.model("opus")]),
            ])
        }
        #expect(try Data(contentsOf: global) == before)
        #expect(ClaudeSettingsEdit.read(broken).problem != nil)
    }
}
