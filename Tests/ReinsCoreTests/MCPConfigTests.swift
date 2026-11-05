import Foundation
import Testing
@testable import ReinsCore

/// Agents plan A4 (AG3, AG4): MCP servers in `~/.claude.json` and `<project>/.mcp.json`. Secrets are names only, edits stay
/// in their region, and a state file that Claude Code rewrites between the read and the write is handled.
@Suite("MCP config")
struct MCPConfigTests {
    static let canary = "CANARY-sk-live-0123456789"
    static let state = """
    {
      "numStartups": 3,
      "theme": "dark",
      "mcpServers": {
        "github": { "command": "npx", "args": ["-y", "server-github"], "env": { "GITHUB_TOKEN": "\(canary)", "DISABLE_TELEMETRY": "1" } }
      },
      "projects": {
        "/w/app": {
          "allowedTools": [],
          "mcpServers": {
            "linear": { "type": "http", "url": "https://mcp.linear.example", "headers": { "Authorization": "Bearer \(canary)" } }
          }
        }
      }
    }

    """

    final class Calls: @unchecked Sendable {
        var count = 0
    }

    @Test("servers read with their kind, target and secret names, and never a secret value")
    func read() throws {
        let home = try TempHome()
        let roots = try home.roots
        try home.write(".claude/.claude.json", Self.state)
        let user = ClaudeStateMCP.read(roots, project: nil)
        #expect(user.problem == nil)
        #expect(user.servers.map(\.name) == ["github"])
        #expect(user.servers.first?.kind == .command && user.servers.first?.target == "npx -y server-github")
        #expect(user.servers.first?.secretNames.map(\.name) == ["GITHUB_TOKEN", "DISABLE_TELEMETRY"])
        let local = ClaudeStateMCP.read(roots, project: "/w/app")
        #expect(local.servers.first?.kind == .url && local.servers.first?.target == "https://mcp.linear.example")
        #expect(local.servers.first?.secretNames == [MCPSecretName(table: "headers", name: "Authorization")])
        #expect(!"\(user.servers) \(local.servers)".contains(Self.canary))
    }

    @Test("add, remove and replace touch only mcpServers, in one entry, and Undo restores the bytes")
    func edits() throws {
        let home = try TempHome()
        let roots = try home.roots
        let file = try home.write(".claude/.claude.json", Self.state)
        let entry = try #require(try AgentSave.save(roots, label: "MCP", changes: [
            ClaudeStateMCP.fileChange(roots, project: nil, [
                .add(name: "docs", kind: .url, target: "https://docs.example.test/mcp"),
                .replaceSecret(server: "github", table: "env", name: "GITHUB_TOKEN", value: "new-token"),
            ]),
            ClaudeStateMCP.fileChange(roots, project: "/w/app", [.remove(name: "linear")]),
        ]))
        #expect(entry.ops.count == 2 || entry.ops.count == 1)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains(#""numStartups": 3"#) && text.contains(#""theme": "dark""#) && text.contains(#""allowedTools": []"#))
        #expect(text.contains("new-token") && !text.contains("Bearer"))
        #expect(ClaudeStateMCP.read(roots, project: nil).servers.map(\.name) == ["github", "docs"])
        #expect(ClaudeStateMCP.read(roots, project: "/w/app").servers.isEmpty)
        _ = try Journal.undo(roots, id: entry.id)
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.state)
    }

    @Test("a state file changed between the read and the write gets the same edit on the new content")
    func changedOnce() throws {
        let home = try TempHome()
        let roots = try home.roots
        let file = try home.write(".claude/.claude.json", Self.state)
        let calls = Calls()
        let base = ClaudeStateMCP.fileChange(roots, project: nil, [.remove(name: "github")])
        let racing = AgentFileChange(file: file, validate: { text in
            calls.count += 1
            // Claude Code writes the file once, just before Reins renames its copy over it.
            if calls.count == 1 { try Data(Self.state.replacingOccurrences(of: "\"numStartups\": 3", with: "\"numStartups\": 4").utf8).write(to: file) }
            try base.validate?(text)
        }, retries: base.retries, conflictMessage: base.conflictMessage, change: base.change)
        try AgentSave.save(roots, label: "MCP", changes: [racing])
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains(#""numStartups": 4"#))
        #expect(!text.contains("server-github"))
        #expect(text.contains(#""theme": "dark""#) && text.contains("mcp.linear.example"))
    }

    @Test("a state file that keeps changing is refused with the message, and Claude Code's write stays")
    func changedTwice() throws {
        let home = try TempHome()
        let roots = try home.roots
        let file = try home.write(".claude/.claude.json", Self.state)
        let calls = Calls()
        let base = ClaudeStateMCP.fileChange(roots, project: nil, [.remove(name: "github")])
        let racing = AgentFileChange(file: file, validate: { _ in
            calls.count += 1
            try Data(Self.state.replacingOccurrences(of: "\"numStartups\": 3", with: "\"numStartups\": \(10 + calls.count)").utf8).write(to: file)
        }, retries: base.retries, conflictMessage: base.conflictMessage, change: base.change)
        do {
            try AgentSave.save(roots, label: "MCP", changes: [racing])
            Issue.record("the save went through")
        } catch let error as ReinsError {
            #expect(error.message == ClaudeStateMCP.conflictMessage)
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("server-github") && text.contains(#""numStartups": 12"#))
        #expect(Journal.entries(roots).isEmpty)
    }

    @Test(".mcp.json: a project's shared servers, added and removed")
    func projectFile() throws {
        let home = try TempHome()
        let roots = try home.roots
        let project = home.url("w/app").path
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        try AgentSave.save(roots, label: "MCP", changes: [MCPFile.fileChange(project: project, [.add(name: "db", kind: .command, target: "db-mcp --read-only")])])
        let read = MCPFile.read(project: project)
        #expect(read.servers.map(\.target) == ["db-mcp --read-only"])
        #expect(throws: ReinsError.self) {
            try AgentSave.save(roots, label: "MCP", changes: [MCPFile.fileChange(project: project, [.add(name: "db", kind: .command, target: "x")])])
        }
    }
}
