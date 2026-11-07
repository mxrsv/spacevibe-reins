import Foundation
import Testing
@testable import ReinsCore

/// Swift Rules and Codex reader against the frozen goldens (SV5), last generated at b58269d3f3eb for the same files.
/// Reads run on the shared fixture HOME and on Fixtures/rules-home/main; every write case runs on a fresh copy of
/// rules-home/main in a TempHome. Writes are compared by the parsed settings JSON, the journal label and op kinds, and the
/// refusal (status and message): Node rewrites a whole file and Swift edits only the changed list, so bytes are tested in RulesTests.
@Suite("Rules golden")
struct RulesGoldenTests {
    @Test("shared fixture HOME: rules, grids, previews and Codex keys match the Node core")
    func goldenSharedHome() throws {
        let golden = try #require(try FixtureHome.golden("rules") as? [String: Any])
        let shared = try #require(golden["shared"] as? [String: Any])
        try FixtureHome.materialize()
        let roots = try Roots.resolve(env: FixtureHome.env)
        let view = RulesGoldenView(store: RulesStore(roots: roots), root: FixtureHome.canonicalRoot)
        try view.compareReads(shared)
        // the fixture must keep covering a mixed cell, an own-rules cell and a wide rule written as Read(*)
        let global = try view.grid(.global)
        #expect(global.first { $0.capability == .read }?.state == .allow)
        #expect(global.first { $0.capability == .edit }?.state == .mixed)
        #expect(global.first { $0.capability == .push }?.state == .ask)
    }

    @Test("section fixture HOME (rules-home/main): the same reads match, including broken, null and empty projects")
    func goldenMainHome() throws {
        let golden = try #require(try FixtureHome.golden("rules") as? [String: Any])
        let main = try #require(golden["main"] as? [String: Any])
        let home = try TempHome()
        let store = RulesStore(roots: try Roots.resolve(env: home.env))
        try RulesGoldenView.materialize("main", into: home)
        let view = RulesGoldenView(store: store, root: home.root)
        try view.compareReads(main)
        #expect(try view.list(.project(home.url("proj-broken").path)).problems.count == 1)
    }

    @Test("Codex configs of rules-home match the Node reader")
    func goldenCodex() throws {
        let golden = try #require(try FixtureHome.golden("rules") as? [String: Any])
        let cases = try #require(golden["codex"] as? [String: Any])
        #expect(cases.count == 5)
        for (name, expected) in cases.sorted(by: { $0.key < $1.key }) {
            let home = try TempHome()
            if name != "missing" { try RulesGoldenView.materialize("codex-\(name)", into: home) }
            let actual = RulesGoldenView.codex(CodexPermissions.read(roots: try Roots.resolve(env: home.env)))
            let diff = FixtureHome.firstDifference(FixtureHome.normalize(actual, root: home.root), expected)
            #expect(diff == nil, Comment(rawValue: "\(name): \(diff ?? "")"))
        }
    }

    @Test("every write case of the Node core gives the same settings, label and refusal")
    func goldenWrites() throws {
        let golden = try #require(try FixtureHome.golden("rules") as? [String: Any])
        let cases = try #require(golden["writes"] as? [[String: Any]])
        #expect(cases.count > 100)
        var refused = 0, noOps = 0
        for item in cases {
            let home = try TempHome()
            let store = RulesStore(roots: try Roots.resolve(env: home.env))
            try RulesGoldenView.materialize("main", into: home)
            let view = RulesGoldenView(store: store, root: home.root)
            let actual = try view.runWrite(item)
            let diff = FixtureHome.firstDifference(FixtureHome.normalize(actual, root: home.root), try #require(item["expected"]))
            #expect(diff == nil, Comment(rawValue: "\(item["fn"] ?? "") \(item["args"] ?? "") \(item["scope"] ?? ""): \(diff ?? "")"))
            if actual["error"] != nil { refused += 1 }
            if actual["ok"] is NSNull { noOps += 1 }
        }
        #expect(refused > 20 && noOps >= 1, "the golden keeps covering refusals (\(refused)) and a no-op (\(noOps))")
    }
}

/// Turns Swift results into the JSON shape of the frozen goldens (SV5), last generated at b58269d3f3eb, and replays its cases.
struct RulesGoldenView {
    let store: RulesStore
    let root: URL

