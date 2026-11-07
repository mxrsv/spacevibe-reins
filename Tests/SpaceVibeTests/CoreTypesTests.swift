import Foundation
import Testing
@testable import SpaceVibe

/// Where the committed core test data lives, and the JSON helpers both Core test files share.
enum CoreTestData {
    /// `<repo>/core/testdata`, found from this file so the tests run from any working directory.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("core/testdata", isDirectory: true)

    static func json(_ relative: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(relative)), options: [.fragmentsAllowed])
    }

    /// Decodes a JSON value into a DTO, encodes it again and returns the first difference from the original (nil when the
    /// two are equal): the check that key names, `null` versus omitted, and extra or missing members all match the wire.
    static func roundTripDifference<T: Codable>(_ original: Any, as type: T.Type) throws -> String? {
        let data = try JSONSerialization.data(withJSONObject: original, options: [.fragmentsAllowed])
        let decoded = try JSONDecoder().decode(T.self, from: data)
        let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded), options: [.fragmentsAllowed])
        return firstDifference(again, original)
    }

    static func firstDifference(_ actual: Any, _ expected: Any, path: String = "$") -> String? {
        switch (actual, expected) {
        case let (a as [String: Any], e as [String: Any]):
            for key in Set(a.keys).union(e.keys).sorted() {
                switch (a[key], e[key]) {
                case (nil, nil): continue
                case (nil, _): return "\(path).\(key) (missing after the round trip)"
                case (_, nil): return "\(path).\(key) (added by the round trip)"
                case let (av?, ev?): if let diff = firstDifference(av, ev, path: "\(path).\(key)") { return diff }
                }
            }
            return nil
        case let (a as [Any], e as [Any]):
            guard a.count == e.count else { return "\(path) (count \(a.count) vs \(e.count))" }
            for (index, pair) in zip(a, e).enumerated() {
                if let diff = firstDifference(pair.0, pair.1, path: "\(path)[\(index)]") { return diff }
            }
            return nil
        case (is NSNull, is NSNull): return nil
        case let (a as NSNumber, e as NSNumber): return a == e ? nil : "\(path) (\(a) vs \(e))"
        case let (a as String, e as String): return a == e ? nil : "\(path) (\"\(a)\" vs \"\(e)\")"
        default: return "\(path) (different kinds)"
        }
    }

    /// A transcript masks the members that follow the clock as `"$CLOCK"` (core/cmd/spacevibe/contract-normalize_test.go), which
    /// is not the type the wire has. This puts a value of the right type back: `true` for `current`, 0 for an age.
    static func unmaskingClock(_ value: Any, key: String = "") -> Any {
        switch value {
        case let text as String where text == "$CLOCK": return key == "current" ? true : 0
        case let object as [String: Any]: return object.reduce(into: [String: Any]()) { $0[$1.key] = unmaskingClock($1.value, key: $1.key) }
        case let array as [Any]: return array.map { unmaskingClock($0, key: key) }
        default: return value
        }
    }

    /// Every `core/testdata/rpc/*.jsonl` line as `(dir, json)`.
    static func transcriptLines() throws -> [(file: String, dir: String, json: [String: Any])] {
        // A line whose json is not an object (a batch, a parse-error probe) has no result or error to read.
        let folder = directory.appendingPathComponent("rpc", isDirectory: true)
        var out: [(String, String, [String: Any])] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasSuffix(".jsonl") }).sorted() {
            // Bytes, not text: a transcript may hold a line that is not valid UTF-8.
            let bytes = try Data(contentsOf: folder.appendingPathComponent(name))
            for line in bytes.split(separator: 0x0A) {
                // Not every line is a record: a probe of the parser may be raw bytes.
                guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let json = record["json"] as? [String: Any] else { continue }
                out.append((name, try #require(record["dir"] as? String), json))
            }
        }
        return out
    }
}

@Suite("Core DTOs")
struct CoreTypesTests {
    // MARK: Recorded transcripts

    @Test("every recorded initialize result decodes and encodes back to the same JSON")
    func transcriptInitialize() throws {
        var seen = 0
        for line in try CoreTestData.transcriptLines() where line.dir == "recv" {
            guard let result = line.json["result"] as? [String: Any], result["methods"] != nil else { continue }
            #expect(try CoreTestData.roundTripDifference(result, as: CoreInitializeResult.self) == nil, "\(line.file)")
            seen += 1
        }
        #expect(seen >= 10)
    }

