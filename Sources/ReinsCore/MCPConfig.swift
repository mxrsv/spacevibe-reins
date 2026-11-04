import Foundation

/// One MCP server as the MCP panel shows it: its name, how it is reached and the names of its secrets. The values of its
/// environment and headers are never read into it (spec, Writes: Secrets).
public struct MCPServer: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case command, url
    }

    public let name: String
    public let kind: Kind
    /// The command and its arguments, or the URL.
    public let target: String
    /// Keys of `env` (Codex: `env`) and of `headers` (Codex: `http_headers`, `env_http_headers`), in file order.
    public let secretNames: [MCPSecretName]
    /// The plugin that owns the server: read-only, with a lock tag.
    public let plugin: String?

    public var id: String { name }

    public init(name: String, kind: Kind, target: String, secretNames: [MCPSecretName], plugin: String?) {
        self.name = name
        self.kind = kind
        self.target = target
        self.secretNames = secretNames
        self.plugin = plugin
    }
}

public struct MCPSecretName: Equatable, Sendable, Hashable {
    /// `env`, `headers`, `http_headers` or `env_http_headers`.
    public let table: String
    public let name: String

    public init(table: String, name: String) {
        self.table = table
        self.name = name
    }
}

/// The MCP panel's edits, on a JSON `mcpServers` object (Claude Code) wherever it sits in its file.
public enum MCPEdit {
    public enum Change: Equatable, Sendable {
        /// A command is split at spaces into `command` and `args`; a URL becomes `{ "type": "http", "url" }`.
        case add(name: String, kind: MCPServer.Kind, target: String)
        case remove(name: String)
        /// Writes a new value for one secret without ever reading the old one.
        case replaceSecret(server: String, table: String, name: String, value: String)
    }

    /// The servers of an `mcpServers` object.
    public static func servers(_ object: JSONValue?, plugin: String? = nil) -> [MCPServer] {
        (object?.objectValue ?? []).compactMap { member in
            guard let server = member.value.objectValue.map(JSONValue.object) else { return nil }
            let names = ["env", "headers"].flatMap { table in
                (server[table]?.objectValue ?? []).map { MCPSecretName(table: table, name: $0.key) }
            }
            if let url = server["url"]?.stringValue {
                return MCPServer(name: member.key, kind: .url, target: url, secretNames: names, plugin: plugin)
            }
            let parts = [server["command"]?.stringValue ?? ""] + (server["args"]?.arrayValue ?? []).compactMap(\.stringValue)
            return MCPServer(name: member.key, kind: .command, target: parts.filter { !$0.isEmpty }.joined(separator: " "), secretNames: names, plugin: plugin)
        }
    }

    /// Applies the changes to the `mcpServers` object at `base` (`["mcpServers"]`, or a project's entry in `~/.claude.json`).
    public static func apply(_ changes: [Change], to document: OrderedJSON, at base: [PathStep], file: URL) throws -> OrderedJSON {
        var doc = document
        do {
            for change in changes {
                switch change {
                case .add(let name, let kind, let target):
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !target.trimmingCharacters(in: .whitespaces).isEmpty else { throw ReinsError("A server needs a name and a target.") }
                    guard doc[base + [.key(trimmed)]] == nil else { throw ReinsError("A server named \(trimmed) already exists.") }
                    doc = try doc.setting(base + [.key(trimmed)], to: value(kind: kind, target: target))
                case .remove(let name):
                    if doc[base + [.key(name)]] != nil { doc = try doc.removing(base + [.key(name)]) }
                case .replaceSecret(let server, let table, let name, let secret):
                    guard doc[base + [.key(server)]] != nil else { throw ReinsError("The server \(server) is gone.", status: 404) }
                    doc = try doc.setting(base + [.key(server), .key(table), .key(name)], to: .string(secret))
                }
            }
        } catch is OrderedJSONError {
            throw ReinsError("\(file.path) has an unexpected layout. Nothing was changed.", status: 409)
        }
        return doc
    }

