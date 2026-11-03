import Foundation
import Testing
import ReinsCore
@testable import Reins

/// The Network cell of a Codex profile must never put a secret-looking string on screen (AGENTS.md S-R3).
@Suite("Codex network flags")
struct CodexCellWordingTests {
    private static let canary = "http://user:CANARY-sk-live-0123456789@proxy.example.com:8080"

    /// Reads a config.toml from a throwaway home, the way the Rules screen does.
    private func permissions(_ toml: String) throws -> CodexPermissions {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root = base.appendingPathComponent("reins-codex-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try toml.write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let env = [
            "HOME": root.path,
            "CLAUDE_CONFIG_DIR": root.appendingPathComponent(".claude").path,
            "CODEX_HOME": codex.path,
            "REINS_HOME": root.appendingPathComponent(".reins").path,
            "REINS_TEST": "1",
        ]
        return CodexPermissions.read(roots: try Roots.resolve(env: env))
    }

    @Test("a URL, a token or any other free text under the network table is not shown; flags and mode words are")
    func networkCellHidesText() throws {
        let codex = try permissions("""
        default_permissions = "dev"

        [permissions.dev.network]
        enabled = true
        mode = "limited"
        proxy = "\(Self.canary)"
        token = "CANARY-sk-live-0123456789"
        timeout = 30
        """)
        let cell = CodexCellWording.cell(.network, codex)
        let shown = cell.keys.map(\.value).joined(separator: "\n") + (cell.note ?? "") + cell.label

        #expect(!shown.contains("CANARY"))
        let values = Dictionary(uniqueKeysWithValues: cell.keys.map { ($0.shortKey, $0.value) })
        #expect(values["enabled"] == "true")
        #expect(values["mode"] == "limited")
        #expect(values["timeout"] == "30")
        #expect(values["proxy"] == CodexCellWording.hiddenFlagText)
        #expect(values["token"] == CodexCellWording.hiddenFlagText)
    }
}
