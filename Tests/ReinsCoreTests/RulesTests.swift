import Foundation
import Testing
@testable import ReinsCore

/// Claude permission rules (RulesStore, Rules grid) and the read-only Codex reader (CodexPermissions). Every test runs on a
/// TempHome or FixtureHome; the real ~/.claude and ~/.codex are never read (REINS_TEST=1 and the Roots guard).
/// Behavior reference: core/rules.mjs and core/rules.test.mjs.
@Suite("Rules")
struct RulesTests {
    /// Stands in for a secret value: it must never show up in a result, a message, a label or the journal.
    private static let canary = "canary-secret-9f3a1c"

    /// A throwaway HOME whose projects are found by discovery, as in the app.
    private struct Sandbox {
        let home: TempHome
        let roots: Roots
        let store: RulesStore
        var settings: URL { roots.claude.hookFile }

        init() throws {
            home = try TempHome()
            roots = try Roots.resolve(env: home.env)
            store = RulesStore(roots: roots)
        }

        /// A project folder with a `.claude` folder, listed in Codex `config.toml` so discovery finds it.
        @discardableResult
        func project(_ name: String) throws -> String {
            let dir = home.url(name)
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            let config = home.codex.appendingPathComponent("config.toml")
            let old = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
            try home.write(".codex/config.toml", old + "[projects.\"\(dir.path)\"]\ntrust_level = \"trusted\"\n")
            return dir.path
        }

