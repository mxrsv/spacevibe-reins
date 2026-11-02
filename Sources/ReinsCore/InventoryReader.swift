import Foundation

// Reads what is installed for Claude Code and Codex. Never executes anything. Settings are read only for hooks, plugin
// flags and skill overrides: no other value (in particular `env`) is kept or returned (S-R3).
extension Inventory {
    /// Skills, agents and hooks of both CLIs, plugin-owned items, and the `.claude/` folders of the discovered projects.
    /// Reads the disk synchronously: call it off the main thread.
    public static func read(roots r: Roots) -> InventorySnapshot {
        var items: [InventoryItem] = []
        var hooks: [InventoryHook] = []
        var problems: [String] = []

        for cli in InventoryCLI.allCases {
            let roots = cli == .claude ? r.claude : r.codex
            switch InventoryFileIO.presence(roots.root.path) {
            case .missing: continue
            case .unknown:
                problems.append("\(roots.root.path) cannot be read, so its skills, agents and hooks cannot be shown.")
                continue
            case .present: break
            }
            items += readSkills(in: roots.skills, cli: cli, owner: nil, project: nil, problems: &problems)
            items += readAgents(in: roots.agents, cli: cli, owner: nil, project: nil, problems: &problems)
            switch InventoryFileIO.readJSON(roots.hookFile) {
            case .value(let config): hooks += parseHooks(from: config, cli: cli, owner: nil, sourceFile: roots.hookFile.path, project: nil, problems: &problems)
            case .invalid: problems.append("\(roots.hookFile.path) is not valid JSON, so its hooks cannot be shown or changed.")
            case .tooLarge: problems.append("\(roots.hookFile.path) is too large to read, so its hooks cannot be shown.")
            case .unreadable: problems.append("\(roots.hookFile.path) cannot be read, so its hooks cannot be shown.")
            case .missing: break
            }
        }

        let claudeSettings = settingsValue(r.claude.hookFile)
        for plugin in plugins(r, settings: claudeSettings) {
            let base = URL(fileURLWithPath: plugin.path, isDirectory: true)
            items += readSkills(in: base.appendingPathComponent("skills"), cli: .claude, owner: plugin.name, project: nil, problems: &problems)
            items += readAgents(in: base.appendingPathComponent("agents"), cli: .claude, owner: plugin.name, project: nil, problems: &problems)
            let hookFile = base.appendingPathComponent("hooks").appendingPathComponent("hooks.json")
            if case .value(let config) = InventoryFileIO.readJSON(hookFile) {
                hooks += parseHooks(from: config, cli: .claude, owner: plugin.name, sourceFile: hookFile.path, project: nil, problems: &problems)
            }
        }

        for path in discoverProjects(roots: r) {
            let dir = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(".claude", isDirectory: true)
            if InventoryFileIO.presence(dir.path) == .unknown {
                problems.append("\(path) cannot be read, so its skills, agents and hooks cannot be shown.")
                continue
            }
            items += readSkills(in: dir.appendingPathComponent("skills"), cli: .claude, owner: nil, project: path, problems: &problems)
            items += readAgents(in: dir.appendingPathComponent("agents"), cli: .claude, owner: nil, project: path, problems: &problems)
            for name in ["settings.json", "settings.local.json"] {
                let file = dir.appendingPathComponent(name)
                switch InventoryFileIO.readJSON(file) {
                case .value(let config): hooks += parseHooks(from: config, cli: .claude, owner: nil, sourceFile: file.path, project: path, problems: &problems)
                case .invalid: problems.append("\(file.path) is not valid JSON, so its hooks cannot be shown.")
                case .tooLarge: problems.append("\(file.path) is too large to read, so its hooks cannot be shown.")
                case .unreadable: problems.append("\(file.path) cannot be read, so its hooks cannot be shown.")
                case .missing: break
                }
            }
        }

        // Claude global skills carry the `skillOverrides` value of settings.json (nil when there is none).
        let overrides = claudeSettings?["skillOverrides"]
        for index in items.indices where items[index].cli == .claude && items[index].kind == .skill && items[index].scope == .global {
            items[index].hasSkillOverride = true
            items[index].skillOverride = overrides?[items[index].name]?.stringValue
        }

        var names = Set<String>()
        for item in items { names.insert("\(item.cli.rawValue):\(item.key)") }
        for index in items.indices { items[index].inOther = names.contains("\(items[index].cli.other.rawValue):\(items[index].key)") }

        return InventorySnapshot(items: items, hooks: hooks, problems: problems, roots: [InventoryCLI.claude.rawValue: r.claude.root.path, InventoryCLI.codex.rawValue: r.codex.root.path])
    }