    // MARK: Fixture homes

    /// A copy of Fixtures/rules-home/<name> with `$HOME` replaced by the home's folder.
    static func materialize(_ name: String, into home: TempHome) throws {
        let source = Fixtures.url("rules-home/\(name)")
        let walker = try #require(FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = String(url.path.dropFirst(source.path.count + 1))
            let text = try String(contentsOf: url, encoding: .utf8)
            try home.write(relative, text.replacingOccurrences(of: FixtureHome.token, with: home.root.path))
        }
    }

    // MARK: Scopes

    func scope(kind: String, rel: String?) -> RuleScope {
        let dir = rel.map { InventoryFileIO.join(root.path, $0) }
        switch kind {
        case "project": return .project(dir!)
        case "local": return .local(dir!)
        default: return .global
        }
    }

    func scope(key: String) -> RuleScope {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        return scope(kind: parts[0], rel: parts.count > 1 ? parts[1] : nil)
    }

    func list(_ scope: RuleScope) throws -> RuleListing { try store.listRules([scope]) }
    func grid(_ scope: RuleScope) throws -> [CapabilityCell] { Rules.capabilityGrid(try list(scope).rules) }

    // MARK: Views

    func ruleObject(_ x: RuleItem) -> [String: Any] {
        ["id": x.id, "scope": x.scope.kind, "dir": x.scope.dir ?? NSNull(), "file": x.file, "verdict": x.verdict.rawValue, "rule": x.rule,
         "tool": x.tool ?? NSNull(), "specifier": x.specifier ?? NSNull()]
    }

    func gridObject(_ cells: [CapabilityCell]) -> [[String: Any]] {
        cells.map { ["capability": $0.capability.rawValue, "label": $0.label, "state": $0.state.rawValue, "editable": $0.editable, "rules": $0.rules.map(\.id)] }
    }

    func pairs(_ list: [VerdictRule]) -> [[String: Any]] { list.map { ["verdict": $0.verdict.rawValue, "rule": $0.rule] } }

    func previewOutcome(_ scope: RuleScope, _ capability: Capability, _ verdict: RuleVerdict) -> [String: Any] {
        outcome {
            let p = try store.previewSetCapability(scope: scope, capability: capability, verdict: verdict)
            return ["capability": p.capability.rawValue, "verdict": p.verdict.rawValue, "scopeLabel": p.scopeLabel, "current": p.current.rawValue,
                    "resulting": p.resulting.rawValue, "replaces": pairs(p.replaces), "writes": pairs(p.writes)]
        }
    }

    /// `{ok: value}` or `{error: {status, message}}`, like `attempt` in the golden script.
    func outcome(_ body: () throws -> Any) -> [String: Any] {
        do { return ["ok": try body()] } catch let error as ReinsError { return ["error": ["status": error.status, "message": error.message]] } catch { return ["error": ["status": -1, "message": "\(error)"]] }
    }

    // MARK: Reads

    func compareReads(_ expected: [String: Any]) throws {
        let lists = try #require(expected["lists"] as? [String: Any])
        let grids = try #require(expected["grids"] as? [String: Any])
        let merged = try #require(expected["merged"] as? [String: Any])
        let previews = try #require(expected["previews"] as? [String: Any])
        #expect(!lists.isEmpty && previews.count == lists.count * Capability.allCases.count * RuleVerdict.allCases.count)
        func check(_ actual: Any, _ golden: Any?, _ what: String) {
            let diff = FixtureHome.firstDifference(FixtureHome.normalize(actual, root: root), golden as Any)
            #expect(diff == nil, Comment(rawValue: "\(what): \(diff ?? "")"))
        }
        for key in lists.keys.sorted() {
            let scope = scope(key: key)
            let listing = try list(scope)
            check(["rules": listing.rules.map(ruleObject), "problems": listing.problems], lists[key], "list \(key)")
            check(gridObject(Rules.capabilityGrid(listing.rules)), grids[key], "grid \(key)")
            for capability in Capability.allCases {
                for verdict in RuleVerdict.allCases {
                    let id = "\(key)|\(capability.rawValue)|\(verdict.rawValue)"
                    check(previewOutcome(scope, capability, verdict), previews[id], "preview \(id)")
                }
            }
        }
        for rel in merged.keys.sorted() {
            let dir = InventoryFileIO.join(root.path, rel)
            let rules = try store.listRules(RuleScope.scopes(for: dir)).rules
            check(gridObject(Rules.capabilityGrid(rules)), merged[rel], "merged \(rel)")
        }
        check(Self.codex(CodexPermissions.read(roots: store.roots)), expected["codex"], "codex")
    }

