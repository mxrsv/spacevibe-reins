import Foundation
import Testing
@testable import ReinsCore

/// Temp HOME only (TempHome / the shared fixture tree). The real home is never read.
private func roots(_ home: TempHome) throws -> Roots { try Roots.resolve(env: home.env) }

private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}

private func setModified(_ url: URL, _ iso: String) throws {
    let date = try #require(ISO8601DateFormatter().date(from: iso))
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

private func skillFile(_ name: String, _ description: String = "d") -> String { "---\nname: \(name)\ndescription: \(description)\n---\n" }

private func hookConfig(_ event: String, _ command: String, secret: String? = nil) -> String {
    let env = secret.map { "\"env\": {\"API_TOKEN\": \"\($0)\"}, " } ?? ""
    return "{\(env)\"hooks\": {\"\(event)\": [{\"matcher\": \"Edit\", \"hooks\": [{\"type\": \"command\", \"command\": \(String(decoding: (try? JSONEncoder().encode(command)) ?? Data(), as: UTF8.self))}]}]}}"
}

@Suite("Inventory")
struct InventoryTests {
    // MARK: hashing and script paths

    @Test("sha is the first 12 hex digits of SHA-1 (known vector)")
    func shaVector() {
        #expect(Inventory.sha("abc") == "a9993e364706")
        #expect(Inventory.sha("") == "da39a3ee5e6b")
        #expect(Inventory.sha(String(repeating: "a", count: 1000)) == "291e9a6c66994949b57ba5e650361e98fc36b1ba".prefix(12).description)
    }

    @Test("bare drops the plugin prefix")
    func bareName() {
        #expect(Inventory.bare("neon:neon-postgres") == "neon-postgres")
        #expect(Inventory.bare("plain") == "plain")
    }

    @Test("scriptPaths finds quoted and bare absolute script paths and nothing else")
    func scriptPaths() {
        #expect(Inventory.scriptPaths("sh '/a/b/c.sh'") == ["/a/b/c.sh"])
        #expect(Inventory.scriptPaths("node \"/x/y.mjs\" --flag") == ["/x/y.mjs"])
        #expect(Inventory.scriptPaths("/usr/bin/env python3 /opt/t/run.py") == ["/opt/t/run.py"])
        #expect(Inventory.scriptPaths("echo hi") == [])
        #expect(Inventory.scriptPaths("cat /etc/hosts") == [])
        #expect(Inventory.scriptPaths("sh /a.sh && sh /a.sh; sh /b.bash") == ["/a.sh", "/b.bash"])
        #expect(Inventory.scriptPaths("sh \"$HOME/x.sh\"") == [])
    }

    // MARK: golden parity

    @Test("the inventory with usage attached equals inventory.json from the Node core")
    func goldenParity() async throws {
        try FixtureHome.materialize()
        let temp = try TempHome()
        var env = FixtureHome.env
        env["REINS_HOME"] = temp.reins.path
        let r = try Roots.resolve(env: env)

        let snapshot = Inventory.read(roots: r)
        let result = try await UsageScanner(roots: r).scan()
        let input = UsageInput.ready(result)
        var attached = Inventory.attachUsage(snapshot, usage: input, now: try FixtureHome.now())
        attached.items.sort { $0.id < $1.id }
        attached.hooks.sort { $0.id < $1.id }
        let actual: [String: Any] = [
            "now": try FixtureHome.manifest().now,
            "usageInput": try jsonObject(input),
            "inventory": try jsonObject(attached),
            "filterCounts": try jsonObject(Inventory.filterCounts(items: attached.items, hooks: attached.hooks)),
        ]
        let expected = try FixtureHome.golden("inventory")
        let diff = FixtureHome.firstDifference(FixtureHome.normalize(actual), expected)
        #expect(diff == nil, "first difference: \(diff ?? "")")
    }

    // MARK: skills, agents, owners

    @Test("skills and agents of both CLIs: names, owners, symlinks, system folders, plugins")
    func itemsAndOwners() throws {
        let h = try TempHome()
        try h.write(".claude/skills/glob/SKILL.md", skillFile("glob", "global skill"))
        try h.write(".claude/skills/.hidden/SKILL.md", skillFile("hidden"))
        try h.write(".claude/skills/_internal/SKILL.md", skillFile("internal"))
        try h.write(".claude/skills/not-a-skill/README.md", "x")
        try h.write(".claude/skills/noname/SKILL.md", "no frontmatter at all")
        try h.write(".claude/agents/rev.md", "---\nname: rev\ndescription: reviews\n---\n")
        try h.write(".claude/agents/notes.txt", "x")
        try h.write(".codex/agents/helper.toml", "name = \"helper\"\ndescription = 'a toml agent'\ndeveloper_instructions = \"\"\"\nbody\n\"\"\"\n")
        try h.write(".codex/skills/glob/SKILL.md", skillFile("glob"))
        // A symlinked skill folder.
        try h.write("elsewhere/linked/SKILL.md", skillFile("linked"))
        try FileManager.default.createDirectory(at: h.claude.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: h.claude.appendingPathComponent("skills/linked"), withDestinationURL: h.url("elsewhere/linked"))
        // An enabled plugin with a skill, an agent and a hook.
        let plugin = h.url("plugins-cache/acme")
        try h.write("plugins-cache/acme/skills/acme-skill/SKILL.md", skillFile("acme-skill"))
        try h.write("plugins-cache/acme/agents/acme-agent.md", "---\nname: acme-agent\n---\n")
        try h.write("plugins-cache/acme/hooks/hooks.json", hookConfig("Stop", "echo plugin-hook"))
        try h.write(".claude/plugins/installed_plugins.json", "{\"plugins\": {\"acme@market\": [{\"installPath\": \"\(plugin.path)\"}], \"off@market\": [{\"installPath\": \"\(plugin.path)\"}]}}")
        try h.write(".claude/settings.json", "{\"enabledPlugins\": {\"acme@market\": true, \"off@market\": false}}")

        let inv = Inventory.read(roots: try roots(h))
        func item(_ name: String, cli: InventoryCLI = .claude) -> InventoryItem? { inv.items.first { $0.name == name && $0.cli == cli } }

        #expect(item("glob")?.description == "global skill")
        #expect(item("glob")?.owner == "user")
        #expect(item("glob")?.removable == true)
        #expect(item("glob")?.inOther == true)
        #expect(item("glob", cli: .codex)?.inOther == true)
        #expect(item("hidden") == nil && item("internal") == nil && item("not-a-skill") == nil)
        #expect(inv.items.first { $0.entry == "noname" }?.name == "noname", "name falls back to the folder name")
        #expect(item("linked")?.owner == "link")
        #expect(item("rev")?.kind == .agent)
        #expect(inv.items.contains { $0.entry == "notes.txt" } == false)
        #expect(item("helper", cli: .codex)?.description == "a toml agent")
        #expect(item("helper", cli: .codex)?.id == "codex:agent:local:helper.toml")
        // Plugins are read-only.
        #expect(item("acme-skill")?.owner == "acme")
        #expect(item("acme-skill")?.removable == false)
        #expect(item("acme-skill")?.id == "claude:skill:acme:acme-skill")
        #expect(item("acme-agent")?.removable == false)
        let pluginHook = try #require(inv.hooks.first { $0.command == "echo plugin-hook" })
        #expect(pluginHook.owner == "acme" && pluginHook.removable == false)
        #expect(inv.items.allSatisfy { $0.owner != "off" })
        #expect(inv.problems.isEmpty)
    }

    @Test("skillOverrides reach global Claude skills only")
    func overrides() throws {
        let h = try TempHome()
        try h.write(".claude/skills/a/SKILL.md", skillFile("a"))
        try h.write(".claude/skills/b/SKILL.md", skillFile("b"))
        try h.write(".codex/skills/a/SKILL.md", skillFile("a"))
        try h.write(".claude/settings.json", "{\"skillOverrides\": {\"a\": \"off\"}}")
        let inv = Inventory.read(roots: try roots(h))
        func item(_ name: String, _ cli: InventoryCLI) -> InventoryItem? { inv.items.first { $0.name == name && $0.cli == cli } }
        #expect(item("a", .claude)?.skillOverride == "off")
        #expect(item("a", .claude)?.hasSkillOverride == true)
        #expect(item("b", .claude)?.skillOverride == nil && item("b", .claude)?.hasSkillOverride == true)
        #expect(item("a", .codex)?.hasSkillOverride == false)
        let codexA = try #require(item("a", .codex))
        let claudeB = try #require(item("b", .claude))
        let encoded = try #require(jsonObject(codexA) as? [String: Any])
        #expect(encoded["override"] == nil)
        let encodedB = try #require(jsonObject(claudeB) as? [String: Any])
        #expect(encodedB["override"] is NSNull)
    }

    // MARK: hooks

    @Test("a hook is dead only when it names script paths and none exists; the hash is event plus command")
    func deadHooks() throws {
        let h = try TempHome()
        try h.write("bin/alive.sh", "#!/bin/sh\n")
        let commands = ["sh '\(h.url("bin/alive.sh").path)'", "sh '\(h.url("bin/gone.sh").path)'", "echo no-path", "sh '\(h.url("bin/gone.sh").path)' '\(h.url("bin/alive.sh").path)'"]
        let groups = commands.map { "{\"hooks\": [{\"type\": \"command\", \"command\": \(String(decoding: (try? JSONEncoder().encode($0)) ?? Data(), as: UTF8.self)), \"timeout\": 30, \"async\": true}]}" }
        try h.write(".claude/settings.json", "{\"hooks\": {\"Stop\": [\(groups.joined(separator: ","))]}}")
        let inv = Inventory.read(roots: try roots(h))
        #expect(inv.hooks.map(\.dead) == [false, true, false, false])
        let first = inv.hooks[0]
        #expect(first.hash == Inventory.sha("Stop|\(commands[0])"))
        #expect(first.timeout == 30 && first.async == true && first.matcher == nil)
        #expect(first.id == "claude:hook:" + Inventory.sha("|Stop||\(commands[0])"))
        #expect(inv.hooks[1].paths == [h.url("bin/gone.sh").path])
    }

    @Test("a duplicated event key counts once, with the last value, as JSON.parse has it")
    func duplicateKeys() throws {
        let h = try TempHome()
        let group = { (command: String) in "[{\"hooks\": [{\"type\": \"command\", \"command\": \"\(command)\"}]}]" }
        try h.write(".claude/settings.json", "{\"hooks\": {\"Stop\": \(group("echo first")), \"Stop\": \(group("echo last"))}}")
        let inv = Inventory.read(roots: try roots(h))
        #expect(inv.hooks.map(\.command) == ["echo last"])
    }

    @Test("hooks come from settings.json and hooks.json; a file that is not valid JSON is reported, not fatal")
    func invalidJSON() throws {
        let h = try TempHome()
        try h.write(".claude/settings.json", "{ not json")
        try h.write(".codex/hooks.json", hookConfig("Stop", "echo codex"))
        let inv = Inventory.read(roots: try roots(h))
        #expect(inv.hooks.map(\.cli) == [.codex])
        #expect(inv.problems.count == 1)
        #expect(inv.problems[0].contains("settings.json") && inv.problems[0].contains("not valid JSON"))
    }

    // MARK: projects

    @Test("projects come from Claude session logs and Codex project tables; worktrees, home and missing folders are skipped")
    func projects() throws {
        let h = try TempHome()
        let alpha = h.url("work/alpha").path
        let beta = h.url("work/beta").path
        func cwd(_ path: String) -> String { "{\"type\":\"user\",\"cwd\":\"\(path)\",\"timestamp\":\"2026-10-01T10:00:00Z\"}" }
        try h.write(".claude/skills/glob/SKILL.md", skillFile("glob"))
        try h.write(".claude/settings.json", hookConfig("Stop", "echo shared"))
        try h.write(".claude/projects/-enc-alpha/s1.jsonl", "{\"type\":\"file-history-snapshot\"}\n" + cwd(alpha))
        try h.write(".claude/projects/-enc-wt/s1.jsonl", cwd(alpha + "/.claude/worktrees/feature"))
        try h.write(".claude/projects/-enc-home/s1.jsonl", cwd(h.root.path))
        try h.write(".claude/projects/-enc-gone/s1.jsonl", cwd(h.url("work/deleted").path))
        try h.write("work/alpha/.claude/worktrees/feature/.claude/settings.json", hookConfig("Stop", "echo copy-in-worktree"))
        try h.write("work/alpha/.claude/skills/pskill/SKILL.md", skillFile("pskill", "project skill"))
        try h.write("work/alpha/.claude/agents/pagent.md", "---\nname: pagent\ndescription: project agent\n---\n")
        try h.write("work/alpha/.claude/settings.json", hookConfig("Stop", "echo shared"))
        try h.write("work/alpha/.claude/settings.local.json", hookConfig("PreToolUse", "sh '\(alpha)/gone.sh'"))
        try h.write(".codex/config.toml", "model = \"x\"\n[projects.\"\(beta)\"]\ntrust_level = \"trusted\"\n[projects.\"\(h.url("work/missing").path)\"]\ntrust_level = \"trusted\"\n")
        try h.write("work/beta/.claude/skills/bskill/SKILL.md", skillFile("bskill", "b"))

        let r = try roots(h)
        #expect(Inventory.discoverProjects(roots: r).sorted() == [alpha, beta].sorted())

        let inv = Inventory.read(roots: r)
        func item(_ name: String) -> InventoryItem? { inv.items.first { $0.name == name } }
        #expect(item("glob")?.scope == .global && item("glob")?.project == nil)
        #expect(item("pskill")?.scope == .project && item("pskill")?.project == alpha && item("pskill")?.kind == .skill)
        #expect(item("pskill")?.removable == false)
        #expect(item("pskill")?.id == "claude:skill:project:\(Inventory.sha(alpha)):pskill")
        #expect(item("pagent")?.kind == .agent)
        #expect(item("bskill")?.project == beta)
        let projectHooks = inv.hooks.filter { $0.project == alpha }
        #expect(projectHooks.map { [$0.event, String($0.file.dropFirst(alpha.count))] }.sorted { $0[0] < $1[0] } == [["PreToolUse", "/.claude/settings.local.json"], ["Stop", "/.claude/settings.json"]])
        #expect(projectHooks.first { $0.event == "PreToolUse" }?.dead == true)
        #expect(projectHooks.allSatisfy { $0.scope == .project && !$0.removable })
        #expect(inv.hooks.contains { $0.command == "echo copy-in-worktree" } == false)

        // The same hook in the global file and in a project: one hash, two ids.
        let same = inv.hooks.filter { $0.command == "echo shared" }
        #expect(same.count == 2)
        #expect(Set(same.map(\.hash)).count == 1)
        #expect(Set(same.map(\.id)).count == 2)
        #expect(same.first { $0.scope == .global }?.id.hasPrefix("claude:hook:") == true)
        #expect(Set(same.map(\.key)).count == 2, "different projects are different matrix rows")
    }

    @Test("the project hook shows the runs of its event plus command, from every log")
    func projectHookUsage() async throws {
        let h = try TempHome()
        let alpha = h.url("work/alpha").path
        try h.write(".claude/projects/-enc-alpha/s1.jsonl", "{\"type\":\"user\",\"cwd\":\"\(alpha)\"}\n")
        func run(_ exit: Int) -> String { "{\"type\":\"attachment\",\"timestamp\":\"2026-10-02T10:00:00Z\",\"attachment\":{\"type\":\"hook_success\",\"hookEvent\":\"Stop\",\"command\":\"echo shared\",\"durationMs\":1,\"exitCode\":\(exit)}}" }
        try h.write(".claude/projects/-enc-alpha/s2.jsonl", run(0) + "\n" + run(1))
        try h.write(".claude/settings.json", hookConfig("Stop", "echo shared"))
        try h.write("work/alpha/.claude/settings.json", hookConfig("Stop", "echo shared"))
        let r = try roots(h)
        let result = try await UsageScanner(roots: r).scan()
        let inv = Inventory.attachUsage(Inventory.read(roots: r), usage: .ready(result), now: try #require(ISO8601DateFormatter().date(from: "2026-11-02T00:00:00Z")))
        let hook = try #require(inv.hooks.first { $0.command == "echo shared" && $0.scope == .project })
        #expect(hook.usage?.runs == 2 && hook.usage?.errors == 1)
        #expect(hook.cells?.claude == .counted(runs: 2, last: "2026-10-02", errors: 1))
    }

    @Test("an empty home gives an empty inventory")
    func emptyHome() throws {
        let h = try TempHome()
        let r = try roots(h)
        #expect(Inventory.discoverProjects(roots: r) == [])
        let inv = Inventory.read(roots: r)
        #expect(inv.items.isEmpty && inv.hooks.isEmpty && inv.problems.isEmpty)
    }

    // MARK: cells and filter counts

    @Suite("usage cells")
    struct Cells {
        let home: TempHome
        let inventory: InventorySnapshot
        let now = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!
        let newestLog = Int64(ISO8601DateFormatter().date(from: "2026-10-29T00:00:00Z")!.timeIntervalSince1970 * 1000)

        init() throws {
            let h = try TempHome()
            func skill(_ cli: String, _ name: String, _ iso: String) throws {
                let file = try h.write(".\(cli)/skills/\(name)/SKILL.md", skillFile(name))
                try setModified(file, iso)
            }
            try skill("claude", "both", "2026-09-20T00:00:00Z")
            try skill("codex", "both", "2026-09-20T00:00:00Z")
            try skill("claude", "only-claude", "2026-09-20T00:00:00Z")
            try skill("claude", "after-log", "2026-10-30T00:00:00Z")
            try skill("claude", "fresh", "2026-11-02T08:00:00Z")
            let settings = try h.write(".claude/settings.json", "{\"hooks\": {\"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"echo ran\"}, {\"type\": \"command\", \"command\": \"sh '\(h.root.path)/gone/dead.sh'\"}]}]}}")
            try setModified(settings, "2026-09-20T00:00:00Z")
            let codexHooks = try h.write(".codex/hooks.json", "{\"hooks\": {\"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"echo codex-only\"}]}]}}")
            try setModified(codexHooks, "2026-09-20T00:00:00Z")
            inventory = Inventory.read(roots: try Roots.resolve(env: h.env))
            home = h
        }

        var totals: UsageTotals {
            UsageTotals(
                claude: CLIUsageTotals(
                    skill: ["both": NameUsage(sessions: 3, days: ["2026-10-20"], last: "2026-10-20")],
                    hook: [Inventory.hookHash(event: "Stop", command: "echo ran"): HookTotals(runs: 7, ms: 70, timed: 7, errors: 2, last: "2026-10-25")]
                ),
                codex: CLIUsageTotals()
            )
        }
        var windows: UsageWindows {
            UsageWindows(claude: LogWindow(files: 9, oldest: "2026-09-01", newest: newestLog), codex: LogWindow(files: 2, oldest: "2026-09-15", newest: newestLog))
        }
        var ready: InventorySnapshot {
            Inventory.attachUsage(inventory, usage: UsageInput(state: "ready", totals: totals, windows: windows), now: now)
        }
        func cell(_ inv: InventorySnapshot, _ name: String, _ cli: InventoryCLI, itemCli: InventoryCLI = .claude) -> UsageCellState? {
            inv.items.first { $0.name == name && $0.cli == itemCli }?.cells?[cli]
        }

        @Test("counted, with zero runs meaning never ran")
        func counted() {
            let inv = ready
            #expect(cell(inv, "both", .claude) == .counted(runs: 3, last: "2026-10-20", errors: nil))
            #expect(cell(inv, "both", .codex) == .counted(runs: 0, last: nil, errors: nil))
            #expect(cell(inv, "only-claude", .claude) == .counted(runs: 0, last: nil, errors: nil))
        }

        @Test("missing when not installed in that CLI; both rows of one skill show the same cells")
        func missing() {
            let inv = ready
            #expect(cell(inv, "only-claude", .codex) == .missing)
            #expect(cell(inv, "both", .claude, itemCli: .codex) == cell(inv, "both", .claude))
        }

        @Test("pending when no log window covers the item yet")
        func pending() {
            let inv = ready
            guard case .pending(let afterLog)? = cell(inv, "after-log", .claude) else { Issue.record("after-log is not pending"); return }
            #expect(afterLog.contains("newest log"))
            guard case .pending(let fresh)? = cell(inv, "fresh", .claude) else { Issue.record("fresh is not pending"); return }
            #expect(fresh.contains("24 hours"))
        }

        @Test("pending for everything until the scan has finished, and when a CLI has no logs")
        func pendingWithoutScan() {
            let waiting = Inventory.attachUsage(inventory, usage: .scanning, now: now)
            #expect(cell(waiting, "both", .claude) == .pending(reason: "Usage scan has not finished"))
            let none = Inventory.attachUsage(inventory, usage: UsageInput(state: "ready", totals: totals, windows: UsageWindows(claude: windows.claude, codex: LogWindow())), now: now)
            #expect(cell(none, "both", .codex, itemCli: .codex).map { if case .pending = $0 { true } else { false } } == true)
            let nothing = Inventory.attachUsage(inventory, usage: nil, now: now)
            #expect(cell(nothing, "both", .claude) == .pending(reason: "Usage scan has not finished"))
        }

        @Test("hooks: Claude counted with errors, Codex unmeasurable, an absent CLI missing")
        func hooks() throws {
            let inv = ready
            let ran = try #require(inv.hooks.first { $0.command == "echo ran" })
            #expect(ran.cells?.claude == .counted(runs: 7, last: "2026-10-25", errors: 2))
            #expect(ran.cells?.codex == .missing)
            #expect(ran.usage == HookUsage(runs: 7, avgMs: 10, totalMs: 70, errors: 2, last: "2026-10-25"))
            let codexOnly = try #require(inv.hooks.first { $0.command == "echo codex-only" })
            #expect(codexOnly.cells?.codex == .unmeasurable(reason: "Codex does not log hook runs"))
            #expect(codexOnly.cells?.claude == .missing)
            #expect(codexOnly.usage == nil)
        }

        @Test("filter counts: all, only in one CLI, never ran, dead")
        func filter() {
            let inv = ready
            #expect(Inventory.filterCounts(items: inv.items, hooks: inv.hooks) == FilterCounts(all: 7, only: .init(claude: 5, codex: 1), neverRan: 1, dead: 1))
            #expect(Inventory.filterCounts([]) == FilterCounts(all: 0, only: .init(claude: 0, codex: 0), neverRan: 0, dead: 0))
        }

        @Test("a dead hook with zero runs is counted under dead only")
        func deadOnly() {
            let row = FilterRow(key: "k", dead: true, cells: InventoryCells(claude: .counted(runs: 0, last: nil, errors: nil), codex: .missing))
            let counts = Inventory.filterCounts([row])
            #expect(counts.dead == 1 && counts.neverRan == 0)
        }
    }

    // MARK: safety

    @Test("values of env keys in settings never appear in any output")
    func secretsStayOut() async throws {
        let h = try TempHome()
        let secret = "sk-test-CANARY-1f9d"
        try h.write(".claude/settings.json", hookConfig("Stop", "echo hi", secret: secret))
        try h.write(".claude/skills/s/SKILL.md", skillFile("s"))
        try h.write("work/p/.claude/settings.json", hookConfig("Stop", "echo project", secret: secret))
        try h.write(".claude/projects/-enc-p/s1.jsonl", "{\"type\":\"user\",\"cwd\":\"\(h.url("work/p").path)\"}\n")
        let r = try roots(h)
        let result = try await UsageScanner(roots: r).scan()
        let attached = Inventory.attachUsage(Inventory.read(roots: r), usage: .ready(result))
        let output = String(decoding: try JSONEncoder().encode(attached), as: UTF8.self) + String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!output.contains(secret))
        let cache = try String(contentsOf: UsageScanCache.url(r), encoding: .utf8)
        #expect(!cache.contains(secret))
        #expect(attached.hooks.count == 2)
    }

    @Test("unreadable, oversized, and odd files never crash the read")
    func hostileFiles() throws {
        let h = try TempHome()
        // A skill that is a folder, an agent that is a folder, a SKILL.md that is binary, a huge settings file, an unreadable one.
        try FileManager.default.createDirectory(at: h.claude.appendingPathComponent("skills/odd/SKILL.md"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: h.claude.appendingPathComponent("agents/folder.md"), withIntermediateDirectories: true)
        try h.write(".claude/skills/binary/SKILL.md", Data([0xFF, 0xFE, 0x00, 0x2D, 0x2D, 0x2D, 0x80]))
        try h.write(".codex/hooks.json", Data(repeating: 0x20, count: InventoryFileIO.maxJSONBytes + 10))
        let denied = try h.write("work/p/.claude/settings.json", hookConfig("Stop", "echo denied"))
        try h.write(".claude/projects/-enc-p/s1.jsonl", "{\"type\":\"user\",\"cwd\":\"\(h.url("work/p").path)\"}\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied.path) }

        let inv = Inventory.read(roots: try roots(h))
        #expect(inv.items.contains { $0.entry == "binary" })
        #expect(!inv.items.contains { $0.entry == "odd" })
        #expect(!inv.items.contains { $0.entry == "folder.md" })
        #expect(inv.problems.contains { $0.contains("hooks.json") && $0.contains("too large") })
        #expect(inv.problems.contains { $0.contains("work/p/.claude/settings.json") && $0.contains("cannot be read") })
        #expect(Inventory.readItemFile(h.url("nope")) == nil)
    }

    @Test("readItemFile caps the text and says so")
    func itemFile() throws {
        let h = try TempHome()
        let big = try h.write("big.md", String(repeating: "x", count: 70_000))
        let file = try #require(Inventory.readItemFile(big))
        #expect(file.size == 70_000 && file.text.utf8.count == 64 * 1024 && file.truncated)
        let small = try #require(Inventory.readItemFile(try h.write("small.md", "hi")))
        #expect(small.text == "hi" && !small.truncated)
    }

    @Test("a root under the real home is refused when REINS_TEST=1, so no read or scan can reach it")
    func guardRefusesRealHome() {
        let real = Roots.realHomeDirectory()
        #expect(throws: RootsError.self) { try Roots.resolve(env: ["HOME": real, "REINS_TEST": "1"]) }
    }

    @Test("items and hooks survive a JSON round trip")
    func codableRoundTrip() async throws {
        try FixtureHome.materialize()
        let temp = try TempHome()
        var env = FixtureHome.env
        env["REINS_HOME"] = temp.reins.path
        let r = try Roots.resolve(env: env)
        let result = try await UsageScanner(roots: r).scan()
        let inv = Inventory.attachUsage(Inventory.read(roots: r), usage: .ready(result), now: try FixtureHome.now())
        let decoded = try JSONDecoder().decode(InventorySnapshot.self, from: JSONEncoder().encode(inv))
        #expect(decoded == inv)
    }
}
