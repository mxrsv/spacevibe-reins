import Foundation
import Testing
@testable import ReinsCore

/// Agents plan A1 (AG3): which values are secret, masking them, putting them back, and the copies Reins keeps.
@Suite("SecretMask")
struct SecretMaskTests {
    /// Stands in for a secret: it must never appear in masked text or an error.
    static let canary = "CANARY-sk-live-0123456789"

    @Test("a key name is secret when it holds key, token, secret, password or auth, in any case")
    func names() {
        for name in ["ANTHROPIC_API_KEY", "GITHUB_TOKEN", "client_secret", "DB_PASSWORD", "Authorization", "apiKeyHelper"] {
            #expect(SecretMask.isSecretName(name), "\(name)")
        }
        for name in ["DISABLE_TELEMETRY", "model", "command", "PATH", "defaultMode"] {
            #expect(!SecretMask.isSecretName(name), "\(name)")
        }
    }

    @Test("every value of an MCP server's environment and headers is secret, elsewhere the key name decides")
    func paths() {
        #expect(SecretMask.isSecretJSON(["mcpServers", "github", "env", "GITHUB_ORG"]))
        #expect(SecretMask.isSecretJSON(["mcpServers", "linear", "headers", "X-Workspace"]))
        #expect(SecretMask.isSecretJSON(["projects", "/w/app", "mcpServers", "db", "env", "PGHOST"]))
        #expect(SecretMask.isSecretJSON(["env", "OPENAI_API_KEY"]))
        #expect(SecretMask.isSecretJSON(["apiKeys", "[0]"]))
        #expect(!SecretMask.isSecretJSON(["env", "DISABLE_TELEMETRY"]))
        #expect(!SecretMask.isSecretJSON(["mcpServers", "github", "command"]))
        #expect(!SecretMask.isSecretJSON(["mcpServers", "github", "args", "[1]"]))
        #expect(!SecretMask.isSecretJSON(["mcpServers", "env", "command"]))
        #expect(SecretMask.isSecretTOML(["mcp_servers", "docs", "env", "DOCS_HOST"]))
        #expect(SecretMask.isSecretTOML(["mcp_servers", "docs", "http_headers", "X-Team"]))
        #expect(SecretMask.isSecretTOML(["mcp_servers", "docs", "env_http_headers", "Authorization"]))
        #expect(SecretMask.isSecretTOML(["shell_environment_policy", "set", "MY_TOKEN"]))
        #expect(!SecretMask.isSecretTOML(["shell_environment_policy", "set", "LANG"]))
        #expect(!SecretMask.isSecretTOML(["model"]))
        #expect(!SecretMask.isSecretTOML(["mcp_servers", "docs", "url"]))
    }

    static let json = """
    {
      "env": {
        "DISABLE_TELEMETRY": "1",
        "ANTHROPIC_API_KEY": "\(canary)"
      },
      "mcpServers": {
        "github": { "command": "npx", "args": ["-y", "server-github"], "env": { "GITHUB_ORG": "\(canary)-org", "RETRIES": 3 } },
        "linear": { "url": "https://mcp.example.test", "headers": { "Authorization": "Bearer \(canary)" } }
      }
    }

    """

    @Test("JSON: secrets read as the placeholder, plain values as they are, and an unchanged save gives the same bytes")
    func maskJSON() throws {
        let masked = try SecretMask.maskJSON(Self.json)
        #expect(!masked.text.contains(Self.canary))
        #expect(masked.text.contains(#""DISABLE_TELEMETRY": "1""#))
        #expect(masked.text.contains(#""command": "npx""#))
        #expect(masked.text.contains(#""RETRIES": "\#(SecretMask.placeholder)""#))
        #expect(masked.hiddenCount == 4)
        #expect(try masked.unmask(masked.text) == Self.json)
    }

    @Test("JSON: an edit elsewhere keeps the secret bytes, a retyped secret is the new value, a moved placeholder is refused")
    func unmaskJSON() throws {
        let masked = try SecretMask.maskJSON(Self.json)
        let edited = masked.text.replacingOccurrences(of: #""DISABLE_TELEMETRY": "1""#, with: #""DISABLE_TELEMETRY": "0""#)
        let saved = try masked.unmask(edited)
        #expect(saved == Self.json.replacingOccurrences(of: #""DISABLE_TELEMETRY": "1""#, with: #""DISABLE_TELEMETRY": "0""#))
        #expect(saved.contains(Self.canary))

        let retyped = masked.text.replacingOccurrences(of: #""ANTHROPIC_API_KEY": "\#(SecretMask.placeholder)""#, with: #""ANTHROPIC_API_KEY": "new""#)
        let next = try masked.unmask(retyped)
        #expect(next.contains(#""ANTHROPIC_API_KEY": "new""#))
        #expect(next.contains("\(Self.canary)-org"))

        let moved = masked.text.replacingOccurrences(of: #""ANTHROPIC_API_KEY""#, with: #""OTHER_NAME""#)
        do {
            _ = try masked.unmask(moved)
            Issue.record("a moved placeholder was accepted")
        } catch let error as ReinsError {
            #expect(error.status == 409)
            #expect(!error.message.contains(Self.canary))
        }
        #expect(throws: ReinsError.self) { try masked.unmask("{ \"env\": ") }
    }

    static let toml = """
    # Codex settings
    model = "gpt-5-codex"

    [shell_environment_policy]
    set = { LANG = "en_US.UTF-8", MY_TOKEN = "\(canary)" }

    [mcp_servers.docs]
    command = "docs-mcp"
    args = [
      "--port", # the port
      "4000",
    ]
    env = { DOCS_HOST = "\(canary)-host" }

    [mcp_servers."remote docs".http_headers]
    "X-Team" = '\(canary)-team'

    """

    @Test("TOML: inline tables, tables and quoted names mask by path, and an unchanged save gives the same bytes")
    func maskTOML() throws {
        let masked = SecretMask.maskTOML(Self.toml)
        #expect(!masked.text.contains(Self.canary))
        #expect(masked.text.contains(#"LANG = "en_US.UTF-8""#))
        #expect(masked.text.contains(#"model = "gpt-5-codex""#))
        #expect(masked.text.contains("# the port"))
        #expect(masked.hiddenCount == 3)
        #expect(try masked.unmask(masked.text) == Self.toml)

        let moved = masked.text.replacingOccurrences(of: "MY_TOKEN", with: "MY_NAME")
        #expect(throws: ReinsError.self) { try masked.unmask(moved) }
        let edited = masked.text.replacingOccurrences(of: #""4000""#, with: #""4001""#)
        #expect(try masked.unmask(edited) == Self.toml.replacingOccurrences(of: #""4000""#, with: #""4001""#))
    }

    @Test("the copy kept before a write holds the secret in a 0600 file, inside 0700 trash folders")
    func trashMode() throws {
        let home = try TempHome()
        let roots = try home.roots
        let settings = try home.write(".claude/settings.json", Self.json)
        let op = try #require(try FileEdit.apply(roots, file: settings) { $0?.replacingOccurrences(of: "\"1\"", with: "\"0\"") })
        let backup = URL(fileURLWithPath: try #require(op.json["backup"]?.stringValue))
        #expect(try home.mode(of: backup) == 0o600)
        #expect(try home.mode(of: backup.deletingLastPathComponent()) == 0o700)
        #expect(try home.mode(of: roots.data.appendingPathComponent("trash")) == 0o700)
        #expect(try String(contentsOf: backup, encoding: .utf8).contains(Self.canary))
    }
}
