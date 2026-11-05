import Foundation
import Testing
@testable import ReinsCore

@Suite("Limits status line")
struct LimitsStatuslineTests {
    private let now = Date(timeIntervalSince1970: 1_793_900_000)
    private let reset = 1_794_000_000

    private func account(_ home: TempHome, name: String = "synthetic-account") throws {
        try home.write(".claude/.claude.json", """
        {"oauthAccount":{"accountUuid":"\(name)","organizationUuid":"synthetic-org"},
         "cachedUsageUtilization":{"fetchedAtMs":1793800000000,"utilization":{"limits":[
         {"kind":"weekly_all","group":"weekly","percent":62,"resets_at":"2026-11-06T16:00:00Z"}]}}}
        """)
    }

    private func input(_ used: Int, session: String = "test-session", reset: Int? = nil) -> Data {
        Data("""
        {"session_id":"\(session)","secret":"must-not-persist","transcript_path":"private",
        "rate_limits":{"seven_day":{"used_percentage":\(used),"resets_at":\(reset ?? self.reset),"extra":"drop"}}}
        """.utf8)
    }

    @Test("regression: status line 76% used supersedes the old 62% cache")
    func newerSnapshot() throws {
        let home = try TempHome()
        try account(home)
        try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now)
        let result = Limits.read(try home.roots, now: now)[0]
        #expect(result.source == .claudeStatusline)
        guard case .measured(let at, let windows) = result.state else { Issue.record("No snapshot"); return }
        #expect(at == now)
        #expect(windows.map(\.usedPercent) == [76])
        #expect(windows.map(\.id) == ["weekly_all"])
        #expect(windows.map(\.minutes) == [10080])
        let file = try #require(LimitsClaudeStatusline.files(try home.roots).first)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(!saved.contains("must-not-persist"))
        #expect(!saved.contains("transcript_path"))
        #expect(!saved.contains("synthetic-account"))
        #expect(!saved.contains("extra"))
        #expect(try home.mode(of: file) == 0o600)
    }

    @Test("idle sessions cannot move usage backwards; a new reset window can")
    func idleSessions() throws {
        let home = try TempHome()
        try account(home)
        try LimitsClaudeStatusline.capture(input(76, session: "active"), roots: home.roots, now: now)
        try LimitsClaudeStatusline.capture(input(62, session: "idle"), roots: home.roots, now: now.addingTimeInterval(1))
        guard case .measured(_, let windows) = LimitsClaudeStatusline.read(try home.roots, now: now.addingTimeInterval(2)).state else {
            Issue.record("No snapshot"); return
        }
        #expect(windows.map(\.usedPercent) == [76])
        try LimitsClaudeStatusline.capture(input(1, session: "new-window", reset: reset + 604800), roots: home.roots, now: now.addingTimeInterval(3))
        guard case .measured(_, let next) = LimitsClaudeStatusline.read(try home.roots, now: now.addingTimeInterval(4)).state else {
            Issue.record("No new window"); return
        }
        #expect(next.map(\.usedPercent) == [1])
    }

    @Test("missing quota, invalid input and a partial malformed reading cannot overwrite a snapshot")
    func invalidInput() throws {
        let home = try TempHome()
        try account(home)
        try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now)
        let file = try #require(LimitsClaudeStatusline.files(try home.roots).first)
        let before = try Data(contentsOf: file)
        try LimitsClaudeStatusline.capture(Data(#"{"session_id":"test-session"}"#.utf8), roots: home.roots)
        for invalid in [input(101), input(-1), input(76, session: "../escape"), input(76, reset: 0),
                        Data(repeating: 0, count: LimitsClaudeStatusline.maxInputBytes + 1),
                        Data(#"{"session_id":"test-session","rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":76,"resets_at":1794000000}}}"#.utf8)] {
            #expect(throws: (any Error).self) { try LimitsClaudeStatusline.capture(invalid, roots: home.roots) }
        }
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("a later partial payload keeps both recent windows, fractional usage and exact resets")
    func independentWindows() throws {
        let home = try TempHome()
        try account(home)
        let payload = Data("""
        {"session_id":"both","rate_limits":{
          "five_hour":{"used_percentage":95.5,"resets_at":\(reset - 1000)},
          "seven_day":{"used_percentage":76.25,"resets_at":\(reset)}}}
        """.utf8)
        try LimitsClaudeStatusline.capture(payload, roots: home.roots, now: now)
        try LimitsClaudeStatusline.capture(input(62, session: "partial"), roots: home.roots, now: now.addingTimeInterval(1))
        guard case .measured(_, let windows) = Limits.read(try home.roots, now: now.addingTimeInterval(2))[0].state else {
            Issue.record("No snapshot"); return
        }
        #expect(windows.map(\.id) == ["five_hour", "weekly_all"])
        #expect(windows.map(\.minutes) == [300, 10080])
        #expect(windows.map(\.usedPercent) == [95.5, 76.25])
        #expect(windows.map(\.resetsAt) == [Date(timeIntervalSince1970: Double(reset - 1000)), Date(timeIntervalSince1970: Double(reset))])
    }

    @Test("a newer usage-cache fetch supersedes an older status-line snapshot")
    func newerCache() throws {
        let home = try TempHome()
        try account(home)
        try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now)
        let file = home.url(".claude/.claude.json")
        let cacheTime = now.addingTimeInterval(10)
        let updated = try OrderedJSON(data: Data(contentsOf: file)).setting(["cachedUsageUtilization", "fetchedAtMs"],
            to: .number(String(cacheTime.timeIntervalSince1970 * 1000)))
        try home.write(".claude/.claude.json", updated.data)
        let result = Limits.read(try home.roots, now: now.addingTimeInterval(20))[0]
        #expect(result.source == .claudeCache)
        guard case .measured(let at, let windows) = result.state else { Issue.record("No cache"); return }
        #expect(at == cacheTime)
        #expect(windows.map(\.usedPercent) == [62])
    }

    @Test("managed subdirectory links cannot redirect collector or installer writes")
    func managedDirectories() throws {
        let home = try TempHome()
        let outside = try TempHome()
        try account(home)
        try home.write(".claude/settings.json", "{}")
        let binary = try home.write("fake-binary", "synthetic")
        try FileManager.default.createDirectory(at: home.reins, withIntermediateDirectories: true)
        let sentinel = try outside.write("sentinel.json", "keep")
        for name in ["bin", "claude-limits"] {
            try FileManager.default.createSymbolicLink(at: home.reins.appendingPathComponent(name), withDestinationURL: outside.root)
        }
        #expect(throws: (any Error).self) { try StatuslineSetup.install(home.roots, binary: binary) }
        #expect(throws: (any Error).self) { try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now) }
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path) == ["sentinel.json"])
        #expect(try String(contentsOf: home.claude.appendingPathComponent("settings.json"), encoding: .utf8) == "{}")
    }

    @Test("account switches reject previous snapshots and prevent an old session relabeling its quota")
    func accountSwitch() throws {
        let home = try TempHome()
        try account(home)
        try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now)
        try account(home, name: "another-account")
        try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now.addingTimeInterval(1))
        #expect(LimitsClaudeStatusline.read(try home.roots, now: now.addingTimeInterval(2)).source == .claudeCache)
        try LimitsClaudeStatusline.capture(input(5, session: "new-login"), roots: home.roots, now: now.addingTimeInterval(3))
        #expect(LimitsClaudeStatusline.read(try home.roots, now: now.addingTimeInterval(4)).source == .claudeStatusline)
    }

    @Test("malformed, future and special-file snapshots fall back without blocking")
    func invalidFiles() throws {
        let home = try TempHome()
        try account(home)
        try home.write(".reins/claude-limits/invalid.json", "{bad")
        try home.write(".reins/claude-limits/large.json", Data(repeating: 32, count: 5000))
        let fifo = home.url(".reins/claude-limits/fifo.json")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        try LimitsClaudeStatusline.capture(input(76), roots: home.roots, now: now.addingTimeInterval(60))
        #expect(LimitsClaudeStatusline.read(try home.roots, now: now).source == .claudeCache)
    }

    @Test("setup preserves the original command and unrelated bytes; repeated setup is a no-op and Undo restores")
    func setup() throws {
        let home = try TempHome()
        let original = """
        { "permissions": {"allow": ["Read"]}, "statusLine": {"type":"command","command":"printf 'hello'","padding":2}, "other":true }
        """
        let settings = try home.write(".claude/settings.json", original)
        let binary = try home.write("fake-binary", "synthetic executable")
        let roots = try home.roots
        let entry = try #require(try StatuslineSetup.install(roots, binary: binary))
        let changed = try String(contentsOf: settings, encoding: .utf8)
        let parsed = try OrderedJSON(text: changed)
        #expect(changed.contains(#""permissions": {"allow": ["Read"]}"#))
        #expect(parsed.root["statusLine"]?["padding"] == 2)
        #expect(parsed.root["statusLine"]?["command"]?.stringValue?.hasSuffix(StatuslineSetup.quote("printf 'hello'")) == true)
        #expect(try StatuslineSetup.install(roots, binary: binary) == nil)
        _ = try Journal.undo(roots, id: entry.id)
        #expect(try String(contentsOf: settings, encoding: .utf8) == original)
    }
}
