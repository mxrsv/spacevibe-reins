import Foundation
import Testing
@testable import ReinsCore

// Token rows of one log. Logs are written into a TempHome (AGENTS.md S-R1) from TokenLines; nothing comes from a real log.

private typealias K = TokenLines.Kinds

private func fold(_ h: TempHome, _ relative: String, _ lines: [String], cli: InventoryCLI, fallbackMs: Double = 0) throws -> TokenLog {
    let url = try h.write(relative, lines.joined(separator: "\n") + "\n")
    return try #require(TokenFold.read(url, cli: cli, fallbackMs: fallbackMs, maxLineBytes: UsageScanner.maxLineBytes))
}

private func total(_ log: TokenLog) -> TokenCounts { log.rows.reduce(TokenCounts.zero) { $0 + $1.counts } }

@Suite("Token fold")
struct TokenFoldTests {
    @Test("repeated streaming blocks count a message once, at its largest values")
    func streamingBlocks() throws {
        let h = try TempHome()
        let at = "2026-10-30T09:15:00.000Z"
        let log = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claude(at, id: "msg_1", K(input: 12, output: 4, cacheWrite: 900, cacheRead: 30_000)),
            TokenLines.claude(at, id: "msg_1", K(input: 12, output: 4, cacheWrite: 900, cacheRead: 30_000)),
            TokenLines.claude(at, id: "msg_1", K(input: 12, output: 250, cacheWrite: 900, cacheRead: 30_000)),
            TokenLines.claude(at, id: "msg_2", K(input: 3, output: 10, cacheRead: 31_000)),
        ], cli: .claude)
        #expect(log.rows == [TokenRow(hour: TokenLines.hour(at), model: "claude-opus-5-5",
                                      counts: TokenCounts(input: 15, cacheWrite: 900, cacheRead: 61_000, output: 260))])
    }

    @Test("the one-hour cache write stays inside cache write, not a fifth kind")
    func longCacheWrite() throws {
        let h = try TempHome()
        let log = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claude("2026-10-30T09:15:00Z", id: "msg_1", K(input: 1, output: 2, cacheWrite: 1000, cacheWrite1h: 400)),
        ], cli: .claude)
        let c = total(log)
        #expect(c.cacheWrite == 1000 && c.cacheWrite1h == 400 && c.total == 1003)
    }

    @Test("a Codex total seen twice counts once, and its input is stored without the cached tokens")
    func codexTotals() throws {
        let h = try TempHome()
        let log = try fold(h, ".codex/sessions/2026/10/30/rollout-2026-10-30T09-00-00-\(TokenLines.rolloutId).jsonl", [
            TokenLines.codexMeta("2026-10-30T09:00:00Z", id: TokenLines.rolloutId, cwd: h.url("work/beta-api").path),
            TokenLines.codexTurn("2026-10-30T09:00:01Z", model: "gpt-6-astra"),
            TokenLines.codexCount("2026-10-30T09:01:00Z", total: (1000, 600, 50), last: (1000, 600, 50)),
            // The same running total again (an interleaved stream repeats it): adds nothing.
            TokenLines.codexCount("2026-10-30T09:01:30Z", total: (1000, 600, 50), last: (1000, 600, 50)),
            // No last_token_usage: the difference between the two totals.
            TokenLines.codexCount("2026-10-30T09:02:00Z", total: (1800, 1300, 90)),
        ], cli: .codex)
        #expect(log.rows.map(\.model) == ["gpt-6-astra"])
        #expect(total(log) == TokenCounts(input: 500, cacheRead: 1300, output: 90))
        #expect(log.project == "beta-api")
        #expect(log.session == LogFiles.baseName(URL(fileURLWithPath: "rollout-2026-10-30T09-00-00-\(TokenLines.rolloutId).jsonl")))
    }

    @Test("a sidechain message is counted with its session")
    func sidechain() throws {
        let h = try TempHome()
        let log = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claude("2026-10-30T09:15:00Z", id: "msg_1", K(input: 10, output: 20)),
            TokenLines.claude("2026-10-30T09:16:00Z", model: "claude-haiku-4-5", id: "msg_side", K(input: 5, output: 7), sidechain: true),
        ], cli: .claude)
        #expect(log.session == "s1")
        #expect(log.rows.map(\.model) == ["claude-haiku-4-5", "claude-opus-5-5"])
        #expect(total(log) == TokenCounts(input: 15, output: 27))
    }

    @Test("a log that names no model is unknown, and a model with no price keeps its logged name")
    func unknownModel() throws {
        let h = try TempHome()
        let unnamed = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claude("2026-10-30T09:15:00Z", model: nil, id: "msg_1", K(input: 1, output: 1)),
        ], cli: .claude)
        #expect(unnamed.rows.map(\.model) == ["unknown"])
        let odd = try fold(h, ".claude/projects/-work-alpha/s2.jsonl", [
            TokenLines.claude("2026-10-30T09:15:00Z", model: "claude-zeta-9", id: "msg_1", K(input: 1, output: 1)),
            // A synthetic message keeps the model before it.
            TokenLines.claude("2026-10-30T09:16:00Z", model: "<synthetic>", id: "msg_2", K(output: 3)),
        ], cli: .claude)
        #expect(odd.rows.map(\.model) == ["claude-zeta-9"])
        #expect(total(odd).output == 4)
        #expect(Pricing.price(for: "claude-zeta-9") == nil)
    }

    @Test("a line with no timestamp takes the hour of the last one, or the first one after it, or the log's time")
    func missingTimestamp() throws {
        let h = try TempHome()
        let log = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claude(nil, id: "msg_0", K(input: 1)),
            TokenLines.claude("2026-10-30T09:15:00Z", id: "msg_1", K(input: 10)),
            TokenLines.claude(nil, id: "msg_2", K(input: 100)),
            TokenLines.claude("2026-10-30T11:05:00Z", id: "msg_3", K(input: 1000)),
        ], cli: .claude)
        #expect(log.rows.map(\.hour) == [TokenLines.hour("2026-10-30T09:00:00Z"), TokenLines.hour("2026-10-30T11:00:00Z")])
        #expect(log.rows.map(\.counts.input) == [111, 1000])

        let fallbackMs = 1_790_000_000_000.0
        let none = try fold(h, ".claude/projects/-work-alpha/s2.jsonl", [TokenLines.claude(nil, id: "msg_0", K(input: 5))], cli: .claude, fallbackMs: fallbackMs)
        #expect(none.rows.map(\.hour) == [TokenFold.hour(ofMs: fallbackMs)])
    }

    @Test("rows are whole UTC hours")
    func utcHours() throws {
        let h = try TempHome()
        let log = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claude("2026-10-30T13:59:59.999Z", id: "msg_1", K(output: 1)),
            TokenLines.claude("2026-10-30T14:00:00.000Z", id: "msg_2", K(output: 2)),
        ], cli: .claude)
        #expect(log.rows.map(\.hour) == [TokenLines.hour("2026-10-30T13:00:00Z"), TokenLines.hour("2026-10-30T14:00:00Z")])
    }

    @Test("a .jsonl.zst rollout folds like a plain one")
    func compressed() throws {
        let h = try TempHome()
        let lines = [
            TokenLines.codexTurn("2026-10-01T08:00:00Z", model: "gpt-6-luna", cwd: h.url("work/beta-api").path),
            TokenLines.codexCount("2026-10-01T08:01:00Z", total: (400, 100, 20), last: (400, 100, 20)),
        ]
        let url = try h.write(".codex/sessions/2026/10/01/rollout-x.jsonl.zst", zstdRawFrame(Data((lines.joined(separator: "\n") + "\n").utf8)))
        let log = try #require(TokenFold.read(url, cli: .codex, fallbackMs: 0, maxLineBytes: UsageScanner.maxLineBytes))
        #expect(total(log) == TokenCounts(input: 300, cacheRead: 100, output: 20))
        #expect(log.session == "rollout-x")
        #expect(TokenFold.read(h.url(".codex/sessions/missing.jsonl"), cli: .codex, fallbackMs: 0, maxLineBytes: 1024) == nil)
    }

    @Test("a subagent log belongs to its parent session, and a worktree slug is never the project")
    func subagentAndWorktree() throws {
        let h = try TempHome()
        let worktree = h.url("work/alpha-app/.claude/worktrees/brave-fox").path
        let log = try fold(h, ".claude/projects/-work-alpha/s1/subagents/agent-a1.jsonl", [
            TokenLines.claude("2026-10-30T09:15:00Z", model: "claude-haiku-4-5", id: "msg_1", K(input: 2, output: 3), cwd: worktree),
        ], cli: .claude)
        #expect(log.session == "s1")
        #expect(log.project == "alpha-app")
    }

    @Test("the fold keeps no text from the log: only hours, model names, a project name and counts")
    func noLogText() throws {
        let h = try TempHome()
        let log = try fold(h, ".claude/projects/-work-alpha/s1.jsonl", [
            TokenLines.claudeUser("2026-10-30T09:14:00Z", text: "secret prompt words", cwd: h.url("work/alpha-app").path),
            TokenLines.claude("2026-10-30T09:15:00Z", id: "msg_1", K(input: 1, output: 1), cwd: h.url("work/alpha-app").path),
        ], cli: .claude)
        let encoded = String(decoding: try JSONEncoder().encode(log), as: UTF8.self)
        #expect(!encoded.contains("secret") && !encoded.contains("Done."))
        #expect(log.project == "alpha-app")
    }
}