    // MARK: Codex

    static func codex(_ c: CodexPermissions) -> [String: Any] {
        func flags(_ members: [JSONMember]) -> [String: Any] {
            Dictionary(uniqueKeysWithValues: members.map { member in
                (member.key, member.value.boolValue.map { $0 as Any } ?? member.value.stringValue.map { $0 as Any } ?? member.value.numberText.flatMap(Double.init) as Any)
            })
        }
        let policy: Any
        switch c.approvalPolicy {
        case .mode(let text)?: policy = text
        case .granular(let members)?: policy = ["granular": flags(members)]
        case nil: policy = NSNull()
        }
        return [
            "present": c.present, "model": c.model.rawValue, "unrestricted": c.unrestricted, "warnings": c.warnings,
            "approval_policy": policy, "sandbox_mode": c.sandboxMode ?? NSNull(),
            "sandbox_workspace_write": c.sandboxWorkspaceWrite.map { ["network_access": $0.networkAccess ?? NSNull(), "writable_roots": $0.writableRoots] as [String: Any] } ?? NSNull(),
            "default_permissions": c.defaultPermissions ?? NSNull(), "approvals_reviewer": c.approvalsReviewer ?? NSNull(),
            "profiles": c.profiles.map { ["name": $0.name, "filesystemEntries": $0.filesystemEntries, "networkEntries": $0.networkEntries, "networkFlags": flags($0.networkFlags)] as [String: Any] },
            "projects": c.projects.map { ["path": $0.path, "trust_level": $0.trustLevel ?? NSNull()] as [String: Any] },
            "rules": ["files": c.rules.files, "allow": c.rules.allow, "prompt": c.rules.prompt, "forbidden": c.rules.forbidden, "other": c.rules.other],
        ]
    }

    // MARK: Writes

    func runWrite(_ item: [String: Any]) throws -> [String: Any] {
        let spec = try #require(item["scope"] as? [String: Any])
        let scope = scope(kind: spec["kind"] as? String ?? "global", rel: spec["rel"] as? String)
        let args = try #require(item["args"] as? [String: Any])
        func verdict(_ key: String) -> RuleVerdict { RuleVerdict(rawValue: args[key] as! String)! }
        var result = outcome { () throws -> Any in
            let entry: JournalEntry?
            switch item["fn"] as? String {
            case "addRule": entry = try store.addRule(scope: scope, verdict: verdict("verdict"), rule: args["rule"] as! String)
            case "removeRule": entry = try store.removeRule(scope: scope, verdict: verdict("verdict"), rule: args["rule"] as! String)
            case "changeVerdict": entry = try store.changeVerdict(scope: scope, rule: args["rule"] as! String, from: verdict("from"), to: verdict("to"))
            default: entry = try store.setCapability(scope: scope, capability: Capability(rawValue: args["capability"] as! String)!, verdict: verdict("verdict"))
            }
            guard let entry else { return NSNull() }
            return ["label": entry.label, "ops": entry.ops.map { ["type": $0.type, "existed": $0.json["existed"]?.boolValue ?? false] as [String: Any] }]
        }
        result["files"] = try settingsAfter()
        return result
    }

    /// Every `.json` file of the home, parsed; a file that is not JSON is recorded as a sentinel, never as its text.
    func settingsAfter() throws -> [String: Any] {
        var out: [String: Any] = [:]
        let walker = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in walker where url.pathExtension == "json" {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            if relative.hasPrefix(".reins") || relative.hasPrefix(".spacevibe") { continue }
            out[relative] = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) ?? "<not JSON>"
        }
        return out
    }
}
