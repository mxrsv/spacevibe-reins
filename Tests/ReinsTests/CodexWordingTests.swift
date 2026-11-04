import Foundation
import Testing
import ReinsCore
@testable import Reins

/// The Codex page of Rules: what it says about a config, and that no secret-looking string from `config.toml` reaches the
/// screen (AGENTS.md S-R3).
@Suite("Codex page wording")
struct CodexWordingTests {
    private static let canary = "http://user:CANARY-sk-live-0123456789@proxy.example.com:8080"

    /// Reads a config.toml (and rules files) from a throwaway home, the way the Rules screen does.
    private func permissions(_ toml: String?, rules: String? = nil) throws -> CodexPermissions {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root = base.appendingPathComponent("reins-codex-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex.appendingPathComponent("rules"), withIntermediateDirectories: true)
        if let toml { try toml.write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8) }
        if let rules { try rules.write(to: codex.appendingPathComponent("rules/default.rules"), atomically: true, encoding: .utf8) }
        let env = [
            "HOME": root.path,
            "CLAUDE_CONFIG_DIR": root.appendingPathComponent(".claude").path,
            "CODEX_HOME": codex.path,
            "REINS_HOME": root.appendingPathComponent(".reins").path,
            "REINS_TEST": "1",
        ]
        return CodexPermissions.read(roots: try Roots.resolve(env: env))
    }

    /// Every string the page would draw for this config.
    private func shown(_ codex: CodexPermissions) -> String {
        let status = CodexWording.status(codex)
        let rows = CodexWording.rows(codex).map { row -> String in
            switch row.value {
            case .options(let options, let picked, _): return ([row.title, row.key, picked ?? ""] + options).joined(separator: "\n")
            case .tag(let text, _): return [row.title, row.key, text].joined(separator: "\n")
            }
        }
        return ([status.sentence, status.detail ?? ""] + rows).joined(separator: "\n")
    }

    @Test("a URL, a token or any other free text under the network table is not shown; flags and mode words are")
    func networkFlagsHideText() throws {
        let codex = try permissions("""
        default_permissions = "dev"

        [permissions.dev.network]
        enabled = true
        mode = "limited"
        proxy = "\(Self.canary)"
        token = "CANARY-sk-live-0123456789"
        timeout = 30
        """)
        let text = shown(codex)
        #expect(!text.contains("CANARY"))
        let network = CodexWording.rows(codex).first { $0.title == "Network in the profile" }
        guard case .tag(let flags, _)? = network?.value else { Issue.record("no profile network row"); return }
        #expect(flags.contains("enabled = true"))
        #expect(flags.contains("mode = limited"))
        #expect(flags.contains("timeout = 30"))
        #expect(flags.contains("proxy = \(CodexWording.hiddenText)"))
        #expect(flags.contains("token = \(CodexWording.hiddenText)"))
    }

    @Test("a profile name, a reviewer or a mode that is not a plain word is not shown")
    func freeTextValuesAreHidden() throws {
        let codex = try permissions("""
        default_permissions = "CANARY-sk-live-0123456789"
        approvals_reviewer = "\(Self.canary)"
        approval_policy = "CANARY-token-value-0123"
        sandbox_mode = "CANARY sandbox value"
        """)
        #expect(!shown(codex).contains("CANARY"))
    }

    @Test("no sandbox and never asking reads as a warning, and every option of both keys is written out")
    func unrestricted() throws {
        let codex = try permissions("""
        approval_policy = "never"
        sandbox_mode = "danger-full-access"
        """, rules: #"prefix_rule(pattern=["git", "push"], decision="allow")"#)
        let status = CodexWording.status(codex)
        #expect(status.tone == .warn)
        #expect(status.sentence == "Has no sandbox and never asks")
        let rows = CodexWording.rows(codex)
        #expect(rows.first { $0.title == "Asks before acting" }?.value == .options(["Unless allowed", "When needed", "Never"], picked: "Never", warn: true))
        #expect(rows.first { $0.title == "Sandbox" }?.value == .options(["Read only", "Workspace", "Full access"], picked: "Full access", warn: true))
        #expect(rows.first { $0.title == "Network" }?.value == .tag("open", tone: .warn))
        #expect(rows.first { $0.title == "Can write to" }?.value == .tag("anywhere", tone: .warn))
    }

    @Test("command rules that forbid or prompt are named in the warning, since they still hold Codex back")
    func unrestrictedWithRules() throws {
        let codex = try permissions("""
        approval_policy = "never"
        sandbox_mode = "danger-full-access"
        """, rules: """
        prefix_rule(pattern=["rm", "-rf"], decision="forbidden")
        prefix_rule(pattern=["git", "push"], decision="prompt")
        """)
        #expect(CodexWording.status(codex).sentence == "Has no sandbox and never asks, except for 2 command rules")
        let asking = try permissions("approval_policy = \"on-request\"\nsandbox_mode = \"danger-full-access\"\n")
        #expect(CodexWording.status(asking) == CodexStatus(tone: .warn, sentence: "Has no sandbox and asks when it needs more", detail: #"sandbox_mode = "danger-full-access" · approval_policy = "on-request""#))
    }

    @Test("the workspace sandbox that asks when needed reads as safe; network and folders come from its table")
    func workspace() throws {
        let codex = try permissions("""
        approval_policy = "on-failure"
        sandbox_mode = "workspace-write"

        [sandbox_workspace_write]
        network_access = false
        writable_roots = ["/tmp/a"]
        """)
        let status = CodexWording.status(codex)
        #expect(status.tone == .success)
        #expect(status.sentence == "Writes only inside the workspace and asks when it needs more")
        let rows = CodexWording.rows(codex)
        // on-failure is an alias of on-request: the segment says so and the key keeps the written value.
        #expect(rows.first { $0.title == "Asks before acting" }?.value == .options(["Unless allowed", "When needed", "Never"], picked: "When needed", warn: false))
        #expect(rows.first { $0.title == "Asks before acting" }?.key == #"approval_policy = "on-failure""#)
        #expect(rows.first { $0.title == "Network" }?.value == .options(["Off", "On"], picked: "Off", warn: false))
        #expect(rows.first { $0.title == "Can write to" }?.value == .tag("the workspace and 1 more folder", tone: .neutral))
    }

    @Test("a missing config says Codex runs on its defaults and shows no setting rows")
    func missing() throws {
        let codex = try permissions(nil)
        #expect(CodexWording.status(codex).tone == .neutral)
        #expect(CodexWording.status(codex).sentence.contains("there is no ~/.codex/config.toml"))
        #expect(CodexWording.rows(codex).isEmpty)
    }

    @Test("command rules are counted per decision, strictest first, with no pattern")
    func ruleCounts() throws {
        let codex = try permissions("approval_policy = \"on-request\"\n", rules: """
        prefix_rule(pattern=["git", "push"], decision="allow")
        prefix_rule(pattern=["curl", "-H", "Authorization: Bearer CANARY-sk-live-0123456789"], decision="prompt")
        prefix_rule(pattern=["rm"], decision="forbidden")
        """)
        let counts = CodexWording.ruleCounts(codex)
        #expect(counts.map(\.title) == ["Forbidden", "Prompt", "Allow"])
        #expect(counts.map(\.count) == [1, 1, 1])
        #expect(!counts.map { $0.title + $0.meaning }.joined().contains("CANARY"))
    }
}
