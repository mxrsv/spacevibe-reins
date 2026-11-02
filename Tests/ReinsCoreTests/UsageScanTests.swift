import Foundation
import Testing
@testable import ReinsCore

// Hook records are generated here in the shape Claude Code writes them; nothing is copied from real logs.
// Temp HOME only: the roots come from TempHome (or the fixture tree with a temp data folder), and REINS_TEST=1 turns on the guard.

private func scanner(_ home: TempHome) throws -> UsageScanner { UsageScanner(roots: try Roots.resolve(env: home.env)) }

private func attach(_ day: String, _ attachment: [String: Any]) throws -> String {
    let record: [String: Any] = ["type": "attachment", "timestamp": "\(day)T10:00:00Z", "attachment": attachment]
    return String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self)
}

private func codexCall(_ day: String, _ skill: String) -> String {
    "{\"timestamp\":\"\(day)T10:00:00Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"arguments\":\"cat skills/\(skill)/SKILL.md\"}}\n"
}

/// A zstd frame made of one raw (uncompressed) block: valid zstd, no compressor needed. Single segment, 4-byte content size.
private func zstdRawFrame(_ payload: Data) -> Data {
    precondition(payload.count < 128 * 1024)
    var out = Data([0x28, 0xB5, 0x2F, 0xFD, 0xA0])
    withUnsafeBytes(of: UInt32(payload.count).littleEndian) { out.append(contentsOf: $0) }
    let header = UInt32(payload.count) << 3 | 1  // last block, type raw
    out.append(contentsOf: [UInt8(header & 0xFF), UInt8((header >> 8) & 0xFF), UInt8((header >> 16) & 0xFF)])
    out.append(payload)
    return out
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UsageProgress] = []
    func add(_ value: UsageProgress) { lock.lock(); values.append(value); lock.unlock() }
    var all: [UsageProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

@Suite("UsageScan")
struct UsageScanTests {
    @Test("hook errors are counted for every error record shape, per event plus command")
    func hookErrors() async throws {
        let h = try TempHome()
        let lines = try [
            attach("2026-10-01", ["type": "hook_success", "hookEvent": "Stop", "hookName": "Stop", "command": "cmd-a", "durationMs": 10, "exitCode": 0, "stdout": "", "stderr": ""]),
            attach("2026-10-02", ["type": "hook_non_blocking_error", "hookEvent": "Stop", "hookName": "Stop", "command": "cmd-a", "durationMs": 20, "exitCode": 1, "stdout": "", "stderr": "boom"]),
            attach("2026-10-03", ["type": "hook_success", "hookEvent": "Stop", "hookName": "Stop", "command": "cmd-a", "durationMs": 30, "exitCode": 2]),
            // The blocking error carries the command inside blockingError, not at the top level.
            attach("2026-10-04", ["type": "hook_blocking_error", "hookEvent": "PostToolUse", "hookName": "PostToolUse:Edit", "toolUseID": "t1", "blockingError": ["blockingError": "denied", "command": "cmd-b"]]),
            attach("2026-10-05", ["type": "hook_blocking_error", "hookEvent": "PostToolUse", "hookName": "PostToolUse:Edit", "toolUseID": "t2", "blockingError": ["blockingError": "denied", "command": "cmd-b"]]),
            // Same command under another event is another hook.
            attach("2026-10-05", ["type": "hook_success", "hookEvent": "PreToolUse", "command": "cmd-b", "durationMs": 5, "exitCode": 0]),
            // Quoted text and a record without a command are not runs; neither is a boolean duration a duration.
            "{\"type\":\"user\",\"timestamp\":\"2026-10-05T10:00:00Z\",\"message\":{\"content\":\"hook_blocking_error \\\"command\\\":\\\"cmd-a\\\"\"}}",
            attach("2026-10-05", ["type": "hook_additional_context", "hookEvent": "Stop", "content": [String: Any]()]),
            "{\"type\":\"attachment\",\"timestamp\":\"2026-10-06T10:00:00Z\",\"attachment\":{\"type\":\"hook_success\",\"hookEvent\":\"Stop\",\"command\":\"cmd-c\",\"durationMs\":true,\"exitCode\":false}}",
        ]
        try h.write(".claude/projects/p/s1.jsonl", lines.joined(separator: "\n"))
        let result = try await scanner(h).scan()
        func hook(_ event: String, _ command: String) -> HookTotals? { result.totals.claude.hook[Inventory.hookHash(event: event, command: command)] }
        #expect(hook("Stop", "cmd-a") == HookTotals(runs: 3, ms: 60, timed: 3, errors: 2, last: "2026-10-03"))
        #expect(hook("PostToolUse", "cmd-b")?.runs == 2 && hook("PostToolUse", "cmd-b")?.errors == 2)
        #expect(hook("PreToolUse", "cmd-b")?.runs == 1 && hook("PreToolUse", "cmd-b")?.errors == 0)
        #expect(hook("Stop", "cmd-c") == HookTotals(runs: 1, ms: 0, timed: 0, errors: 0, last: "2026-10-06"))
        #expect(result.totals.claude.hook.count == 4)
    }

    @Test("skills, slash commands and subagents count sessions, not mentions; plugin prefixes are dropped")
    func skillsAndAgents() async throws {
        let h = try TempHome()
        func skillCall(_ day: String, _ name: String) -> String { "{\"type\":\"assistant\",\"timestamp\":\"\(day)T10:00:00Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Skill\",\"input\":{\"skill\":\"\(name)\"}}]}}" }
        func slash(_ day: String, _ name: String) -> String { "{\"type\":\"user\",\"timestamp\":\"\(day)T10:00:00Z\",\"message\":{\"content\":\"<command-name>/\(name)</command-name>\"}}" }
        func agent(_ day: String, _ name: String) -> String { "{\"type\":\"assistant\",\"timestamp\":\"\(day)T10:00:00Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Task\",\"input\":{\"subagent_type\":\"\(name)\"}}]}}" }
        try h.write(".claude/projects/p/s1.jsonl", [skillCall("2026-10-01", "acme:foo"), skillCall("2026-10-01", "foo"), slash("2026-10-02", "bar"), agent("2026-10-02", "rev")].joined(separator: "\n"))
        try h.write(".claude/projects/p/s2.jsonl", [skillCall("2026-10-04", "foo"), agent("2026-10-04", "rev")].joined(separator: "\n"))
        // A subagent log belongs to the session that spawned it.
        try h.write(".claude/projects/p/s2/subagents/agent-1.jsonl", skillCall("2026-10-05", "foo"))
        let result = try await scanner(h).scan()
        #expect(result.totals.claude.skill["foo"] == NameUsage(sessions: 2, days: ["2026-10-01", "2026-10-04", "2026-10-05"], last: "2026-10-05"))
        #expect(result.totals.claude.skill["bar"]?.sessions == 1)
        #expect(result.totals.claude.agent["rev"]?.sessions == 2)
        #expect(result.sessions == UsageSessions(claude: 2, codex: 0))
        #expect(result.files == 3)
    }

    @Test("the log window is reported per CLI; a cache entry from an older parser is scanned again")
    func windowAndCacheVersion() async throws {
        let h = try TempHome()
        try h.write(".claude/projects/p/s1.jsonl", try attach("2026-10-01", ["type": "hook_blocking_error", "hookEvent": "PostToolUse", "blockingError": ["command": "cmd-b"]]))
        let r = try Roots.resolve(env: h.env)
        let first = try await UsageScanner(roots: r).scan()
        #expect(first.windows.claude.files == 1 && first.windows.claude.oldest == "2026-10-01")
        #expect((first.windows.claude.newest ?? 0) > 0)
        #expect(first.windows.codex == LogWindow(files: 0, oldest: nil, newest: nil))

        // The cache lives under the REINS data root and carries the version.
        let cacheURL = UsageScanCache.url(r)
        #expect(cacheURL.path == h.reins.path + "/usage-cache.json")
        var cache = UsageScanCache.load(r)
        let entry = try #require(cache.values.first)
        #expect(entry.v == UsageScanner.scanVersion)

        // A cache entry of the right version and stamp is trusted (no reparse) ...
        var trusted = entry
        trusted.rec.hook = [:]
        cache[cache.keys.first!] = trusted
        UsageScanCache.save(cache, r)
        #expect(try await UsageScanner(roots: r).scan().totals.claude.hook.isEmpty)
        // ... and one written by an older parser is not.
        var old = entry
        old.v = UsageScanner.scanVersion - 1
        old.rec.hook = [:]
        cache[cache.keys.first!] = old
        UsageScanCache.save(cache, r)
        let again = try await UsageScanner(roots: r).scan()
        #expect(again.totals.claude.hook[Inventory.hookHash(event: "PostToolUse", command: "cmd-b")]?.errors == 1)
    }

    @Test("a corrupt cache file is an empty cache; the cache is private to the user")
    func corruptCache() async throws {
        let h = try TempHome()
        try h.write(".claude/projects/p/s1.jsonl", try attach("2026-10-01", ["type": "hook_success", "hookEvent": "Stop", "command": "c"]))
        try h.write(".reins/usage-cache.json", "{ truncated")
        let r = try Roots.resolve(env: h.env)
        let result = try await UsageScanner(roots: r).scan()
        #expect(result.totals.claude.hook.count == 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: UsageScanCache.url(r).path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test("compressed Codex rollouts count like plain ones, and a session in both forms counts once")
    func compressedRollouts() async throws {
        let h = try TempHome()
        let dir = ".codex/sessions/2026/03/01"
        try h.write("\(dir)/rollout-old.jsonl.zst", zstdRawFrame(Data(codexCall("2026-03-01", "old-skill").utf8)))
        try h.write("\(dir)/rollout-both.jsonl", codexCall("2026-03-02", "both-skill"))
        try h.write("\(dir)/rollout-both.jsonl.zst", zstdRawFrame(Data(codexCall("2026-03-02", "stale-skill").utf8)))
        try h.write("\(dir)/rollout-broken.jsonl.zst", "not zstd")
        let result = try await scanner(h).scan()
        #expect(result.totals.codex.skill["old-skill"] == NameUsage(sessions: 1, days: ["2026-03-01"], last: "2026-03-01"))
        #expect(result.totals.codex.skill["both-skill"]?.sessions == 1)
        #expect(result.totals.codex.skill["stale-skill"] == nil)
        #expect(result.sessions.codex == 2, "the broken file is skipped, the others still count")
        #expect(result.files == 3)
        #expect(result.windows.codex.oldest == "2026-03-01")
    }

    @Test("Codex agents and skills are read from tool calls only")
    func codexCalls() async throws {
        let h = try TempHome()
        let call = "{\"timestamp\":\"2026-10-01T10:00:00Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"arguments\":\"{\\\"agent_type\\\": \\\"explorer\\\"}\"}}\n"
        let chatter = "{\"timestamp\":\"2026-10-01T10:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"message\":\"please read skills/chat-only/SKILL.md and agent_type explorer\"}}\n"
        try h.write(".codex/sessions/2026/10/rollout-a.jsonl", call + chatter)
        let result = try await scanner(h).scan()
        #expect(result.totals.codex.agent["explorer"]?.sessions == 1)
        #expect(result.totals.codex.skill["chat-only"] == nil)
    }

    @Test("an unreadable log, an oversized line, an empty file and binary junk never crash the scan")
    func hostileLogs() async throws {
        let h = try TempHome()
        try h.write(".claude/projects/p/empty.jsonl", "")
        try h.write(".claude/projects/p/junk.jsonl", Data([0xFF, 0x00, 0xFE, 0x0A, 0x7B, 0x0A]))
        let denied = try h.write(".claude/projects/p/denied.jsonl", try attach("2026-10-01", ["type": "hook_success", "hookEvent": "Stop", "command": "c"]))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied.path) }
        let cap = 4096
        let huge = "{\"type\":\"user\",\"x\":\"" + String(repeating: "y", count: cap + 10) + "\"}\n"
        try h.write(".claude/projects/p/huge.jsonl", huge + (try attach("2026-10-02", ["type": "hook_success", "hookEvent": "Stop", "command": "after-huge"])))
        let result = try await UsageScanner(roots: try Roots.resolve(env: h.env), maxLineBytes: cap).scan()
        #expect(result.files == 4)
        #expect(result.totals.claude.hook[Inventory.hookHash(event: "Stop", command: "after-huge")]?.runs == 1)
    }

    @Test("progress is reported and ends at the file count; cancelling throws and writes no cache")
    func progressAndCancel() async throws {
        let h = try TempHome()
        for index in 0..<45 { try h.write(".claude/projects/p/s\(index).jsonl", "{}\n") }
        let r = try Roots.resolve(env: h.env)
        let log = ProgressLog()
        _ = try await UsageScanner(roots: r).scan { log.add($0) }
        let seen = log.all
        #expect(seen.last == UsageProgress(done: 45, total: 45))
        #expect(seen.count >= 3 && zip(seen, seen.dropFirst()).allSatisfy { $0.done <= $1.done })

        try FileManager.default.removeItem(at: UsageScanCache.url(r))
        // Cancelled before the first file is read, so the outcome does not depend on timing.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await UsageScanner(roots: r).scan()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: UsageScanCache.url(r).path))
    }

    @Test("a scan of the shared fixture tree equals usage.json from the Node core")
    func goldenParity() async throws {
        try FixtureHome.materialize()
        let temp = try TempHome()
        var env = FixtureHome.env
        env["REINS_HOME"] = temp.reins.path
        let r = try Roots.resolve(env: env)
        let cold = try await UsageScanner(roots: r).scan()
        let expected = try FixtureHome.golden("usage")
        let coldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cold))
        let diff = FixtureHome.firstDifference(FixtureHome.normalize(coldJSON), expected)
        #expect(diff == nil, "first difference: \(diff ?? "")")
        // The second scan reads the cache and gives the same answer.
        let warm = try await UsageScanner(roots: r).scan()
        #expect(warm == cold)
    }

    @Test("the scan never reads the real home: the roots it is given are the temp ones, and the guard refuses the real ones")
    func neverTouchesRealHome() throws {
        let real = Roots.realHomeDirectory()
        #expect(throws: RootsError.self) { try Roots.resolve(env: ["HOME": real, "REINS_TEST": "1"]) }
        let h = try TempHome()
        let r = try Roots.resolve(env: h.env)
        for url in [r.claude.logs, r.codex.logs, UsageScanCache.url(r)] { #expect(url.path.hasPrefix(h.root.path)) }
    }
}