    /// The first 64 KB of a skill or agent file for the detail view. Nil when it cannot be read.
    public static func readItemFile(_ url: URL) -> InventoryItemFile? {
        var info = stat()
        let limit = 64 * 1024
        guard stat(url.path, &info) == 0, let text = InventoryFileIO.readText(url, maxBytes: limit) else { return nil }
        return InventoryItemFile(size: Int(info.st_size), text: text, truncated: Int(info.st_size) > limit)
    }

    // MARK: Skills and agents

    private static func readSkills(in dir: URL, cli: InventoryCLI, owner: String?, project: String?, problems: inout [String]) -> [InventoryItem] {
        if InventoryFileIO.isUnreadableFolder(dir) { problems.append("\(dir.path) cannot be read, so its skills cannot be shown.") }
        var out: [InventoryItem] = []
        for entry in InventoryFileIO.list(dir) where !isSystemName(entry) {
            let path = dir.appendingPathComponent(entry, isDirectory: true)
            let file = path.appendingPathComponent("SKILL.md")
            guard let text = InventoryFileIO.readText(file) else { continue }
            let fm = Frontmatter.parse(text)
            out.append(InventoryItem(
                id: "\(cli.rawValue):skill:\(idTag(owner: owner, project: project)):\(entry)", cli: cli, kind: .skill,
                name: nonEmpty(fm["name"]) ?? entry, entry: entry, description: fm["description"] ?? "",
                owner: owner ?? ownerOf(path), path: path.path, file: file.path, removable: isUserLevel(owner, project),
                scope: project == nil ? .global : .project, project: project
            ))
        }
        return out
    }

    private static func readAgents(in dir: URL, cli: InventoryCLI, owner: String?, project: String?, problems: inout [String]) -> [InventoryItem] {
        if InventoryFileIO.isUnreadableFolder(dir) { problems.append("\(dir.path) cannot be read, so its agents cannot be shown.") }
        var out: [InventoryItem] = []
        for entry in InventoryFileIO.list(dir) where !isSystemName(entry) {
            let isMarkdown = entry.hasSuffix(".md")
            guard isMarkdown || entry.hasSuffix(".toml") else { continue }
            let path = dir.appendingPathComponent(entry)
            guard let text = InventoryFileIO.readText(path) else { continue }
            let fields = isMarkdown ? Frontmatter.parse(text) : tomlFields(text)
            let fallback = String(entry.dropLast(isMarkdown ? 3 : 5))
            out.append(InventoryItem(
                id: "\(cli.rawValue):agent:\(idTag(owner: owner, project: project)):\(entry)", cli: cli, kind: .agent,
                name: nonEmpty(fields["name"]) ?? fallback, entry: entry, description: fields["description"] ?? "",
                owner: owner ?? ownerOf(path), path: path.path, file: path.path, removable: isUserLevel(owner, project),
                scope: project == nil ? .global : .project, project: project
            ))
        }
        return out
    }

    /// `name` and `description` of a Codex agent `.toml`: the first assignment of each key, in any table, as the Node regex finds it.
    static func tomlFields(_ text: String) -> [String: String] {
        let doc = TOMLReader.read(text)
        var out: [String: String] = [:]
        for key in ["name", "description"] {
            if let value = doc.entries.first(where: { $0.keyPath == [key] && $0.value?.stringValue != nil })?.value?.stringValue { out[key] = value }
        }
        return out
    }