        func bytes(_ url: URL? = nil) throws -> Data { try Data(contentsOf: url ?? settings) }
        func text(_ url: URL? = nil) throws -> String { String(decoding: try bytes(url), as: UTF8.self) }
        func parsed(_ url: URL? = nil) throws -> JSONValue { try OrderedJSON(data: try bytes(url)).root }
        func mode(_ url: URL? = nil) throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: (url ?? settings).path)[.posixPermissions] as! NSNumber).intValue & 0o777
        }
        func setMode(_ mode: Int, _ url: URL? = nil) throws {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: (url ?? settings).path)
        }
        func journalText() -> String { (try? String(contentsOf: roots.data.appendingPathComponent("journal.json"), encoding: .utf8)) ?? "" }
        func strayTempFiles(in folder: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".tmp") }
        }
        func undo(_ entry: JournalEntry?) throws {
            _ = try Journal.undo(roots, id: try #require(entry).id)
        }
    }

    private static func pretty(_ value: JSONValue, indent: String = "  ") throws -> String { try OrderedJSON.pretty(value, indent: indent) }

    private static func permissionsObject(_ allow: [String]? = nil, ask: [String]? = nil, deny: [String]? = nil) -> JSONValue {
        func list(_ items: [String]) -> JSONValue { .array(items.map(JSONValue.string)) }
        var members: [JSONMember] = []
        if let allow { members.append(JSONMember("allow", list(allow))) }
        if let ask { members.append(JSONMember("ask", list(ask))) }
        if let deny { members.append(JSONMember("deny", list(deny))) }
        return .object(members)
    }

    private func rl(_ verdict: RuleVerdict, _ rule: String) -> RuleItem { RuleItem(verdict: verdict, rule: rule) }
    private func stateOf(_ rules: [RuleItem], _ capability: Capability) -> CapabilityState {
        Rules.capabilityGrid(rules).first { $0.capability == capability }!.state
    }
    private func refusal(_ body: () throws -> Any?) -> ReinsError? {
        do { _ = try body(); return nil } catch let error as ReinsError { return error } catch { return nil }
    }

    // MARK: Rule shape

    @Test("parseRule: Tool, Tool(specifier), blanks, and what is not a rule")
    func parseRuleShapes() {
        #expect(Rules.parseRule("Bash(npm test:*)") == ParsedRule(tool: "Bash", specifier: "npm test:*"))
        #expect(Rules.parseRule("  Read  ") == ParsedRule(tool: "Read", specifier: nil))
        #expect(Rules.parseRule("Bash()") == ParsedRule(tool: "Bash", specifier: nil))
        #expect(Rules.parseRule("Bash(  )") == ParsedRule(tool: "Bash", specifier: nil))
        #expect(Rules.parseRule("mcp__demo__lookup") == ParsedRule(tool: "mcp__demo__lookup", specifier: nil))
        #expect(Rules.parseRule("Edit( a b )(c)") == ParsedRule(tool: "Edit", specifier: " a b )(c"))
        #expect(Rules.parseRule("Bash(a\nb)") == ParsedRule(tool: "Bash", specifier: "a\nb"))
        for bad in ["", "   ", "not a rule!", "Bash(unclosed", "(x)", "Bash)", "9Bash", "Bash(x) y", "Bàsh", "???"] {
            #expect(Rules.parseRule(bad) == nil, "\(bad)")
        }
    }

    @Test("pushes and deploys are recognised by ASCII word rules, as JavaScript does")
    func pushDeployText() {
        for yes in ["git push", "git   push origin", "vercel --prod", "gh pr merge 1", "npm publish", "echo deploy now", "deploy", "wrangler deploy", "yarn\tpublish"] {
            #expect(Rules.looksLikePushOrDeploy(yes), "\(yes)")
        }
        for no in ["git pushd", "vercelx", "npm test", "redeploy", "git status", "deployment"] {
            #expect(!Rules.looksLikePushOrDeploy(no), "\(no)")
        }
        // A letter next to the word is a word character only in ICU's view; JavaScript treats it as a boundary.
        #expect(Rules.looksLikePushOrDeploy("vercelé"))
        #expect(Rules.namesEnvFile("./.env") && Rules.namesEnvFile(".env.local") && Rules.namesEnvFile("**/.env*") && Rules.namesEnvFile("a/.env"))
        #expect(!Rules.namesEnvFile("src/x.env") && !Rules.namesEnvFile("environment"))
    }

    // MARK: Listing

    @Test("lists rules by scope and keeps values that are not rules out of the tool/specifier fields")
    func listing() throws {
        let sb = try Sandbox()
        let proj = try sb.project("proj")
        try sb.home.write(".claude/settings.json", """
        {"env":{"TOKEN":"\(Self.canary)"},"permissions":{"allow":["Bash(npm test:*)",42,"not a rule!"],"deny":["Read(./.env)"]}}
        """)
        try sb.home.write("proj/.claude/settings.json", #"{"permissions":{"ask":["Edit"]}}"#)
        try sb.home.write("proj/.claude/settings.local.json", #"{"permissions":{"allow":["WebFetch"]}}"#)
        let listing = try sb.store.listRules(RuleScope.scopes(for: proj))
        #expect(listing.problems.isEmpty)
        #expect(listing.rules.map { "\($0.scope.kind):\($0.verdict.rawValue):\($0.rule)" } == [
            "global:allow:Bash(npm test:*)", "global:allow:not a rule!", "global:deny:Read(./.env)", "project:ask:Edit", "local:allow:WebFetch",
        ])
        #expect(listing.rules[0].tool == "Bash" && listing.rules[0].specifier == "npm test:*")
        #expect(listing.rules[1].tool == nil)
        #expect(listing.rules[0].id == "global:allow:Bash(npm test:*)" && listing.rules[3].scope == .project(proj))
        #expect(try sb.store.listRules([.local(try sb.project("empty"))]).rules.isEmpty)
        #expect(refusal { try sb.store.listRules([.project("relative")]) }?.status == 400)
    }

    @Test("a project folder must be one discovery found: others are refused with 404 and nothing is created")
    func undiscoveredFolder() throws {
        let sb = try Sandbox()
        try sb.project("known")
        let stranger = sb.home.url("stranger")
        try FileManager.default.createDirectory(at: stranger, withIntermediateDirectories: true)
        let missing = sb.home.url("missing").path
        for scope in [RuleScope.project(stranger.path), .local(stranger.path), .project(missing), .local("/etc"), .project(sb.home.root.path)] {
            #expect(refusal { try sb.store.listRules([scope]) }?.status == 404)
            #expect(refusal { try sb.store.addRule(scope: scope, verdict: .allow, rule: "Read") }?.status == 404)
            #expect(refusal { try sb.store.setCapability(scope: scope, capability: .read, verdict: .deny) }?.status == 404)
            #expect(refusal { try sb.store.previewSetCapability(scope: scope, capability: .read, verdict: .deny) }?.status == 404)
        }
        #expect(!FileManager.default.fileExists(atPath: stranger.appendingPathComponent(".claude").path))
        #expect(!FileManager.default.fileExists(atPath: "/etc/.claude"))
        #expect(Journal.history(sb.roots).isEmpty)
        // a known folder with a trailing slash or a dot segment is the same folder
        #expect(try sb.store.listRules([.project(sb.home.url("known").path + "/./")]).problems.isEmpty)
    }

    // MARK: Writing

    @Test("add, change and remove keep other keys and the indent; undo restores identical bytes and the mode")
    func addChangeRemoveUndo() throws {
        for indent in ["    ", "\t"] {
            let sb = try Sandbox()
            let start = try Self.pretty(.object([
                JSONMember("env", .object([JSONMember("TOKEN", .string(Self.canary))])), JSONMember("model", "x"),
                JSONMember("permissions", Self.permissionsObject(["Read"])), JSONMember("hooks", .object([])),
            ]), indent: indent)
            try sb.home.write(".claude/settings.json", start)
            try sb.setMode(0o640)
            let before = try sb.bytes()

            let added = try sb.store.addRule(scope: .global, verdict: .deny, rule: "Bash(rm *)")
            let afterAdd = try sb.text()
            let parsed = try sb.parsed()
            #expect(parsed["permissions"] == Self.permissionsObject(["Read"], deny: ["Bash(rm *)"]))
            #expect(parsed["env"] == .object([JSONMember("TOKEN", .string(Self.canary))]))
            #expect(parsed["model"] == "x" && parsed["hooks"] == .object([]))
            #expect(afterAdd.hasPrefix("{\n\(indent)\"env\""), "indent kept")
            #expect(afterAdd.hasSuffix("}\n"))
            #expect(try sb.mode() == 0o640)

            let moved = try sb.store.changeVerdict(scope: .global, rule: "Bash(rm *)", from: .deny, to: .ask)
            // the new list goes at the end of the block, after the lists that were already there
            #expect(try sb.parsed()["permissions"] == .object([
                JSONMember("allow", .array(["Read"])), JSONMember("deny", .array([])), JSONMember("ask", .array(["Bash(rm *)"])),
            ]))
            let removed = try sb.store.removeRule(scope: .global, verdict: .ask, rule: "Bash(rm *)")
            #expect(try sb.parsed()["permissions"]?["ask"] == .array([]), "an emptied list stays as []")

            try sb.undo(removed); try sb.undo(moved); try sb.undo(added)
            #expect(try sb.bytes() == before, "undo restored the exact bytes")
            #expect(try sb.mode() == 0o640)
            #expect(sb.strayTempFiles(in: sb.roots.claude.root).isEmpty)
        }
    }

    @Test("CRLF line endings, a compact one-line file and a missing trailing newline are kept")
    func formattingKept() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", "{\r\n  \"model\": \"x\",\r\n  \"permissions\": {\r\n    \"allow\": [\r\n      \"Read\"\r\n    ]\r\n  }\r\n}\r\n")
        try sb.store.addRule(scope: .global, verdict: .allow, rule: "Edit")
        let crlf = try sb.text()
        #expect(crlf.contains("\r\n") && !crlf.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "every line break is CRLF")
        #expect(crlf.hasSuffix("}\r\n"))
        #expect(try sb.parsed()["permissions"]?["allow"] == .array(["Read", "Edit"]))

        try sb.home.write(".claude/settings.json", #"{"model":"x"}"#)
        let before = try sb.bytes()
        let entry = try sb.store.addRule(scope: .global, verdict: .allow, rule: "WebSearch")
        #expect(try sb.text() == #"{"model":"x","permissions":{"allow":["WebSearch"]}}"#, "compact style, no newline added")
        try sb.undo(entry)
        #expect(try sb.bytes() == before)
    }

    @Test("rules go into a file without a permissions block, into `permissions: null`, and a created file is removed by undo")
    func missingBlockAndCreatedFile() throws {
        let sb = try Sandbox()
        let proj = try sb.project("proj")
        let local = sb.home.url("proj/.claude/settings.local.json")
        let entry = try sb.store.addRule(scope: .local(proj), verdict: .allow, rule: "Bash(git status)")
        #expect(try sb.parsed(local) == .object([JSONMember("permissions", Self.permissionsObject(["Bash(git status)"]))]))
        #expect(try sb.mode(local) == 0o600)
        try sb.undo(entry)
        #expect(!FileManager.default.fileExists(atPath: local.path))

        try sb.home.write(".claude/settings.json", #"{"permissions":null,"model":"x"}"#)
        try sb.store.addRule(scope: .global, verdict: .deny, rule: "Bash(rm *)")
        #expect(try sb.parsed()["permissions"] == Self.permissionsObject(nil, deny: ["Bash(rm *)"]))
        #expect(try sb.parsed()["model"] == "x")
    }

    @Test("values in a rule list that are not strings are kept, and a removed rule goes everywhere it appears")
    func nonStringsAndDuplicates() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", #"{"permissions":{"allow":["Read",42,"Edit","Read",null,{"a":1}]}}"#)
        try sb.store.removeRule(scope: .global, verdict: .allow, rule: "Read")
        #expect(try sb.parsed()["permissions"]?["allow"] == .array([.number("42"), "Edit", .null, .object([JSONMember("a", .number("1"))])]))
    }

    @Test("a symlinked settings file stays a symlink and the target is edited")
    func symlinkedSettings() throws {
        let sb = try Sandbox()
        let target = try sb.home.write("shared-settings.json", "{}\n")
        try FileManager.default.createDirectory(at: sb.roots.claude.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sb.settings, withDestinationURL: target)
        try sb.store.addRule(scope: .global, verdict: .allow, rule: "Read")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sb.settings.path)) != nil)
        #expect(try sb.parsed(target)["permissions"]?["allow"] == .array(["Read"]))
    }

    @Test("invalid JSON, wrong shapes and bad input are refused without touching the file or quoting its text")
    func refusals() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", "{\"env\":{\"TOKEN\":\"\(Self.canary)\"} oops")
        let before = try sb.bytes()
        let attempts: [() throws -> Any?] = [
            { try sb.store.addRule(scope: .global, verdict: .allow, rule: "Read") },
            { try sb.store.removeRule(scope: .global, verdict: .allow, rule: "Read") },
            { try sb.store.changeVerdict(scope: .global, rule: "Read", from: .allow, to: .deny) },
            { try sb.store.setCapability(scope: .global, capability: .read, verdict: .deny) },
            { try sb.store.previewSetCapability(scope: .global, capability: .read, verdict: .deny) },
        ]
        for attempt in attempts {
            let error = try #require(refusal(attempt))
            #expect(error.message.contains("is not valid JSON") && error.status == 409 && !error.message.contains(Self.canary))
        }
        #expect(try sb.bytes() == before)
        #expect(try sb.store.listRules().problems.first?.contains("is not valid JSON") == true)
        #expect(Journal.history(sb.roots).isEmpty)
        #expect(sb.strayTempFiles(in: sb.roots.claude.root).isEmpty)
        #expect(!sb.journalText().contains(Self.canary))

        try sb.home.write(".claude/settings.json", #"{"permissions":{"allow":"Read"}}"#)
        #expect(refusal { try sb.store.addRule(scope: .global, verdict: .allow, rule: "Bash") }?.message.contains("not a list") == true)
        try sb.home.write(".claude/settings.json", #"{"permissions":[]}"#)
        #expect(refusal { try sb.store.addRule(scope: .global, verdict: .allow, rule: "Bash") }?.message.contains("not an object") == true)
        try sb.home.write(".claude/settings.json", "[]")
        #expect(refusal { try sb.store.addRule(scope: .global, verdict: .allow, rule: "Bash") }?.message.contains("JSON object") == true)

        try sb.home.write(".claude/settings.json", "{}")
        for rule in ["", "   ", "two\nlines", "two\rlines", "Bash(unclosed", "(x)", String(repeating: "a", count: 1001)] {
            #expect(refusal { try sb.store.addRule(scope: .global, verdict: .allow, rule: rule) }?.status == 400, "\(rule.prefix(12))")
        }
        try sb.store.addRule(scope: .global, verdict: .allow, rule: String(repeating: "a", count: 1000))
        try sb.store.addRule(scope: .global, verdict: .allow, rule: "Bash")
        #expect(refusal { try sb.store.addRule(scope: .global, verdict: .deny, rule: "Bash") }?.message.contains("already in allow") == true)
        #expect(refusal { try sb.store.removeRule(scope: .global, verdict: .deny, rule: "Bash") }?.message.contains("already changed") == true)
        #expect(refusal { try sb.store.changeVerdict(scope: .global, rule: "Bash", from: .allow, to: .allow) }?.status == 400)
        #expect(refusal { try sb.store.changeVerdict(scope: .global, rule: "Bash", from: .ask, to: .deny) }?.status == 409)
    }

    @Test("undo refuses when the file changed after the edit")
    func undoAfterHandEdit() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", "{}\n")
        let entry = try sb.store.addRule(scope: .global, verdict: .allow, rule: "Read")
        try sb.home.write(".claude/settings.json", #"{"model":"hand-edited"}"# + "\n")
        let error = refusal { try Journal.undo(sb.roots, id: entry.id) }
        #expect(error?.status == 409 && error?.message.contains("changed since") == true)
        #expect(try sb.parsed()["model"] == "hand-edited")
    }

    // MARK: Capability grid

    @Test("capability grid, one row per mapping")
    func gridMapping() {
        func state(_ capability: Capability, _ rules: RuleItem...) -> CapabilityState { stateOf(rules, capability) }
        let a = RuleVerdict.allow, k = RuleVerdict.ask, d = RuleVerdict.deny
        #expect(Rules.capabilityGrid([]).map { "\($0.capability.rawValue):\($0.state.rawValue)" } == Capability.allCases.map { "\($0.rawValue):none" })
        // Read files and Secrets
        #expect(state(.read, rl(a, "Read")) == .allow)
        #expect(state(.secrets, rl(a, "Read")) == .allow)
        #expect(state(.read, rl(a, "Read(src/**)")) == .mixed)
        #expect(state(.read, rl(d, "Read(./.env)")) == .none)
        #expect(state(.secrets, rl(d, "Read(./.env)")) == .deny)
        #expect(state(.secrets, rl(d, "Read(**/.env*)")) == .deny)
        #expect(state(.secrets, rl(a, "Read(./.env)"), rl(k, "Read(./.env.*)")) == .mixed)
        #expect(state(.secrets, rl(a, "Read"), rl(d, "Read(./.env)")) == .deny)
        #expect(state(.read, rl(a, "Read"), rl(d, "Read(./.env)")) == .allow)
        // Edit files
        #expect(state(.edit, rl(k, "Edit")) == .ask)
        #expect(state(.edit, rl(a, "MultiEdit")) == .allow)
        #expect(state(.edit, rl(d, "Write")) == .deny)
        #expect(state(.edit, rl(k, "Edit"), rl(a, "Write(src/**)")) == .ask)
        #expect(state(.edit, rl(d, "Edit(secrets/**)")) == .mixed)
        #expect(state(.edit, rl(d, "Write"), rl(a, "Edit(a)")) == .deny)
        #expect(state(.edit, rl(a, "Edit"), rl(k, "Edit(docs/**)")) == .mixed)
        // Run commands and Push and deploy
        #expect(state(.run, rl(a, "Bash")) == .allow)
        #expect(state(.run, rl(a, "Bash(*)")) == .allow)
        #expect(state(.push, rl(a, "Bash")) == .allow)
        #expect(state(.run, rl(a, "Bash(npm test:*)")) == .mixed)
        #expect(state(.push, rl(a, "Bash(npm test:*)")) == .none)
        #expect(state(.run, rl(a, "Bash"), rl(a, "Bash(ls)")) == .allow)
        #expect(state(.run, rl(a, "Bash"), rl(d, "Bash(rm *)")) == .mixed)
        #expect(state(.run, rl(k, "Bash"), rl(a, "Bash(ls)")) == .ask)
        #expect(state(.run, rl(k, "Bash"), rl(d, "Bash(rm *)")) == .mixed)
        #expect(state(.run, rl(a, "Bash"), rl(d, "Bash")) == .deny)
        #expect(state(.run, rl(a, "Bash"), rl(k, "Bash")) == .ask)
        let pushDeny = [rl(a, "Bash"), rl(d, "Bash(git push:*)")]
        #expect(stateOf(pushDeny, .run) == .allow)
        #expect(stateOf(pushDeny, .push) == .deny)
        #expect(state(.push, rl(d, "Bash"), rl(a, "Bash(git push *)")) == .deny)
        #expect(state(.push, rl(a, "Bash(vercel deploy)")) == .allow)
        #expect(state(.push, rl(a, "Bash(npm publish)")) == .allow)
        #expect(state(.push, rl(a, "Bash(git push *)"), rl(d, "Bash(vercel *)")) == .mixed)
        #expect(state(.run, rl(a, "Bash(git push *)")) == .none)
        // Network
        #expect(state(.network, rl(d, "WebFetch")) == .deny)
        #expect(state(.network, rl(a, "WebSearch")) == .allow)
        #expect(state(.network, rl(a, "WebSearch"), rl(a, "WebFetch(domain:a.dev)")) == .allow)
        #expect(state(.network, rl(a, "WebFetch(domain:a.dev)")) == .mixed)
        // Rules that belong to no cell
        #expect(Rules.capabilityGrid([rl(a, "mcp__x__y"), rl(a, "Skill(a)"), rl(a, "???")]).map(\.state) == Capability.allCases.map { _ in .none })
        // The concrete rules behind a cell, and editable
        let cell = Rules.capabilityGrid([rl(a, "Bash"), rl(d, "Bash(rm *)")]).first { $0.capability == .run }!
        #expect(cell.rules.map(\.rule) == ["Bash", "Bash(rm *)"] && !cell.editable && cell.label == "Run commands")
    }

    @Test("a star specifier is wide for every tool, so Read(*) reads as allow")
    func starSpecifier() {
        #expect(stateOf([rl(.allow, "Read(*)")], .read) == .allow)
        #expect(stateOf([rl(.allow, "WebFetch(*)")], .network) == .allow)
        #expect(stateOf([rl(.allow, "Edit(*)"), rl(.deny, "Edit(~/.ssh/**)")], .edit) == .mixed)
        #expect(stateOf([rl(.allow, "Bash( * )")], .run) == .allow)
    }

    // MARK: Setting a cell

    @Test("preview and set replace the cell's rules, journaled and undoable; a no-op writes nothing")
    func setCapability() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", try Self.pretty(.object([
            JSONMember("model", "x"),
            JSONMember("permissions", Self.permissionsObject(["Bash", "Read(./.env)", "WebFetch"], ask: ["Edit"], deny: ["Bash(git push *)"])),
        ])))
        let before = try sb.bytes()

        let preview = try sb.store.previewSetCapability(scope: .global, capability: .run, verdict: .deny)
        #expect(preview.replaces == [VerdictRule(verdict: .allow, rule: "Bash")] && preview.writes == [VerdictRule(verdict: .deny, rule: "Bash")])
        #expect(preview.current == .allow && preview.resulting == .deny && preview.scopeLabel == "~/.claude/settings.json")
        #expect(try sb.bytes() == before, "preview writes nothing")

        try sb.store.setCapability(scope: .global, capability: .run, verdict: .deny)
        let permissions = try sb.parsed()["permissions"]
        #expect(permissions?["allow"] == .array(["Read(./.env)", "WebFetch"]))
        #expect(permissions?["deny"] == .array(["Bash(git push *)", "Bash"]))

        let network = try sb.store.setCapability(scope: .global, capability: .network, verdict: .ask)
        #expect(try sb.parsed()["permissions"]?["ask"] == .array(["Edit", "WebFetch", "WebSearch"]))
        try sb.undo(network)
        #expect(try sb.parsed()["permissions"]?["ask"] == .array(["Edit"]))

        let edit = try sb.store.previewSetCapability(scope: .global, capability: .edit, verdict: .allow)
        #expect(edit.replaces == [VerdictRule(verdict: .ask, rule: "Edit")])
        #expect(try sb.store.setCapability(scope: .global, capability: .edit, verdict: .ask) == nil, "already that value: no write, no journal entry")

        let entries = Journal.history(sb.roots)
        #expect(entries.count == 2)
        _ = try Journal.undo(sb.roots, id: entries[1].id)
        #expect(try sb.bytes() == before)
        #expect(sb.strayTempFiles(in: sb.roots.claude.root).isEmpty)
    }

    @Test("push and secrets cells write their canonical rules and report a rule that still wins")
    func pushAndSecrets() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", #"{"permissions":{"deny":["Bash"],"allow":["Read"]}}"#)
        let push = try sb.store.previewSetCapability(scope: .global, capability: .push, verdict: .allow)
        #expect(push.replaces.isEmpty, "a bare Bash belongs to Run commands and is kept")
        #expect(push.writes.map(\.rule) == ["Bash(git push *)", "Bash(vercel *)"])
        #expect(push.resulting == .deny, "the bare Bash deny still wins")

        let secrets = try sb.store.setCapability(scope: .global, capability: .secrets, verdict: .deny)
        #expect(try sb.parsed()["permissions"]?["deny"] == .array(["Bash", "Read(./.env)", "Read(./.env.*)"]))
        #expect(stateOf(try sb.store.listRules().rules, .secrets) == .deny)
        #expect(stateOf(try sb.store.listRules().rules, .read) == .allow)
        try sb.store.setCapability(scope: .global, capability: .secrets, verdict: .ask)
        let permissions = try sb.parsed()["permissions"]
        #expect(permissions?["deny"] == .array(["Bash"]) && permissions?["ask"] == .array(["Read(./.env)", "Read(./.env.*)"]))
        #expect(secrets?.label.contains("Secrets") == true)
    }

    @Test("a mixed cell is refused for preview and write, and nothing changes")
    func mixedRefused() throws {
        let sb = try Sandbox()
        try sb.home.write(".claude/settings.json", #"{"permissions":{"allow":["Bash","Edit(src/**)"],"deny":["Bash(rm *)"]}}"#)
        let before = try sb.bytes()
        for capability in [Capability.run, .edit] {
            let preview = refusal { try sb.store.previewSetCapability(scope: .global, capability: capability, verdict: .allow) }
            #expect(preview?.status == 409 && preview?.message.contains("no single value") == true)
            #expect(refusal { try sb.store.setCapability(scope: .global, capability: capability, verdict: .deny) }?.status == 409)
        }
        #expect(try sb.bytes() == before)
        #expect(Journal.history(sb.roots).isEmpty)
    }

    @Test("a cell write in a project scope only touches that project file")
    func projectScopeWrite() throws {
        let sb = try Sandbox()
        let proj = try sb.project("proj")
        try sb.home.write(".claude/settings.json", #"{"permissions":{"allow":["Bash"]}}"#)
        let globalBefore = try sb.bytes()
        try sb.store.setCapability(scope: .project(proj), capability: .run, verdict: .deny)
        #expect(try sb.parsed(sb.home.url("proj/.claude/settings.json")) == .object([JSONMember("permissions", Self.permissionsObject(nil, deny: ["Bash"]))]))
        #expect(try sb.bytes() == globalBefore)
        let merged = try sb.store.listRules(RuleScope.scopes(for: proj)).rules
        #expect(stateOf(merged, .run) == .deny, "a project deny beats a global allow")
        #expect(Journal.history(sb.roots).first?.label == "Set Run commands to Deny (project \(proj))")
    }

    // MARK: Secrets

    @Test("a secret in settings never appears in a return value, a message, a label or the journal")
    func secretsNeverEscape() throws {
        let sb = try Sandbox()
        let proj = try sb.project("proj")
        let secret = JSONValue.object([
            JSONMember("env", .object([JSONMember("TOKEN", .string(Self.canary))])),
            JSONMember("apiKeyHelper", .string("echo \(Self.canary)")),
            JSONMember("permissions", Self.permissionsObject(["Read"])),
        ])
        try sb.home.write(".claude/settings.json", try Self.pretty(secret))
        try sb.home.write("proj/.claude/settings.json", try Self.pretty(secret))
        try sb.home.write(".codex/config.toml", try String(contentsOf: sb.home.codex.appendingPathComponent("config.toml"), encoding: .utf8)
            + "[mcp_servers.x.env]\nTOKEN = \"\(Self.canary)\"\n[shell_environment_policy]\nset = { API_KEY = \"\(Self.canary)\" }\n")
        var seen: [String] = []
        func keep(_ value: Any) { seen.append(String(describing: value)) }
        keep(try sb.store.listRules(RuleScope.scopes(for: proj)))
        keep(Rules.capabilityGrid(try sb.store.listRules(RuleScope.scopes(for: proj)).rules))
        keep(try sb.store.previewSetCapability(scope: .global, capability: .run, verdict: .ask))
        let added = try sb.store.addRule(scope: .global, verdict: .deny, rule: "Bash(rm *)")
        keep(added)
        keep(try sb.store.changeVerdict(scope: .global, rule: "Bash(rm *)", from: .deny, to: .ask))
        keep(try sb.store.setCapability(scope: .project(proj), capability: .network, verdict: .deny) as Any)
        keep(try sb.store.removeRule(scope: .global, verdict: .ask, rule: "Bash(rm *)"))
        keep(Journal.history(sb.roots))
        keep(CodexPermissions.read(roots: sb.roots))
        try sb.home.write(".claude/settings.json", "{\"env\":{\"T\":\"\(Self.canary)\"")
        seen.append(refusal { try sb.store.addRule(scope: .global, verdict: .allow, rule: "Read") }?.message ?? "")
        seen.append(refusal { try Journal.undo(sb.roots, id: added.id) }?.message ?? "") // hand-edited, so undo refuses
        #expect(seen.count > 8 && seen.allSatisfy { !$0.isEmpty })
        for text in seen { #expect(!text.contains(Self.canary)) }
        #expect(!sb.journalText().contains(Self.canary))
        // the backup of the old bytes is a file in the app trash, not in the journal
        #expect(!sb.journalText().contains("TOKEN"))
    }

    @Test("all writes stay inside the temporary HOME (REINS_TEST=1)")
    func staysInTempHome() throws {
        let sb = try Sandbox()
        #expect(ProcessInfo.processInfo.environment["REINS_TEST"] == "1")
        let real = Roots.resolvedPath(Roots.realHomeDirectory())
        for url in [sb.roots.claude.root, sb.roots.codex.root, sb.roots.data] { #expect(!Roots.resolvedPath(url.path).hasPrefix(real + "/")) }
        #expect(sb.roots.claude.hookFile.path.hasPrefix(sb.home.root.path))
    }

    // MARK: Codex

    private func readCodex(_ config: String?, rules: [String: String] = [:]) throws -> CodexPermissions {
        let home = try TempHome()
        try FileManager.default.createDirectory(at: home.codex, withIntermediateDirectories: true)
        if let config { try home.write(".codex/config.toml", config) }
        for (name, text) in rules { try home.write(".codex/rules/\(name)", text) }
        return CodexPermissions.read(roots: try Roots.resolve(env: home.env))
    }

    @Test("Codex reader: legacy model, comments, multi-line arrays, inline tables, and nothing from mcp or env tables")
    func codexLegacy() throws {
        let c = try readCodex("""
        # comment
        approval_policy = "never"   # trailing comment
        sandbox_mode = "danger-full-access"
        approvals_reviewer = "user"
        model = "demo-model"
        developer_instructions = \"\"\"
        approval_policy = "on-request"
        [permissions.fake]
        \"\"\"

        [sandbox_workspace_write]
        network_access = true
        writable_roots = [
          "/tmp/a",
          "/tmp/b", # note
        ]

        [projects."/work/app"]
        trust_level = "trusted"

        [projects."/work/weird]path"]
        trust_level = "untrusted"

        [projects]
        "/work/inline" = { trust_level = "trusted" }

        [mcp_servers.github]
        command = "npx"
        [mcp_servers.github.env]
        GITHUB_TOKEN = "\(Self.canary)"

        [shell_environment_policy]
        set = { API_KEY = "\(Self.canary)" }
        """, rules: ["default.rules": """
        # prefix_rule(pattern=["x"], decision="forbidden")
        prefix_rule(pattern=["git", "status"], decision="allow")
        prefix_rule(
          pattern=["rm"],
          decision="forbidden",
        )
        prefix_rule(pattern=["curl", "\(Self.canary)"], decision="prompt")
        prefix_rule(pattern=["ls"])
        """])
        #expect(c.present && c.model == .legacy && c.unrestricted)
        #expect(c.approvalPolicy == .mode("never") && c.sandboxMode == "danger-full-access" && c.approvalsReviewer == "user")
        #expect(c.sandboxWorkspaceWrite == CodexSandboxWorkspaceWrite(networkAccess: true, writableRoots: ["/tmp/a", "/tmp/b"]))
        #expect(c.projects == [
            CodexProject(path: "/work/app", trustLevel: "trusted"), CodexProject(path: "/work/weird]path", trustLevel: "untrusted"),
            CodexProject(path: "/work/inline", trustLevel: "trusted"),
        ])
        #expect(c.profiles.isEmpty && c.warnings.isEmpty)
        #expect(c.rules == CodexRulesSummary(files: 1, allow: 2, prompt: 1, forbidden: 1, other: 0))
        #expect(!String(describing: c).contains(Self.canary), "nothing from mcp_servers, env tables or rule patterns")
    }

    @Test("Codex reader: profiles model, granular approval policy, and a missing config")
    func codexProfiles() throws {
        let missing = try readCodex(nil)
        #expect(!missing.present && missing.model == .legacy && !missing.unrestricted && missing.profiles.isEmpty && missing.projects.isEmpty)
        #expect(missing.rules == CodexRulesSummary())

        let c = try readCodex("""
        default_permissions = "dev"

        [approval_policy.granular]
        sandbox_approval = true
        rules = false

        [permissions.dev.filesystem]
        "/tmp" = "write"
        "~/.ssh" = "none"

        [permissions.dev.network]
        enabled = true
        mode = "limited"

        [permissions.strict.filesystem]
        "/" = "read"
        """)
        #expect(c.model == .profiles && c.defaultPermissions == "dev" && c.sandboxMode == nil && !c.unrestricted)
        #expect(c.approvalPolicy == .granular([JSONMember("sandbox_approval", true), JSONMember("rules", false)]))
        #expect(c.profiles == [
            CodexProfile(name: "dev", filesystemEntries: 2, networkEntries: 2, networkFlags: [JSONMember("enabled", true), JSONMember("mode", "limited")]),
            CodexProfile(name: "strict", filesystemEntries: 1, networkEntries: 0, networkFlags: []),
        ])
        #expect(c.sandboxWorkspaceWrite == nil)
    }

    @Test("Codex reader: both models set warns")
    func codexBoth() throws {
        let c = try readCodex("""
        default_permissions = "dev"
        sandbox_mode = "workspace-write"
        approval_policy = { granular = { rules = true } }
        [permissions.dev.network]
        enabled = false
        """)
        #expect(c.model == .both && c.warnings.count == 1 && c.warnings[0].contains("default_permissions and sandbox_mode"))
        #expect(!c.unrestricted)
        #expect(c.approvalPolicy == .granular([JSONMember("rules", true)]))
    }
}
