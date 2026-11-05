import Foundation
import Testing
@testable import ReinsCore

/// Agents plan A5 (AG2, AG5, AG6): Codex's `config.toml`, command rules and hooks, written only where they change.
@Suite("CodexConfigEdit")
struct CodexConfigEditTests {
    static let canary = "CANARY-sk-live-0123456789"
    static let legacy = """
    # Written by hand
    model = "gpt-5-codex"
    approval_policy = "on-request"
    sandbox_mode = "workspace-write"

    [sandbox_workspace_write]
    network_access = false
    writable_roots = ["/w/cache"]

    [projects."/w/app"]
    trust_level = "trusted"

    [mcp_servers.docs]
    command = "docs-mcp"
    env = { DOCS_TOKEN = "\(canary)" }

    """

    static let profiles = """
    approval_policy = "on-request"
    default_permissions = "project-edit"

    [permissions.project-edit]
    extends = ":workspace"

    [permissions.project-edit.filesystem]
    ":workspace_roots" = "write"
    "~/.ssh" = "deny"

    [permissions.project-edit.network]
    enabled = true

    [permissions.project-edit.network.domains]
    "api.openai.com" = "allow"

    [features]
    network_proxy = true

    """

    static let both = legacy.replacingOccurrences(of: "sandbox_mode = \"workspace-write\"\n", with: "sandbox_mode = \"workspace-write\"\ndefault_permissions = \"project-edit\"\n")

    func file(_ text: String) throws -> (TempHome, Roots, URL) {
        let home = try TempHome()
        let roots = try home.roots
        let url = try home.write(".codex/config.toml", text)
        return (home, roots, url)
    }

    @Test("the legacy model reads approval, sandbox, network, roots, trust, model and MCP names")
    func readLegacy() throws {
        let (home, _, url) = try file(Self.legacy)
        defer { withExtendedLifetime(home) {} } // TempHome deletes its folder on deinit; `_` would drop it at once
        let config = CodexConfig.read(url)
        #expect(config.permissionModel == .legacy)
        #expect(config.approvalPolicy == "on-request" && config.sandboxMode == "workspace-write")
        #expect(config.networkAccess == false && config.writableRoots == ["/w/cache"])
        #expect(config.trust["/w/app"] == "trusted" && config.model == "gpt-5-codex")
        #expect(config.mcpServers.map(\.name) == ["docs"] && config.mcpServers.first?.secretNames.map(\.name) == ["DOCS_TOKEN"])
        #expect(!"\(config)".contains(Self.canary))
    }

    @Test("profiles read with their files, network and domains")
    func readProfiles() throws {
        let (home, _, url) = try file(Self.profiles)
        defer { withExtendedLifetime(home) {} } // TempHome deletes its folder on deinit; `_` would drop it at once
        let config = CodexConfig.read(url)
        #expect(config.permissionModel == .profiles)
        let profile = try #require(config.profile("project-edit"))
        #expect(profile.extends == ":workspace")
        #expect(profile.filesystem == [CodexPathRule(path: ":workspace_roots", access: "write"), CodexPathRule(path: "~/.ssh", access: "deny")])
        #expect(profile.networkEnabled && config.networkProxy)
        #expect(profile.domains == [CodexDomainRule(host: "api.openai.com", access: "allow")])
    }

