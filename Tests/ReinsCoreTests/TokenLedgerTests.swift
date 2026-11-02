import Foundation
import Testing
@testable import ReinsCore

// The token ledger against a TempHome (AGENTS.md S-R1). AC9: deleting a counted log and rescanning leaves every past day unchanged.

private typealias K = TokenLines.Kinds

private let claudeLog = ".claude/projects/-work-alpha/s1.jsonl"
private let codexLog = ".codex/sessions/2026/10/20/rollout-2026-10-20T08-00-00-\(TokenLines.rolloutId).jsonl"

private func claudeLines(_ h: TempHome) -> [String] {
    let cwd = h.url("work/alpha-app").path
    return [
        TokenLines.claude("2026-10-19T22:10:00Z", id: "msg_1", K(input: 10, output: 200, cacheWrite: 3000, cacheRead: 90_000), cwd: cwd),
        TokenLines.claude("2026-10-20T09:00:00Z", model: "claude-sonnet-5-5", id: "msg_2", K(input: 5, output: 80, cacheRead: 40_000), cwd: cwd),
    ]
}

private func codexLines(_ h: TempHome) -> [String] {
    [
        TokenLines.codexMeta("2026-10-20T08:00:00Z", id: TokenLines.rolloutId, cwd: h.url("work/beta-api").path),
        TokenLines.codexTurn("2026-10-20T08:00:01Z", model: "gpt-6-astra"),
        TokenLines.codexCount("2026-10-20T08:05:00Z", total: (5000, 4000, 300), last: (5000, 4000, 300)),
    ]
}

private func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