    static func value(kind: MCPServer.Kind, target: String) -> JSONValue {
        switch kind {
        case .url:
            return .object([JSONMember("type", "http"), JSONMember("url", .string(target.trimmingCharacters(in: .whitespaces)))])
        case .command:
            let words = target.split(separator: " ").map(String.init)
            var members = [JSONMember("command", .string(words.first ?? ""))]
            if words.count > 1 { members.append(JSONMember("args", .array(words.dropFirst().map(JSONValue.string)))) }
            return .object(members)
        }
    }
}

/// MCP servers in Claude Code's state file `~/.claude.json` (plan A4): the user-level `mcpServers`, and a project's own
/// `projects.<path>.mcpServers` (the Local scope). Only those keys are read into the app; the file's other keys stay
/// bytes. Claude Code rewrites the file often, so a save that finds it changed since the read applies the same edit to
/// the new content once, then refuses with the spec's message.
public enum ClaudeStateMCP {
    public static let conflictMessage = "Claude Code just changed ~/.claude.json. Nothing was saved; try again."

    static func base(project: String?) -> [PathStep] {
        guard let project else { return ["mcpServers"] }
        return ["projects", .key(project), "mcpServers"]
    }

    /// The servers at user level (`project` nil) or a project's Local entry, and a problem when the file cannot be read.
    public static func read(_ roots: Roots, project: String?) -> (servers: [MCPServer], problem: String?) {
        switch InventoryFileIO.readJSON(roots.claudeState) {
        case .missing: return ([], nil)
        case .value(let root):
            var node: JSONValue? = root
            for step in base(project: project) {
                if case .key(let key) = step { node = node?[key] }
            }
            return (MCPEdit.servers(node), nil)
        case .invalid, .tooLarge, .unreadable: return ([], "\(roots.claudeState.path) could not be read, so its MCP servers cannot be shown.")
        }
    }

    public static func fileChange(_ roots: Roots, project: String?, _ changes: [MCPEdit.Change]) -> AgentFileChange {
        let file = roots.claudeState
        let json = AgentSave.jsonChange(file) { try MCPEdit.apply(changes, to: $0, at: base(project: project), file: file) }
        return AgentFileChange(file: file, validate: json.validate, retries: 1, conflictMessage: conflictMessage, change: json.change)
    }
}

/// A project's shared MCP servers in `<project>/.mcp.json` (the Project scope), and the read-only servers of enabled plugins.
public enum MCPFile {
    public static func url(project: String) -> URL {
        URL(fileURLWithPath: project, isDirectory: true).appendingPathComponent(".mcp.json")
    }

    public static func read(project: String) -> (servers: [MCPServer], problem: String?) {
        let file = url(project: project)
        switch InventoryFileIO.readJSON(file) {
        case .missing: return ([], nil)
        case .value(let root): return (MCPEdit.servers(root["mcpServers"]), nil)
        case .invalid, .tooLarge, .unreadable: return ([], "\(file.path) could not be read, so its MCP servers cannot be shown.")
        }
    }

    public static func fileChange(project: String, _ changes: [MCPEdit.Change]) -> AgentFileChange {
        let file = url(project: project)
        return AgentSave.jsonChange(file) { try MCPEdit.apply(changes, to: $0, at: ["mcpServers"], file: file) }
    }

    /// Servers that enabled Claude Code plugins bring in their own `.mcp.json`. They cannot be changed.
    public static func pluginServers(_ roots: Roots) -> [MCPServer] {
        Inventory.plugins(roots, settings: Inventory.settingsValue(roots.claude.hookFile)).flatMap { plugin -> [MCPServer] in
            let file = URL(fileURLWithPath: plugin.path, isDirectory: true).appendingPathComponent(".mcp.json")
            guard case .value(let root) = InventoryFileIO.readJSON(file) else { return [] }
            return MCPEdit.servers(root["mcpServers"] ?? root, plugin: plugin.name)
        }
    }
}
