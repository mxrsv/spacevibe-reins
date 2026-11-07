import Foundation
import Testing
@testable import ReinsCore

// Every test runs on a TempHome (SPACEVIBE_TEST=1 makes Roots refuse a root under the real home). The golden replay copies the
// synthetic fixture HOME into one, runs each operation the Node core ran (golden/mutate.json), and compares.
@Suite("Mutate")
struct MutateTests {
    static let canary = "fixture-secret-do-not-show"
    static let golden: [String: Any] = ((try? FixtureHome.golden("mutate")) as? [String: Any]) ?? [:]
    static let scenarios: [[String: Any]] = golden["scenarios"] as? [[String: Any]] ?? []
    static let scenarioNames: [String] = scenarios.compactMap { $0["name"] as? String }
    static let hookFiles: Set<String> = Set(golden["hookFiles"] as? [String] ?? [])

    /// A golden that fails to load turns every parametrized case into zero cases, which passes. This one fails instead.
    @Test("the golden loaded: 37 or more Node scenarios are replayed")
    func goldenLoaded() {
        #expect(!Self.golden.isEmpty, "golden/mutate.json did not load")
        #expect(Self.scenarioNames.count >= 37, "only \(Self.scenarioNames.count) scenarios")
        #expect(!Self.hookFiles.isEmpty)
    }

    // MARK: Helpers

    /// A TempHome holding a private copy of the fixture HOME, with `Roots` pointing at it.
    private struct Copy {
        let home: TempHome
        let roots: Roots
        var root: String { home.root.path }

        init() throws {
            home = try TempHome()
            try FixtureHome.materialize(into: home.root)
            roots = try home.roots
        }

        func read(_ relative: String) throws -> String { try String(contentsOf: home.url(relative), encoding: .utf8) }
        func tree() throws -> [String: String] { try TreeHash.measure(home.root, root: root, skipTop: [".reins", ".spacevibe", ".fixture-stamp"]) }
    }

    /// Path -> sha1 of the text with the copy's root replaced by `$HOME` (the hashing the frozen goldens (SV5), last generated at b58269d3f3eb, used).
    private enum TreeHash {
        static func sha1(_ text: String) -> String {
            Sha1.digest(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        static func measure(_ dir: URL, root: String, skipTop: Set<String> = []) throws -> [String: String] {
            var out: [String: String] = [:]
            func visit(_ url: URL, _ prefix: String) throws {
                let fm = FileManager.default
                for name in try fm.contentsOfDirectory(atPath: url.path).sorted() {
                    let relative = prefix.isEmpty ? name : prefix + "/" + name
                    if prefix.isEmpty, skipTop.contains(name) { continue }
                    let child = url.appendingPathComponent(name)
                    let type = try fm.attributesOfItem(atPath: child.path)[.type] as? FileAttributeType
                    if type == .typeSymbolicLink {
                        out[relative] = "link:" + (try fm.destinationOfSymbolicLink(atPath: child.path)).replacingOccurrences(of: root, with: FixtureHome.token)
                    } else if type == .typeDirectory {
                        try visit(child, relative)
                    } else {
                        let text = String(decoding: try Data(contentsOf: child), as: UTF8.self)
                        out[relative] = sha1(text.replacingOccurrences(of: root, with: FixtureHome.token))
                    }
                }
            }
            try visit(dir, "")
            return out
        }

        /// What the trash holds, as sorted "<path inside the slot>:<sha1>".
        static func trash(_ data: URL, root: String) throws -> [String] {
            let folder = data.appendingPathComponent("trash")
            guard let slots = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
            return try slots.flatMap { slot in
                try measure(folder.appendingPathComponent(slot), root: root).map { "\($0.key):\($0.value)" }
            }.sorted()
        }
    }

    private func applySetup(_ setup: [String: Any]?, in copy: Copy) throws {
        guard let setup else { return }
        let token = FixtureHome.token
        for relative in setup["remove"] as? [String] ?? [] { try FileManager.default.removeItem(at: copy.home.url(relative)) }
        for (relative, text) in (setup["files"] as? [String: String] ?? [:]).sorted(by: { $0.key < $1.key }) {
            try copy.home.write(relative, text.replacingOccurrences(of: token, with: copy.root))
        }
        for (relative, target) in (setup["links"] as? [String: String] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let link = copy.home.url(relative)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.replacingOccurrences(of: token, with: copy.root))
        }
    }