    @Test("a save changes only its lines, in one entry, and Undo restores the bytes")
    func saveAndUndo() throws {
        let (home, roots, url) = try file(Self.legacy)
        defer { withExtendedLifetime(home) {} } // TempHome deletes its folder on deinit; `_` would drop it at once
        let entry = try #require(try AgentSave.save(roots, label: "How Codex runs", changes: [CodexConfigEdit.fileChange(url, [
            .approvalPolicy("never"), .networkAccess(true), .trust(project: "/w/app", level: "untrusted"), .reasoningEffort("high"),
        ])]))
        let text = try String(contentsOf: url, encoding: .utf8)
        let expected = Self.legacy
            .replacingOccurrences(of: #"approval_policy = "on-request""#, with: #"approval_policy = "never""#)
            .replacingOccurrences(of: "network_access = false", with: "network_access = true")
            .replacingOccurrences(of: #"trust_level = "trusted""#, with: #"trust_level = "untrusted""#)
            .replacingOccurrences(of: "sandbox_mode = \"workspace-write\"\n", with: "sandbox_mode = \"workspace-write\"\nmodel_reasoning_effort = \"high\"\n")
        #expect(text == expected)
        _ = try Journal.undo(roots, id: entry.id)
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.legacy)
    }

    @Test("MCP servers are added as tables, removed with them, and a secret is replaced without reading it")
    func mcp() throws {
        let (home, roots, url) = try file(Self.legacy)
        defer { withExtendedLifetime(home) {} } // TempHome deletes its folder on deinit; `_` would drop it at once
        try AgentSave.save(roots, label: "MCP", changes: [CodexConfigEdit.fileChange(url, [
            .addServer(name: "search", kind: .url, target: "https://search.example.test/mcp"),
            .replaceSecret(server: "docs", table: "env", name: "DOCS_TOKEN", value: "new-token"),
        ])])
        var config = CodexConfig.read(url)
        #expect(config.mcpServers.map(\.name) == ["docs", "search"])
        #expect(try String(contentsOf: url, encoding: .utf8).contains("new-token"))
        try AgentSave.save(roots, label: "MCP", changes: [CodexConfigEdit.fileChange(url, [.removeServer(name: "docs")])])
        config = CodexConfig.read(url)
        #expect(config.mcpServers.map(\.name) == ["search"])
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("# Written by hand\nmodel = \"gpt-5-codex\"\n"))
    }

    @Test("a write never leaves both permission models set, and each keep choice removes the other model")
    func bothModels() throws {
        let (home, roots, url) = try file(Self.both)
        defer { withExtendedLifetime(home) {} } // TempHome deletes its folder on deinit; `_` would drop it at once
        #expect(CodexConfig.read(url).permissionModel == .both)
        #expect(throws: ReinsError.self) {
            try AgentSave.save(roots, label: "Model", changes: [CodexConfigEdit.fileChange(url, [.model("o4-mini")])])
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.both)
        let keepLegacy = try CodexConfigEdit.apply([.keepModel(.legacy)], to: Self.both)
        #expect(keepLegacy == Self.legacy)
        let keepProfile = try CodexConfigEdit.apply([.keepModel(.profiles)], to: Self.both)
        let read = CodexConfig.parse(keepProfile, file: url, exists: true)
        #expect(read.permissionModel == .profiles && read.sandboxMode == nil && read.networkAccess == nil && read.writableRoots.isEmpty)
        #expect(keepProfile.contains("[projects.\"/w/app\"]") && keepProfile.contains("[mcp_servers.docs]"))
        #expect(throws: ReinsError.self) { try CodexConfigEdit.apply([.sandboxMode("read-only")], to: Self.profiles) }
    }

    @Test("profile edits: extends, file rules, network, enforcement and domains")
    func profileEdits() throws {
        let out = try CodexConfigEdit.apply([
            .profileExtends(profile: "project-edit", parent: ":read-only"),
            .pathRule(profile: "project-edit", path: "~/.ssh", access: nil),
            .pathRule(profile: "project-edit", path: ":tmpdir", access: "write"),
            .domain(profile: "project-edit", host: "**.npmjs.org", access: "allow"),
            .networkProxy(false),
        ], to: Self.profiles)
        let profile = try #require(CodexConfig.parse(out, file: URL(fileURLWithPath: "/x"), exists: true).profile("project-edit"))
        #expect(profile.extends == ":read-only")
        #expect(profile.filesystem.map(\.path) == [":workspace_roots", ":tmpdir"])
        #expect(profile.domains.map(\.host) == ["api.openai.com", "**.npmjs.org"])
        #expect(!CodexConfig.parse(out, file: URL(fileURLWithPath: "/x"), exists: true).networkProxy)
    }

    @Test("Advanced: syntax is checked by line, and masked secrets keep their bytes")
    func advanced() throws {
        #expect(throws: ReinsError.self) { try CodexConfigEdit.check("model = \"a\"\nthis is not toml\n") }
        try CodexConfigEdit.check(Self.legacy)
        let (home, roots, url) = try file(Self.legacy)
        defer { withExtendedLifetime(home) {} } // TempHome deletes its folder on deinit; `_` would drop it at once
        let masked = SecretMask.maskTOML(Self.legacy)
        let edited = masked.text.replacingOccurrences(of: "gpt-5-codex", with: "o4-mini")
        try AgentSave.save(roots, label: "Advanced", changes: [AgentSave.advancedChange(url, masked: masked, edited: edited, check: CodexConfigEdit.check)])
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.legacy.replacingOccurrences(of: "gpt-5-codex", with: "o4-mini"))
    }

    @Test("command rules: shown, added, changed and removed; a file with other code is read-only")
    func commandRules() throws {
        let home = try TempHome()
        let roots = try home.roots
        let url = try home.write(".codex/rules/default.rules", "# team rules\nprefix_rule(pattern=[\"git\", \"push\"], decision=\"prompt\")\n")
        let read = CodexRulesFile.read(url)
        #expect(read.readOnlyReason == nil && read.rules.map(\.text) == ["git push"] && read.rules.first?.decision == "prompt")
        try AgentSave.save(roots, label: "Rules", changes: [CodexRulesFile.fileChange(url, [
            .add(pattern: ["rm", "-rf"], decision: "forbidden"), .decision(pattern: ["git", "push"], to: "allow"),
        ])])
        #expect(try String(contentsOf: url, encoding: .utf8) == "# team rules\nprefix_rule(pattern=[\"git\", \"push\"], decision=\"allow\")\nprefix_rule(pattern=[\"rm\", \"-rf\"], decision=\"forbidden\")\n")
        try AgentSave.save(roots, label: "Rules", changes: [CodexRulesFile.fileChange(url, [.remove(pattern: ["git", "push"])])])
        #expect(CodexRulesFile.read(url).rules.map(\.text) == ["rm -rf"])
        let other = try home.write(".codex/rules/other.rules", "def helper():\n  pass\n")
        #expect(CodexRulesFile.read(other).readOnlyReason != nil)
        #expect(throws: ReinsError.self) {
            try AgentSave.save(roots, label: "Rules", changes: [CodexRulesFile.fileChange(other, [.add(pattern: ["ls"], decision: "allow")])])
        }
    }

    @Test("Codex hooks.json: a hook is added and removed with the shared hook edits")
    func hooks() throws {
        let home = try TempHome()
        let roots = try home.roots
        try home.write(".codex/hooks.json", "{\n  \"hooks\": {}\n}\n")
        try AgentSave.save(roots, label: "Hooks", changes: [CodexHooksFile.fileChange(roots, [.add(event: "Stop", matcher: nil, command: "say done")])])
        #expect(try String(contentsOf: roots.codex.hookFile, encoding: .utf8).contains("say done"))
        try AgentSave.save(roots, label: "Hooks", changes: [CodexHooksFile.fileChange(roots, [.remove(event: "Stop", matcher: nil, command: "say done")])])
        #expect(!(try String(contentsOf: roots.codex.hookFile, encoding: .utf8)).contains("say done"))
    }
}
