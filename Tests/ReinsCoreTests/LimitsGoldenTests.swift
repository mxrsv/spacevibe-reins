import Foundation
import Testing
@testable import ReinsCore

/// Swift `Limits.read` recorded into core/testdata/fixtures/golden/limits.json (AC10, C1). The Go core replays the same
/// cases: it recreates each case's input files in a temporary home, reads with `now`, and must produce the same bytes.
/// Unlike the Node goldens this one is written by Swift, through `CanonicalJSON`, and compared as bytes.
/// `SPACEVIBE_RECORD_GOLDEN=1` rewrites the file; any other run compares with it.
@Suite("Limits golden")
struct LimitsGoldenTests {
    static let expectedCases = 27
    static let recordVariable = "SPACEVIBE_RECORD_GOLDEN"
    static let goldenPath = "golden/limits.json"

    @Test("every Limits scenario reads the same as the committed golden, byte for byte")
    func golden() throws {
        let cases = try LimitsGoldenCase.all()
        #expect(cases.count > 0 && cases.count == Self.expectedCases, "case count \(cases.count)")
        #expect(Set(cases.map(\.name)).count == cases.count, "case names are unique")
        let document = try CanonicalJSON.object([
            "format": "limits-golden/1",
            "environment": [
                "HOME": "<home>", "CLAUDE_CONFIG_DIR": "<home>/.claude (unset when unsetClaudeConfigDir)",
                "CODEX_HOME": "<home>/.codex", "SPACEVIBE_HOME": "<home>/.spacevibe", "SPACEVIBE_TEST": "1",
            ],
            "tokens": [
                "$ACCOUNT_KEY(<accountUuid>,<organizationUuid>)":
                    "in a file text: sha256 hex of \"<claude root>\\n<accountUuid>\\n<organizationUuid>\", the key the status line snapshots carry",
            ],
            "cases": .array(cases.map { try $0.record() }),
        ]).text()

        try Self.assertNoLeak(document)
        let states = Set(document.components(separatedBy: "\"state\": \"").dropFirst().compactMap { $0.split(separator: "\"").first.map(String.init) })
        #expect(states == ["measured", "notRecorded", "unreadable", "notMeasurable", "notInstalled"], "cases cover \(states.sorted())")
        #expect(document.contains("\"source\": \"claudeStatusline\"") && document.contains("\"source\": \"claudeCache\""))
        #expect(document.contains("\"current\": false"))

        let target = Fixtures.url(Self.goldenPath)
        if ProcessInfo.processInfo.environment[Self.recordVariable] == "1" {
            try Data(document.utf8).write(to: target, options: .atomic)
            return
        }
        let committed = try String(contentsOf: target, encoding: .utf8)
        #expect(document == committed, Comment(rawValue: Self.firstDifference(document, committed)))
    }

    @Test("the status line snapshot the cases write by hand is what the collector writes")
    func snapshotShapeMatchesCapture() throws {
        let home = try TempHome()
        try home.write(".claude/.claude.json", LimitsGoldenCase.accountState("synthetic-account"))
        let input = Data(#"{"session_id":"s1","rate_limits":{"seven_day":{"used_percentage":76,"resets_at":1794000000}}}"#.utf8)
        let now = Date(timeIntervalSince1970: LimitsGoldenCase.defaultNow)
        try LimitsClaudeStatusline.capture(input, roots: home.roots, now: now)
        let written = try Data(contentsOf: try #require(LimitsClaudeStatusline.files(try home.roots).first))

        let byHand = LimitsGoldenCase.snapshot(session: "s1", account: "synthetic-account", observed: LimitsGoldenCase.defaultNow,
                                               windows: [("seven_day", "76", 1_794_000_000)])
        let handText = try #require(byHand.text)
        let key = try #require(LimitsClaudeStatusline.accountKey(try home.roots))
        let resolved = handText.replacingOccurrences(of: "$ACCOUNT_KEY(synthetic-account,synthetic-org)", with: key)
        let a = try JSONSerialization.jsonObject(with: written) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: Data(resolved.utf8)) as? NSDictionary
        #expect(a != nil && a == b)
    }

    /// The golden is committed, so it must not carry this machine: no temp folder, real home or user name.
    private static func assertNoLeak(_ text: String) throws {
        let forbidden = [NSTemporaryDirectory(), NSHomeDirectory(), "reins-test-", "/private/var", "/Users/", NSUserName()]
        for item in forbidden where item.count > 3 {
            #expect(!text.contains(item), Comment(rawValue: "limits golden mentions \(item)"))
        }
    }

    /// The first line that differs, with its number, to look up in limits.json.
    static func firstDifference(_ actual: String, _ expected: String) -> String {
        let a = actual.components(separatedBy: "\n"), e = expected.components(separatedBy: "\n")
        for index in 0..<max(a.count, e.count) where index >= a.count || index >= e.count || a[index] != e[index] {
            return "first difference at line \(index + 1)\n  actual:   \(index < a.count ? a[index] : "<end>")\n  expected: \(index < e.count ? e[index] : "<end>")"
        }
        return "no difference"
    }
}