    private func itemID(_ find: [String: Any], roots: Roots) throws -> String {
        if let id = find["id"] as? String { return id }
        let snapshot = Inventory.read(roots: roots)
        if find["kind"] as? String == "hook" {
            let hook = snapshot.hooks.first {
                $0.cli.rawValue == find["cli"] as? String && $0.event == find["event"] as? String
                    && $0.command.contains(find["commandIncludes"] as? String ?? "")
            }
            return try #require(hook, "no hook for \(find)").id
        }
        let item = snapshot.items.first {
            $0.kind.rawValue == find["kind"] as? String && $0.cli.rawValue == find["cli"] as? String && $0.name == find["name"] as? String
        }
        return try #require(item, "no item for \(find)").id
    }

    private func perform(_ op: [String: Any], in copy: Copy) throws -> JournalEntry {
        let roots = copy.roots
        let clis = (op["clis"] as? [String] ?? []).compactMap(InventoryCLI.init(rawValue:))
        let text = { (key: String) in op[key] as? String ?? "" }
        switch op["fn"] as? String {
        case "addSkill":
            return try Mutate.addSkill(roots: roots, clis: clis, name: text("name"), description: text("description"), body: text("body"))
        case "addAgent":
            return try Mutate.addAgent(roots: roots, clis: clis, name: text("name"), description: text("description"), instructions: text("instructions"))
        case "addHook":
            return try Mutate.addHook(
                roots: roots, clis: clis, event: text("event"), matcher: op["matcher"] as? String,
                command: text("command").replacingOccurrences(of: FixtureHome.token, with: copy.root), timeout: (op["timeout"] as? NSNumber)?.doubleValue
            )
        case "removeItem":
            return try Mutate.removeItem(roots: roots, id: itemID(op["find"] as? [String: Any] ?? [:], roots: roots))
        case "removeDeadHooks":
            return try Mutate.removeDeadHooks(roots: roots, cli: try #require(InventoryCLI(rawValue: text("cli"))))
        case "copyToOther":
            return try Mutate.copyToOther(roots: roots, id: itemID(op["find"] as? [String: Any] ?? [:], roots: roots))
        default:
            throw ReinsError("test bug: unknown operation")
        }
    }

    /// The journal entry as the golden records it: label and ops without the keys that name trash paths or hold Swift-only restore data.
    private func summary(_ entry: JournalEntry, root: String) throws -> Any {
        let dropped: Set<String> = ["to", "backup", "after", "restore"]
        let ops = entry.ops.map { op -> JSONValue in
            .object((op.json.objectValue ?? []).filter { !dropped.contains($0.key) })
        }
        let value = JSONValue.object([JSONMember("label", .string(entry.label)), JSONMember("ops", .array(ops))])
        let text = try OrderedJSON.pretty(value)
        return FixtureHome.normalize(try JSONSerialization.jsonObject(with: Data(text.utf8)), root: URL(fileURLWithPath: root))
    }

    private func parsedJSON(_ copy: Copy, _ relative: String) throws -> Any {
        FixtureHome.normalize(try JSONSerialization.jsonObject(with: Data(contentsOf: copy.home.url(relative))), root: copy.home.root)
    }

    private func settings(_ copy: Copy) throws -> JSONValue { try OrderedJSON(text: copy.read(".claude/settings.json")).root }

    // MARK: Golden replay

    @Test("the fixture copy hashes like the Node copy")
    func initialTree() throws {
        let copy = try Copy()
        let expected = try #require(Self.golden["initial"] as? [String: Any])
        #expect(FixtureHome.firstDifference(try copy.tree(), expected) == nil)
    }

    @Test("an operation does what the Node core does, and undo puts every byte back", arguments: MutateTests.scenarioNames)
    func replay(name: String) throws {
        let scenario = try #require(Self.scenarios.first { $0["name"] as? String == name })
        let copy = try Copy()
        try applySetup(scenario["setup"] as? [String: Any], in: copy)
        let before = try copy.tree()

        var entry: JournalEntry?
        var failure: ReinsError?
        do { entry = try perform(try #require(scenario["op"] as? [String: Any]), in: copy) } catch let error as ReinsError { failure = error }
        let after = try copy.tree()

        // The outcome: an error with the Node status and wording, or a journal entry with the Node label and ops.
        if let expected = scenario["error"] as? [String: Any] {
            #expect(failure?.status == expected["status"] as? Int, "\(name) status")
            #expect(failure?.message.replacingOccurrences(of: copy.root, with: FixtureHome.token) == expected["message"] as? String, "\(name) message")
            #expect(before == after, "\(name): a refused operation must change nothing")
        } else {
            #expect(failure == nil, "\(name) failed: \(failure?.message ?? "")")
            let entry = try #require(entry)
            let diff = FixtureHome.firstDifference(try summary(entry, root: copy.root), scenario["journal"] ?? NSNull())
            #expect(diff == nil, "\(name) journal differs at \(diff ?? "")")
        }

        // The files: same changed set; skills and agents byte for byte, the two hook files as parsed JSON.
        var changed: [String: Any] = [:]
        for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
            changed[key] = after[key].map { Self.hookFiles.contains(key) ? "json" : $0 } ?? NSNull()
        }
        let deltaDiff = FixtureHome.firstDifference(changed, scenario["delta"] as? [String: Any] ?? [:])
        #expect(deltaDiff == nil, "\(name) file changes differ at \(deltaDiff ?? "")")
        let expectedJSON = scenario["json"] as? [String: Any] ?? [:]
        let expectedBody = scenario["body"] as? [String: Any] ?? [:]
        for (relative, node) in expectedJSON {
            let diff = FixtureHome.firstDifference(try parsedJSON(copy, relative), node)
            #expect(diff == nil, "\(name) \(relative) differs at \(diff ?? "")")
            // Node re-prints the whole file with a final newline; where the file was already pretty-printed the bytes agree without it.
            let body = try #require(expectedBody[relative] as? [String: Any])
            if body["wasPretty"] as? Bool == true {
                var text = try copy.read(relative).replacingOccurrences(of: copy.root, with: FixtureHome.token)
                if text.utf8.last == 0x0A { text.removeLast() }
                #expect(TreeHash.sha1(text) == body["bodySha1"] as? String, "\(name) \(relative) bytes differ from the Node output")
            }
        }
        let trash = try TreeHash.trash(copy.roots.data, root: copy.root)
        #expect(trash == scenario["trash"] as? [String] ?? [], "\(name) trash")

        // The journal never holds a secret from settings, whatever the operation did.
        let journalText = (try? String(contentsOf: copy.roots.data.appendingPathComponent("journal.json"), encoding: .utf8)) ?? ""
        #expect(!journalText.contains(Self.canary) && !(failure?.message.contains(Self.canary) ?? false))

        // Undo: every byte of the tree comes back, and a second undo is refused.
        if let entry {
            let undone = try Journal.undo(copy.roots, id: entry.id)
            #expect(undone == entry.label)
            #expect(try copy.tree() == before, "\(name): undo did not restore the tree")
            let second = #expect(throws: ReinsError.self) { try Journal.undo(copy.roots, id: entry.id) }
            #expect(second?.status == 409 && second?.message == "This was already undone.")
        }
    }

    // MARK: Behavior the golden does not cover

    @Test("removing a linked skill leaves its target; undo makes the link again")
    func linkedSkill() throws {
        let copy = try Copy()
        try copy.home.write("shared/linked/SKILL.md", "---\nname: linked\ndescription: shared\n---\n")
        try FileManager.default.createSymbolicLink(atPath: copy.home.url(".claude/skills/linked").path, withDestinationPath: copy.home.url("shared/linked").path)
        let id = try #require(Inventory.read(roots: copy.roots).items.first { $0.name == "linked" }).id
        let entry = try Mutate.removeItem(roots: copy.roots, id: id)
        #expect(entry.ops.map(\.type) == ["link-removed"])
        #expect(FileManager.default.fileExists(atPath: copy.home.url("shared/linked/SKILL.md").path))
        _ = try Journal.undo(copy.roots, id: entry.id)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copy.home.url(".claude/skills/linked").path) == copy.home.url("shared/linked").path)
    }