    private static func isSystemName(_ name: String) -> Bool { name.hasPrefix(".") || name.hasPrefix("_") }
    private static func nonEmpty(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
    private static func isUserLevel(_ owner: String?, _ project: String?) -> Bool { (owner ?? "").isEmpty && project == nil }
    private static func ownerOf(_ path: URL) -> String { InventoryFileIO.isSymlink(path) ? "link" : "user" }
    private static func idTag(owner: String?, project: String?) -> String {
        if let project { return "project:\(sha(project))" }
        return owner ?? "local"
    }

    // MARK: Hooks

    private static func parseHooks(from config: JSONValue, cli: InventoryCLI, owner: String?, sourceFile: String, project: String?, problems: inout [String]) -> [InventoryHook] {
        var out: [InventoryHook] = []
        guard let events = config["hooks"]?.objectValue else { return out }
        // A duplicated key counts once, with the last value, as `JSON.parse` has it.
        var seenEvents = Set<String>()
        for member in events where seenEvents.insert(member.key).inserted {
            guard let groups = config["hooks"]?[member.key]?.arrayValue else { continue }
            for group in groups {
                let matcher = group["matcher"]?.stringValue
                for hook in group["hooks"]?.arrayValue ?? [] {
                    guard let command = hook["command"]?.stringValue else { continue }
                    let paths = scriptPaths(command)
                    // Dead only when every script is known to be gone: a script under a folder Reins cannot stat may well work.
                    let presences = paths.map { InventoryFileIO.presence($0) }
                    let dead = !paths.isEmpty && presences.allSatisfy { $0 == .missing }
                    if presences.contains(.unknown) {
                        let note = "A script named in \(sourceFile) cannot be checked, so its hook is not marked dead."
                        if !problems.contains(note) { problems.append(note) }
                    }
                    // A global id hashes owner, event, matcher and command. A project hook also hashes its file, so the same hook in two files has two ids.
                    let seed = "\(owner ?? "")|\(member.key)|\(matcher ?? "")|\(command)\(project == nil ? "" : "|\(sourceFile)")"
                    out.append(InventoryHook(
                        id: "\(cli.rawValue):hook:\(sha(seed))", cli: cli, event: member.key, matcher: matcher, command: command,
                        timeout: hook["timeout"]?.numberText.flatMap(Double.init), async: hook["async"]?.boolValue ?? false,
                        owner: owner ?? "user", removable: isUserLevel(owner, project), dead: dead, paths: paths,
                        hash: hookHash(event: member.key, command: command), file: sourceFile,
                        scope: project == nil ? .global : .project, project: project
                    ))
                }
            }
        }
        return out
    }

    // MARK: Plugins

    /// Enabled Claude plugins whose install folder still exists. Read-only: Reins never changes a plugin.
    private static func plugins(_ r: Roots, settings: JSONValue?) -> [(name: String, path: String)] {
        let file = r.claude.root.appendingPathComponent("plugins").appendingPathComponent("installed_plugins.json")
        guard case .value(let installed) = InventoryFileIO.readJSON(file), let entries = installed["plugins"]?.objectValue else { return [] }
        var out: [(String, String)] = []
        var seen = Set<String>()
        for entry in entries where seen.insert(entry.key).inserted {
            guard let value = installed["plugins"]?[entry.key] else { continue }
            guard settings?["enabledPlugins"]?[entry.key]?.boolValue == true,
                  let path = value[0]?["installPath"]?.stringValue, !path.isEmpty, InventoryFileIO.exists(path) else { continue }
            out.append((entry.key.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? entry.key, path))
        }
        return out
    }

    private static func settingsValue(_ file: URL) -> JSONValue? {
        if case .value(let value) = InventoryFileIO.readJSON(file) { return value }
        return nil
    }
}