    @Test("every recorded error decodes, and a -32000 carries the engine's status and message")
    func transcriptErrors() throws {
        var codes: Set<Int> = []
        for line in try CoreTestData.transcriptLines() where line.dir == "recv" {
            guard let error = line.json["error"] as? [String: Any] else { continue }
            #expect(try CoreTestData.roundTripDifference(error, as: CoreRPCError.self) == nil, "\(line.file)")
            let decoded = try JSONDecoder().decode(CoreRPCError.self, from: JSONSerialization.data(withJSONObject: error))
            codes.insert(decoded.code)
            if decoded.code == -32000 {
                let refusal = try #require(decoded.coreError, "\(line.file)")
                #expect([400, 403, 404, 409, 413, 500].contains(refusal.status), "\(line.file) status \(refusal.status)")
                #expect(refusal.message == decoded.message)
            }
            if decoded.code == -32001 { #expect(decoded.data?.protocolVersion == CoreProtocol.version) }
        }
        #expect(codes.isSuperset(of: [-32000, -32001, -32601, -32602]))
    }

    /// The result type of each method that has one. `initialize` and the errors have their own tests.
    static let resultTypes: [String: any Codable.Type] = [
        "inventory.read": CoreInventorySnapshot.self, "usage.scan": CoreUsageResult.self, "loadout.rows": CoreLoadoutRows.self,
        "activity.read": CoreActivityReport.self, "activity.subscribe": CoreActivityReport.self, "activity.stop": CoreStopResult.self,
        "loadout.copyToOther": CoreEntryResult.self, "loadout.removeItem": CoreEntryResult.self, "loadout.removeDeadHooks": CoreEntryResult.self,
        "journal.undo": CoreUndoResult.self, "journal.history": CoreJournalHistory.self,
        "rules.snapshot": CoreRulesSnapshot.self, "rules.preview": CoreCapabilityPreview.self, "rules.setCapability": CoreSetCapabilityResult.self,
        "rules.add": CoreEntryResult.self, "rules.remove": CoreEntryResult.self, "rules.changeVerdict": CoreEntryResult.self,
        "rules.check": CoreRuleCheck.self, "limits.read": CoreLimitsResult.self,
    ]

    private static func unmaskedParams(_ json: [String: Any]) throws -> Any {
        CoreTestData.unmaskingClock(try #require(json["params"]))
    }

    @Test("every recorded engine result and activity/report notification decodes and encodes back to the same JSON")
    func transcriptResults() throws {
        func difference<T: Codable>(_ value: Any, as _: T.Type) throws -> String? { try CoreTestData.roundTripDifference(value, as: T.self) }
        var covered: Set<String> = []
        var method: [String: String] = [:]
        var file = ""
        for line in try CoreTestData.transcriptLines() {
            if line.file != file { file = line.file; method = [:] }
            let key = "\(line.json["id"] ?? "")"
            if line.dir == "send", let name = line.json["method"] as? String { method[key] = name; continue }
            if line.dir == "recv", line.json["id"] == nil, line.json["method"] as? String == "activity/report" {
                #expect(try difference(Self.unmaskedParams(line.json), as: CoreActivityReport.self) == nil, "\(line.file) activity/report")
                covered.insert("activity/report")
                continue
            }
            if line.dir == "recv", line.json["id"] == nil, line.json["method"] as? String == "usage/progress" {
                // The notification adds the request id to the DTO's `done` and `total`.
                var params = try #require(line.json["params"] as? [String: Any])
                #expect(params.removeValue(forKey: "id") != nil)
                #expect(try difference(params, as: CoreUsageProgress.self) == nil, "\(line.file) usage/progress")
                covered.insert("usage/progress")
                continue
            }
            guard line.dir == "recv", let result = line.json["result"].map({ CoreTestData.unmaskingClock($0) }), let name = method[key], let type = Self.resultTypes[name] else { continue }
            func check<T: Codable>(_: T.Type) throws { #expect(try difference(result, as: T.self) == nil, "\(line.file) \(name)") }
            try check(type)
            covered.insert(name)
        }
        // Whatever the transcripts hold today must decode; the table is the list of methods that may appear.
        print("transcript results decoded for: \(covered.sorted())")
    }

    @Test("the handshake transcript names the identity the Swift constants hold")
    func identityMatchesTheConstants() throws {
        let line = try #require(try CoreTestData.transcriptLines().first { $0.file == "handshake_ok.jsonl" && $0.dir == "recv" })
        let recorded = try JSONDecoder().decode(CoreInitializeResult.self, from: JSONSerialization.data(withJSONObject: try #require(line.json["result"])))
        #expect(recorded.identity.envPrefix == CoreProtocol.envPrefix)
        #expect(recorded.identity.dataDir == ".spacevibe")
        #expect(recorded.protocolVersion == CoreProtocol.version)
    }

    // MARK: Frozen goldens

    @Test("usage.json is a CoreUsageResult")
    func usageGolden() throws {
        #expect(try CoreTestData.roundTripDifference(try CoreTestData.json("fixtures/golden/usage.json"), as: CoreUsageResult.self) == nil)
    }

    @Test("inventory.json holds a CoreInventorySnapshot, the usage input and the filter counts")
    func inventoryGolden() throws {
        let golden = try #require(try CoreTestData.json("fixtures/golden/inventory.json") as? [String: Any])
        let inventory = try #require(golden["inventory"])
        #expect(try CoreTestData.roundTripDifference(inventory, as: CoreInventorySnapshot.self) == nil)
        let snapshot = try JSONDecoder().decode(CoreInventorySnapshot.self, from: JSONSerialization.data(withJSONObject: inventory))
        #expect(snapshot.items.contains { $0.hasSkillOverride }, "an item that carries the override member")
        #expect(snapshot.items.contains { !$0.hasSkillOverride }, "an item that omits it")
        let input = try #require(golden["usageInput"] as? [String: Any])
        #expect(try CoreTestData.roundTripDifference(try #require(input["totals"]), as: CoreUsageTotals.self) == nil)
        #expect(try CoreTestData.roundTripDifference(try #require(input["windows"]), as: CoreUsageWindows.self) == nil)
        #expect(try CoreTestData.roundTripDifference(try #require(golden["filterCounts"]), as: CoreFilterCounts.self) == nil)
    }

    @Test("activity.json holds CoreActivityReports")
    func activityGolden() throws {
        let golden = try #require(try CoreTestData.json("fixtures/golden/activity.json") as? [String: Any])
        for name in ["shared", "extra"] {
            #expect(try CoreTestData.roundTripDifference(try #require(golden[name]), as: CoreActivityReport.self) == nil, "\(name)")
        }
    }

    @Test("limits.json results are CoreLimitsEntry lists")
    func limitsGolden() throws {
        let golden = try #require(try CoreTestData.json("fixtures/golden/limits.json") as? [String: Any])
        let cases = try #require(golden["cases"] as? [[String: Any]])
        var measured = 0
        for item in cases {
            let result = try #require(item["result"] as? [Any])
            let name = item["name"] as? String ?? "?"
            #expect(try CoreTestData.roundTripDifference(["limits": result], as: CoreLimitsResult.self) == nil, "\(name)")
            let entries = try JSONDecoder().decode(CoreLimitsResult.self, from: JSONSerialization.data(withJSONObject: ["limits": result])).limits
            measured += entries.filter { $0.state == .measured }.count
        }
        #expect(cases.count > 5)
        #expect(measured > 0)
    }

    @Test("rules.json lists are CoreRule lists and previews are CoreCapabilityPreviews")
    func rulesGolden() throws {
        let golden = try #require(try CoreTestData.json("fixtures/golden/rules.json") as? [String: Any])
        var rules = 0
        var previews = 0
        for section in ["shared", "main"] {
            let body = try #require(golden[section] as? [String: Any])
            for (scope, list) in try #require(body["lists"] as? [String: [String: Any]]) {
                let found = try #require(list["rules"] as? [Any])
                #expect(try CoreTestData.roundTripDifference(found, as: [CoreRule].self) == nil, "\(section) \(scope)")
                rules += found.count
            }
            for (key, outcome) in try #require(body["previews"] as? [String: [String: Any]]) {
                guard let preview = outcome["ok"] else { continue }
                #expect(try CoreTestData.roundTripDifference(preview, as: CoreCapabilityPreview.self) == nil, "\(section) \(key)")
                previews += 1
            }
        }
        #expect(rules > 20)
        #expect(previews > 10)
    }

    // MARK: Shapes the goldens do not carry

    private static let loadoutRows = """
    {"usage":"ready","items":[{"id":"claude:skill:local:a","cli":"claude","kind":"skill","name":"a","entry":"a","description":"","owner":"user","path":"/h/.claude/skills/a","file":"/h/.claude/skills/a/SKILL.md","removable":true,"scope":"global","project":null,"inOther":false,"override":null,"key":"skill::a","cells":{"claude":{"state":"counted","runs":2,"last":"2026-11-01"},"codex":{"state":"missing"}}}],
     "hooks":[{"id":"claude:hook:abc","cli":"claude","kind":"hook","event":"Stop","matcher":null,"command":"x.sh","timeout":5.5,"async":false,"owner":"user","removable":true,"dead":true,"paths":["/h/x.sh"],"hash":"abc","file":"/h/.claude/settings.json","scope":"project","project":"/p","key":"hook:/p:abc","cells":{"claude":{"state":"counted","runs":1,"errors":1,"last":null},"codex":{"state":"unmeasurable","reason":"Codex does not log hook runs"}},"usage":{"runs":1,"avgMs":null,"totalMs":0,"errors":1,"last":null}}],
     "problems":["/h/.claude/settings.json is not valid JSON."],"events":{"claude":["Stop"],"codex":["Stop"]},"roots":{"claude":"/h/.claude","codex":"/h/.codex"},
     "countsByScope":{"global":{"all":1,"only":{"claude":1,"codex":0},"neverRan":0,"dead":0},"/p":{"all":1,"only":{"claude":1,"codex":0},"neverRan":0,"dead":1}},
     "rowFlags":{"skill::a":{"one":true,"neverRan":false,"dead":false},"hook:/p:abc":{"one":true,"neverRan":false,"dead":true}}}
    """

    private static let rulesSnapshot = """
    {"projectDirs":["/p"],"globalRuleCount":2,"scope":"project","dir":"/p","fileLabel":".claude/settings.json","exists":true,"problems":[],
     "rules":[{"id":"project:ask:Bash","scope":"project","dir":"/p","file":"/p/.claude/settings.json","verdict":"ask","rule":"Bash","tool":"Bash","specifier":null}],
     "grid":[{"capability":"run","label":"Run commands","state":"ask","editable":true,"rules":[{"id":"project:ask:Bash","scope":"project","dir":"/p","file":"/p/.claude/settings.json","verdict":"ask","rule":"Bash","tool":"Bash","specifier":null}]}],
     "codex":{"present":true,"model":"profiles","unrestricted":false,"warnings":["w"],"approvalPolicy":{"granular":[{"key":"rules","value":true}]},"sandboxMode":null,
       "sandboxWorkspaceWrite":{"networkAccess":null,"writableRoots":["/w"]},"defaultPermissions":"strict","approvalsReviewer":null,
       "profiles":[{"name":"strict","filesystemEntries":2,"networkEntries":1,"networkFlags":[{"key":"enabled","value":true},{"key":"mode","value":"proxy"},{"key":"port","value":8080},{"key":"ratio","value":0.5}]}],
       "projects":[{"path":"/p","trustLevel":"trusted"},{"path":"/q","trustLevel":null}],
       "rules":{"files":1,"allow":1,"prompt":0,"forbidden":0,"other":0,"unreadable":0,"folderNotReadable":false},"notReadable":false,"skippedLines":3},
     "notReadable":false,"globalNotReadable":false}
    """

    private static let activityWithNewCode = """
    {"sessions":[{"cli":"codex","id":"pid:7:1","title":"t","project":null,"pid":7,"state":"unmeasurable","stateReason":"r","reasonCode":"a-code-the-core-adds-later","currentTool":null,"ageMs":null,"lastWriteAgoMs":null,"cost":null,"costNote":null}],
     "failures":[],"files":[],"unmeasurable":[{"cli":"codex","code":"codex-process-unknown","text":"x"}],"stats":{"logs":0,"truncated":0}}
    """

    private func object(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    @Test("loadout.rows round-trips, including the cell shapes and the hook usage null")
    func loadoutRowsShape() throws {
        #expect(try CoreTestData.roundTripDifference(try object(Self.loadoutRows), as: CoreLoadoutRows.self) == nil)
    }

    @Test("rules.snapshot round-trips, including the Codex policy, flag values and the Go-only members")
    func rulesSnapshotShape() throws {
        #expect(try CoreTestData.roundTripDifference(try object(Self.rulesSnapshot), as: CoreRulesSnapshot.self) == nil)
    }

    @Test("an unknown reasonCode or unmeasurable code decodes and is kept")
    func openReasonCodes() throws {
        #expect(try CoreTestData.roundTripDifference(try object(Self.activityWithNewCode), as: CoreActivityReport.self) == nil)
        let report = try JSONDecoder().decode(CoreActivityReport.self, from: Data(Self.activityWithNewCode.utf8))
        #expect(report.sessions[0].reasonCode == "a-code-the-core-adds-later")
    }

    @Test("the small results round-trip")
    func smallResults() throws {
        let entry = #"{"id":"e1","at":"2026-11-07T10:00:00.000Z","label":"Removed skill a from Claude Code","undone":false,"count":2}"#
        #expect(try roundTrip(#"{"entry":\#(entry)}"#, as: CoreEntryResult.self) == nil)
        #expect(try roundTrip(#"{"entry":\#(entry)}"#, as: CoreSetCapabilityResult.self) == nil)
        #expect(try roundTrip(#"{"entry":null}"#, as: CoreSetCapabilityResult.self) == nil)
        #expect(try roundTrip(#"{"entries":[\#(entry)]}"#, as: CoreJournalHistory.self) == nil)
        #expect(try roundTrip(#"{"label":"Set Run commands to Ask"}"#, as: CoreUndoResult.self) == nil)
        #expect(try roundTrip(#"{"exited":true}"#, as: CoreStopResult.self) == nil)
        #expect(try roundTrip(#"{"valid":false,"message":"Enter a rule such as Bash(npm test *)."}"#, as: CoreRuleCheck.self) == nil)
        #expect(try roundTrip(#"{"valid":true,"message":null}"#, as: CoreRuleCheck.self) == nil)
        #expect(try roundTrip(#"{"done":20,"total":180}"#, as: CoreUsageProgress.self) == nil)
        #expect(try roundTrip(#"{"status":409,"message":"Nothing to change."}"#, as: CoreError.self) == nil)
    }

    private func roundTrip<T: Codable>(_ text: String, as type: T.Type) throws -> String? {
        try CoreTestData.roundTripDifference(try object(text), as: type)
    }

    @Test("a member the wire omits stays omitted, and a null stays null")
    func omittedVersusNull() throws {
        let omitted = #"{"id":"i","cli":"codex","kind":"agent","name":"n","entry":"n.md","description":"","owner":"user","path":"p","file":"f","removable":false,"scope":"project","project":"/p","inOther":true,"key":"agent:/p:n"}"#
        let item = try JSONDecoder().decode(CoreInventoryItem.self, from: Data(omitted.utf8))
        #expect(!item.hasSkillOverride)
        #expect(item.cells == nil)
        let text = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))
        #expect(!text.contains("override"))
        #expect(!text.contains("cells"))
        #expect(try roundTrip(omitted, as: CoreInventoryItem.self) == nil)
    }

    @Test("CoreError is the shape of a -32000 data member and keeps the message-and-status call shape")
    func coreErrorShape() throws {
        let error = CoreError("Gone.", status: 404)
        #expect(error == CoreError(status: 404, message: "Gone."))
        #expect(error.localizedDescription == "Gone.")
        let text = try #require(String(data: JSONEncoder().encode(error), encoding: .utf8))
        #expect(try object(text) as? NSDictionary == ["status": 404, "message": "Gone."])
        #expect(CoreError("Bad input.").status == 400)
    }

    @MainActor
    @Test("a screen shows a CoreError's message and any other error as one fixed sentence")
    func environmentMessage() {
        #expect(AppEnvironment.message(CoreError("Gone.", status: 404)) == "Gone.")
        #expect(AppEnvironment.message(CancellationError()) == CoreError.unexpectedMessage)
    }
}