    @Test("a removed skill folder is in the app trash with its bytes, not deleted")
    func removedGoesToTrash() throws {
        let copy = try Copy()
        let original = try copy.read(".claude/skills/tdd/SKILL.md")
        let id = try #require(Inventory.read(roots: copy.roots).items.first { $0.name == "tdd" && $0.cli == .claude }).id
        let entry = try Mutate.removeItem(roots: copy.roots, id: id)
        let moved = try #require(entry.ops.first?.json["to"]?.stringValue)
        #expect(moved.hasPrefix(copy.roots.data.appendingPathComponent("trash").path))
        #expect(try String(contentsOfFile: moved + "/SKILL.md", encoding: .utf8) == original)
    }

    @Test("project-scoped and plugin-owned items are read-only (403)")
    func readOnlyItems() throws {
        let copy = try Copy()
        try copy.home.write("work/spacevibe-bench/.claude/skills/proj-skill/SKILL.md", "---\nname: proj-skill\ndescription: p\n---\n")
        try copy.home.write("work/spacevibe-bench/.claude/settings.json", "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo project\"}]}]}}")
        let snapshot = Inventory.read(roots: copy.roots)
        let skill = try #require(snapshot.items.first { $0.name == "proj-skill" })
        let hook = try #require(snapshot.hooks.first { $0.command == "echo project" })
        let plugin = try #require(snapshot.items.first { $0.name == "neon-postgres" })
        #expect(skill.scope == .project && !skill.removable && hook.scope == .project)
        let before = try copy.tree()
        for (id, text) in [(skill.id, "project folder"), (hook.id, "project folder"), (plugin.id, "belongs to a plugin")] {
            let error = #expect(throws: ReinsError.self) { try Mutate.removeItem(roots: copy.roots, id: id) }
            #expect(error?.status == 403 && error?.message.contains(text) == true)
        }
        #expect(try copy.tree() == before)
        // Reading is allowed: a project skill can be copied into the other CLI.
        let entry = try Mutate.copyToOther(roots: copy.roots, id: skill.id)
        #expect(entry.label == "Copied skill proj-skill to Codex")
    }