private func scanner(_ h: TempHome, version: Int = TokenLedger.scanVersion) throws -> TokenLedgerScanner {
    TokenLedgerScanner(roots: try Roots.resolve(env: h.env), scanVersion: version)
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UsageProgress] = []
    func add(_ value: UsageProgress) { lock.lock(); values.append(value); lock.unlock() }
    var all: [UsageProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

@Suite("Token ledger")
struct TokenLedgerTests {
    @Test("AC9: deleting a counted log and rescanning leaves every past day unchanged, also after a restart")
    func deletedLogKeepsHistory() async throws {
        let h = try TempHome()
        try h.write(claudeLog, text(claudeLines(h)))
        try h.write(codexLog, text(codexLines(h)))
        let first = try await scanner(h).scan()
        #expect(first.files == 2 && first.unreadable == 0 && first.notSaved == nil)
        #expect(first.ledger.entries.count == 3)

        try FileManager.default.removeItem(at: h.url(claudeLog))
        let again = try await scanner(h).scan()
        #expect(again.files == 1)
        #expect(again.ledger == first.ledger)

        // A new scanner reads the history back from disk, with the log still gone.
        let restarted = try await scanner(h).scan()
        #expect(restarted.ledger == first.ledger)
        let claude = try #require(restarted.ledger.files["claude/-work-alpha/s1"])
        #expect(claude.log.project == "alpha-app")
        #expect(claude.log.rows.map(\.hour) == [TokenLines.hour("2026-10-19T22:00:00Z"), TokenLines.hour("2026-10-20T09:00:00Z")])
    }

    @Test("a log that grows adds to its hours; one rewritten smaller never lowers them")
    func changedLog() async throws {
        let h = try TempHome()
        let lines = claudeLines(h)
        try h.write(claudeLog, text([lines[0]]))
        let small = try await scanner(h).scan()
        try h.write(claudeLog, text(lines))
        let grown = try await scanner(h).scan()
        let grownRows = try #require(grown.ledger.files["claude/-work-alpha/s1"]).log.rows
        #expect(grownRows.count == 2)
        #expect(grownRows.first == small.ledger.files["claude/-work-alpha/s1"]?.log.rows.first)

        // Same message, smaller numbers, in a shorter file: the counted hours stay as they were.
        try h.write(claudeLog, text([TokenLines.claude("2026-10-19T22:10:00Z", id: "msg_1", K(input: 1, output: 2))]))
        let rewritten = try await scanner(h).scan()
        #expect(rewritten.ledger.files["claude/-work-alpha/s1"]?.log.rows == grownRows)
    }

    @Test("a new scan version refolds the logs still present and keeps the rows of logs that are gone")
    func scanVersion() async throws {
        let h = try TempHome()
        try h.write(claudeLog, text(claudeLines(h)))
        try h.write(codexLog, text(codexLines(h)))
        let old = try await scanner(h, version: 0).scan()
        // Doctor the present log's entry, so a refold is visible.
        var doctored = old.ledger
        doctored.files["claude/-work-alpha/s1"]?.log.rows = [TokenRow(hour: 1, model: "made-up", counts: TokenCounts(input: 1))]
        try TokenLedgerStore.save(doctored, try Roots.resolve(env: h.env))
        try FileManager.default.removeItem(at: h.url(codexLog))

        let next = try await scanner(h, version: 7).scan()
        let claude = try #require(next.ledger.files["claude/-work-alpha/s1"])
        #expect(claude.v == 7)
        #expect(claude.log.rows == old.ledger.files["claude/-work-alpha/s1"]?.log.rows)
        let codexKey = try #require(old.ledger.files.keys.first { $0.hasPrefix("codex/") })
        #expect(next.ledger.files[codexKey] == old.ledger.files[codexKey])
        #expect(next.ledger.files[codexKey]?.v == 0)
    }

    @Test("a rollout Codex compresses to .jsonl.zst keeps its entry and is not counted twice")
    func compressedRollout() async throws {
        let h = try TempHome()
        try h.write(codexLog, text(codexLines(h)))
        let plain = try await scanner(h).scan()
        try h.write(codexLog + ".zst", zstdRawFrame(Data(text(codexLines(h)).utf8)))
        try FileManager.default.removeItem(at: h.url(codexLog))
        let compressed = try await scanner(h).scan()
        #expect(compressed.ledger.files.count == 1)
        #expect(compressed.ledger.files.values.first?.log.rows == plain.ledger.files.values.first?.log.rows)
    }

    @Test("a corrupt ledger is moved aside and reported, never silently replaced")
    func corruptLedger() async throws {
        let h = try TempHome()
        try h.write(claudeLog, text(claudeLines(h)))
        let garbage = Data("{\"format\":1,\"files\":{\"claude/x\":{\"stamp\":".utf8)
        try h.write(".reins/token-ledger.json", garbage)
        let result = try await scanner(h).scan(now: Date(timeIntervalSince1970: 1_790_000_000))
        let moved = try #require(result.movedAside)
        #expect(URL(fileURLWithPath: moved).lastPathComponent == "token-ledger.unreadable-20260921T141320Z.json")
        #expect(FileManager.default.contents(atPath: moved) == garbage)
        #expect(result.notSaved == nil)
        #expect(result.ledger.files.count == 1)
        let saved = try JSONDecoder().decode(TokenLedger.self, from: try Data(contentsOf: h.url(".reins/token-ledger.json")))
        #expect(saved == result.ledger)
    }

    @Test("a ledger of another format is moved aside, not read as empty and not overwritten")
    func otherFormat() async throws {
        let h = try TempHome()
        let future = Data("{\"format\":99,\"files\":{}}".utf8)
        try h.write(".reins/token-ledger.json", future)
        let result = try await scanner(h).scan()
        let moved = try #require(result.movedAside)
        #expect(FileManager.default.contents(atPath: moved) == future)
    }

    @Test("a ledger that cannot be opened is left alone and the scan says it was not saved")
    func unreadableLedger() async throws {
        let h = try TempHome()
        try h.write(claudeLog, text(claudeLines(h)))
        // A folder where the file should be: it cannot be opened as a file, and it must survive the scan.
        try FileManager.default.createDirectory(at: h.url(".reins/token-ledger.json/keep"), withIntermediateDirectories: true)
        let result = try await scanner(h).scan()
        #expect(result.notSaved != nil)
        #expect(result.movedAside == nil)
        #expect(result.ledger.files.count == 1)
        #expect(InventoryFileIO.isDirectory(h.url(".reins/token-ledger.json/keep")))
    }

    @Test("the ledger file is mode 0600 and holds names, dates and numbers only")
    func modeAndContent() async throws {
        let h = try TempHome()
        try h.write(claudeLog, text([TokenLines.claudeUser("2026-10-19T22:00:00Z", text: "private words in a prompt")] + claudeLines(h)))
        _ = try await scanner(h).scan()
        let path = h.url(".reins/token-ledger.json").path
        let mode = try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber).intValue
        #expect(mode & 0o777 == 0o600)
        let saved = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        #expect(!saved.contains("private words") && !saved.contains("Done.") && !saved.contains(h.root.path))
    }

    @Test("REINS_TEST=1 refuses a data root under the real home, so no test can write the real ledger")
    func realHomeGuard() throws {
        let h = try TempHome()
        let fakeReal = h.url("real-home").path
        var env = h.env
        env["REINS_HOME"] = fakeReal + "/.reins"
        #expect(throws: RootsError.underRealHome(label: "reins", path: fakeReal + "/.reins")) {
            try Roots.resolve(env: env, realHome: fakeReal)
        }
        let roots = try Roots.resolve(env: h.env, realHome: fakeReal)
        #expect(TokenLedgerStore.url(roots).deletingLastPathComponent() == roots.data)
    }

    @Test("progress is reported and ends at the number of logs; an unchanged log is not read again")
    func progressAndCache() async throws {
        let h = try TempHome()
        for n in 0..<25 { try h.write(".claude/projects/-work-alpha/s\(n).jsonl", text([TokenLines.claude("2026-10-20T09:00:00Z", id: "m\(n)", K(input: n + 1))])) }
        let log = ProgressLog()
        let first = try await scanner(h).scan { log.add($0) }
        #expect(log.all.map(\.done) == [20, 25])
        #expect(log.all.allSatisfy { $0.total == 25 })
        #expect(first.ledger.files.count == 25)
        // An unreadable log keeps its earlier rows: a broken .zst in place of one log.
        let entry = try #require(first.ledger.files["claude/-work-alpha/s3"])
        try FileManager.default.removeItem(at: h.url(".claude/projects/-work-alpha/s3.jsonl"))
        try h.write(".claude/projects/-work-alpha/s3.jsonl.zst", "not zstd")
        let next = try await scanner(h).scan()
        #expect(next.unreadable == 1)
        #expect(next.ledger.files["claude/-work-alpha/s3"] == entry)
    }
}