    @Test("names: only lowercase letters, digits and dashes, 1 to 64 characters")
    func nameRules() throws {
        let copy = try Copy()
        for name in ["../evil", "a/b", ".hidden", "UP", "", "-lead", "has space", String(repeating: "a", count: 65)] {
            let error = #expect(throws: ReinsError.self) { try Mutate.addSkill(roots: copy.roots, clis: [.claude], name: name, description: "x") }
            #expect(error?.status == 400 && error?.message == "Use lowercase letters, numbers and dashes for the name.", "\(name)")
            #expect(throws: ReinsError.self) { try Mutate.addAgent(roots: copy.roots, clis: [.codex], name: name, description: "x") }
        }
        _ = try Mutate.addSkill(roots: copy.roots, clis: [.claude], name: "9" + String(repeating: "a", count: 63), description: "x")
        _ = try Mutate.addSkill(roots: copy.roots, clis: [.claude], name: "a-b-9", description: "x")
    }

    @Test("a name that exists in the second CLI leaves nothing behind in the first")
    func existingNameInSecondCLI() throws {
        let copy = try Copy()
        try copy.home.write(".codex/skills/codex-only/SKILL.md", "---\nname: codex-only\ndescription: c\n---\n")
        try copy.home.write(".claude/agents/dup.md", "---\nname: dup\ndescription: d\n---\n")
        let before = try copy.tree()
        let skill = #expect(throws: ReinsError.self) { try Mutate.addSkill(roots: copy.roots, clis: [.claude, .codex], name: "codex-only", description: "x") }
        #expect(skill?.status == 409 && skill?.message == "Codex already has a skill named codex-only.")
        let agent = #expect(throws: ReinsError.self) { try Mutate.addAgent(roots: copy.roots, clis: [.codex, .claude], name: "dup", description: "x") }
        #expect(agent?.status == 409)
        #expect(try copy.tree() == before)
        #expect(Journal.history(copy.roots).isEmpty)
    }

    @Test("hooks: a failure on the second CLI puts the first file back and records nothing")
    func hookRollback() throws {
        let copy = try Copy()
        try copy.home.write(".codex/hooks.json", "{broken")
        let before = try copy.tree()
        let error = #expect(throws: ReinsError.self) { try Mutate.addHook(roots: copy.roots, clis: [.claude, .codex], event: "Stop", command: "echo x") }
        #expect(error?.status == 409)
        #expect(try copy.tree() == before)
        #expect(Journal.history(copy.roots).isEmpty)
    }

    @Test("hooks: validation wording and the per-CLI event list")
    func hookValidation() throws {
        let copy = try Copy()
        func fails(_ clis: [InventoryCLI], _ event: String, _ command: String, _ message: String) {
            let error = #expect(throws: ReinsError.self) { try Mutate.addHook(roots: copy.roots, clis: clis, event: event, command: command) }
            #expect(error?.status == 400 && error?.message == message, "\(message)")
        }
        fails([.claude], "Stop", "   ", "Enter the command this hook runs.")
        fails([], "Stop", "echo", "Pick at least one CLI.")
        fails([.codex], "TeammateIdle", "echo", "Codex has no TeammateIdle event.")
        fails([.claude, .codex], "PostToolUseFailure", "echo", "Codex has no PostToolUseFailure event.")
        #expect(Journal.history(copy.roots).isEmpty)
    }

    @Test("copying a hook: into Claude Code when it knows the event, never into Codex")
    func copyHook() throws {
        let copy = try Copy()
        try copy.home.write(".codex/hooks.json", "{\"hooks\":{\"Interrupt\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo bye\"}]}],\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo stop-from-codex\"}]}]}}")
        let snapshot = Inventory.read(roots: copy.roots)
        let interrupt = try #require(snapshot.hooks.first { $0.command == "echo bye" })
        let stop = try #require(snapshot.hooks.first { $0.command == "echo stop-from-codex" })
        let claudeHook = try #require(snapshot.hooks.first { $0.cli == .claude && $0.event == "SessionStart" })

        let unknown = #expect(throws: ReinsError.self) { try Mutate.copyToOther(roots: copy.roots, id: interrupt.id) }
        #expect(unknown?.message == "Claude Code has no Interrupt event.")
        let toCodex = #expect(throws: ReinsError.self) { try Mutate.copyToOther(roots: copy.roots, id: claudeHook.id) }
        #expect(toCodex?.status == 400 && toCodex?.message == "Reins does not copy hooks into Codex.")

        let entry = try Mutate.copyToOther(roots: copy.roots, id: stop.id)
        #expect(entry.label == "Added Stop hook to Claude Code")
        #expect(Inventory.read(roots: copy.roots).hooks.contains { $0.cli == .claude && $0.command == "echo stop-from-codex" })
    }

    @Test("a copied skill is a new item: its files are not older than the copy")
    func copiedSkillIsFresh() throws {
        let copy = try Copy()
        let source = try #require(Inventory.read(roots: copy.roots).items.first { $0.cli == .claude && $0.kind == .skill && $0.removable })
        let old = Date(timeIntervalSince1970: 1_577_836_800)
        let sourceFolder = URL(fileURLWithPath: source.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: sourceFolder.appendingPathComponent("SKILL.md").path)
        _ = try Mutate.copyToOther(roots: copy.roots, id: source.id)
        let target = try #require(Inventory.read(roots: copy.roots).items.first { $0.cli == .codex && $0.name == source.name })
        let attrs = try FileManager.default.attributesOfItem(atPath: URL(fileURLWithPath: target.path).appendingPathComponent("SKILL.md").path)
        let modified = try #require(attrs[.modificationDate] as? Date)
        #expect(Date().timeIntervalSince(modified) < 120)
    }

    @Test("an agent keeps its quotes and backslashes through markdown and TOML")
    func agentRoundTrip() throws {
        let copy = try Copy()
        let instructions = "Say \"hi\" \\ always.\nSecond line."
        _ = try Mutate.addAgent(roots: copy.roots, clis: [.claude], name: "round", description: "Reads \"quotes\" and \\ slashes", instructions: instructions)
        let toCodex = try Mutate.copyToOther(roots: copy.roots, id: try #require(Inventory.read(roots: copy.roots).items.first { $0.name == "round" && $0.cli == .claude }).id)
        #expect(toCodex.label == "Copied agent round to Codex")
        let toml = try copy.read(".codex/agents/round.toml")
        #expect(MutateText.tomlInstructions(toml) == instructions)
        #expect(Inventory.tomlFields(toml)["description"] == "Reads \"quotes\" and \\ slashes")
        // And back: a Codex-only agent becomes a Claude Code file with the same words.
        try FileManager.default.removeItem(at: copy.home.url(".claude/agents/round.md"))
        _ = try Mutate.copyToOther(roots: copy.roots, id: try #require(Inventory.read(roots: copy.roots).items.first { $0.name == "round" && $0.cli == .codex }).id)
        let markdown = try copy.read(".claude/agents/round.md")
        #expect(Frontmatter.parse(markdown)["description"] == "Reads \"quotes\" and \\ slashes")
        #expect(MutateText.stripHeader(markdown).trimmingCharacters(in: .whitespacesAndNewlines) == instructions)
    }

    @Test("JavaScript trim and whitespace collapse")
    func jsText() {
        #expect(ActivityText.trim("\u{00A0} a b \u{FEFF}\n") == "a b")
        #expect(MutateText.yamlValue("  one\t\ttwo \n three\u{2003}") == "\"one two three\"")
        #expect(ActivityText.trim(" \u{200B}x") == "\u{200B}x")
    }

    // MARK: Hook undo

    @Test("undo when the file changed since: the hook is reversed, the hand edit and the secrets stay")
    func undoAfterHandEdit() throws {
        let copy = try Copy()
        let deadBefore = Inventory.read(roots: copy.roots).hooks.filter(\.dead).count
        let entry = try Mutate.removeDeadHooks(roots: copy.roots, cli: .claude)
        #expect(entry.ops.count == 2)
        #expect(Inventory.read(roots: copy.roots).hooks.filter(\.dead).isEmpty)

        // A change by hand after the removal: the exact bytes no longer match, so undo must re-add the hooks only.
        let file = copy.home.url(".claude/settings.json")
        let edited = try OrderedJSON(data: Data(contentsOf: file)).setting(["model"], to: "by-hand")
        try edited.data.write(to: file)
        _ = try Journal.undo(copy.roots, id: entry.id)

        #expect(Inventory.read(roots: copy.roots).hooks.filter(\.dead).count == deadBefore)
        let now = try settings(copy)
        #expect(now["model"]?.stringValue == "by-hand")
        #expect(now["env"]?["EXAMPLE_TOKEN"]?.stringValue == Self.canary)
    }

    @Test("undo of one hook while a later hook stays")
    func undoOlderHook() throws {
        let copy = try Copy()
        let first = try Mutate.addHook(roots: copy.roots, clis: [.claude], event: "Stop", command: "echo first")
        let second = try Mutate.addHook(roots: copy.roots, clis: [.claude], event: "Stop", command: "echo second", timeout: 3)
        _ = try Journal.undo(copy.roots, id: first.id)
        var commands = Inventory.read(roots: copy.roots).hooks.map(\.command)
        #expect(!commands.contains("echo first") && commands.contains("echo second"))
        _ = try Journal.undo(copy.roots, id: second.id)
        commands = Inventory.read(roots: copy.roots).hooks.map(\.command)
        #expect(!commands.contains("echo second"))
        #expect(try settings(copy)["env"]?["EXAMPLE_TOKEN"]?.stringValue == Self.canary)
    }

    @Test("hook ops written by the Node core (no restore data) are undone by editing the hooks")
    func undoNodeHookOps() throws {
        let home = try TempHome()
        let roots = try home.roots
        let file = home.url(".claude/settings.json")
        try home.write(".claude/settings.json", "{\n  \"env\": {\"T\": \"\(Self.canary)\"},\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          { \"type\": \"command\", \"command\": \"echo kept\" },\n          { \"type\": \"command\", \"command\": \"echo added\", \"timeout\": 5 }\n        ]\n      }\n    ]\n  }\n}")
        try home.write(".spacevibe/journal.json", """
        [
          { "id": "aaaaaaaa-0000-0000-0000-000000000001", "at": "2026-11-02T10:00:00.000Z", "label": "Added Stop hook to Claude Code",
            "ops": [ { "type": "hook-added", "file": "\(file.path)", "event": "Stop", "matcher": null, "hook": { "type": "command", "command": "echo added", "timeout": 5 } } ] },
          { "id": "aaaaaaaa-0000-0000-0000-000000000002", "at": "2026-11-02T09:00:00.000Z", "label": "Removed Edit hook from Claude Code",
            "ops": [ { "type": "hook-removed", "file": "\(file.path)", "event": "PreToolUse", "matcher": "Edit", "hook": { "type": "command", "command": "echo gone" } } ] }
        ]
        """)
        #expect(try Journal.undo(roots, id: "aaaaaaaa-0000-0000-0000-000000000001") == "Added Stop hook to Claude Code")
        #expect(try Journal.undo(roots, id: "aaaaaaaa-0000-0000-0000-000000000002") == "Removed Edit hook from Claude Code")
        let commands = Inventory.read(roots: roots).hooks.map(\.command).sorted()
        #expect(commands == ["echo gone", "echo kept"])
        let hooks = try OrderedJSON(data: Data(contentsOf: file)).root
        #expect(hooks["hooks"]?["PreToolUse"]?[0]?["matcher"]?.stringValue == "Edit")
        #expect(hooks["env"]?["T"]?.stringValue == Self.canary)
    }

    // MARK: Secrets

    @Test("no error or label quotes a secret from settings, even when the file is broken")
    func canaryNeverLeaks() throws {
        let copy = try Copy()
        try copy.home.write(".claude/settings.json", "{\"env\": {\"T\": \"\(Self.canary)\"}, \"hooks\": ")
        let broken = #expect(throws: ReinsError.self) { try Mutate.addHook(roots: copy.roots, clis: [.claude], event: "Stop", command: "echo x") }
        #expect(broken?.status == 409 && broken?.message.contains(Self.canary) == false)
        let raw = try copy.read(".claude/settings.json")
        #expect(raw.contains(Self.canary))

        try copy.home.write(".claude/settings.json", "{\"env\": {\"T\": \"\(Self.canary)\"}, \"hooks\": {\"Stop\": 7}}")
        let layout = #expect(throws: ReinsError.self) { try Mutate.addHook(roots: copy.roots, clis: [.claude], event: "Stop", command: "echo x") }
        #expect(layout?.status == 409 && layout?.message.contains(Self.canary) == false)

        try copy.home.write(".claude/settings.json", "{\"env\": {\"T\": \"\(Self.canary)\"}}")
        let entry = try Mutate.addHook(roots: copy.roots, clis: [.claude], event: "Stop", command: "echo x")
        let journal = try String(contentsOf: copy.roots.data.appendingPathComponent("journal.json"), encoding: .utf8)
        #expect(!journal.contains(Self.canary) && !entry.label.contains(Self.canary))
        #expect(try copy.read(".claude/settings.json").contains(Self.canary))
    }
}
