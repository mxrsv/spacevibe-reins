import Foundation

/// One `filesystem` entry of a Codex permission profile: a path or glob and `read`, `write` or `deny`.
public struct CodexPathRule: Equatable, Sendable {
    public let path: String
    public let access: String
}

/// One `network.domains` entry: a host pattern and `allow` or `deny`.
public struct CodexDomainRule: Equatable, Sendable {
    public let host: String
    public let access: String
}

/// A named `[permissions.<name>]` profile, as the Permissions panel edits it. The layout follows mock C′ (plan A0b):
/// `extends`, `[permissions.<name>.filesystem]` path = access, `[permissions.<name>.network]` `enabled`, and
/// `[permissions.<name>.network.domains]` host = access.
public struct CodexPermissionProfile: Equatable, Sendable {
    public let name: String
    public let extends: String?
    public let filesystem: [CodexPathRule]
    public let networkEnabled: Bool
    public let domains: [CodexDomainRule]
}

/// Codex's `config.toml` as the Codex panels show it (plan A5). Secrets in `mcp_servers` are names only.
public struct CodexConfig: Equatable, Sendable {
    public let file: URL
    public let exists: Bool
    public let approvalPolicy: String?
    public let sandboxMode: String?
    public let networkAccess: Bool?
    public let writableRoots: [String]
    public let defaultPermissions: String?
    public let profiles: [CodexPermissionProfile]
    /// `[features] network_proxy`: domain rules are enforced.
    public let networkProxy: Bool
    public let model: String?
    public let reasoningEffort: String?
    public let trust: [String: String]
    public let mcpServers: [MCPServer]

    /// The built-in profiles, which are described and never edited.
    public static let builtinProfiles = [":read-only", ":workspace", ":danger-full-access"]

    public var permissionModel: CodexPermissionModel {
        switch (defaultPermissions != nil, sandboxMode != nil) {
        case (true, true): .both
        case (true, false): .profiles
        default: .legacy
        }
    }

    public func profile(_ name: String?) -> CodexPermissionProfile? {
        profiles.first { $0.name == name }
    }

    public static func read(_ file: URL) -> CodexConfig {
        let exists = InventoryFileIO.exists(file.path)
        let text = InventoryFileIO.readData(file, maxBytes: InventoryFileIO.maxJSONBytes).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return parse(text, file: file, exists: exists)
    }

    public static func parse(_ text: String, file: URL, exists: Bool) -> CodexConfig {
        let document = TOMLReader.read(text)
        func value(_ path: [String]) -> TOMLValue? { TOMLEdit.lookup(document, path) }
        var trust: [String: String] = [:]
        var profileNames: [String] = []
        var mcpNames: [String] = []
        for entry in document.entries where !entry.inArrayTable {
            let full = entry.table + entry.keyPath
            if full.count == 3, full[0] == "projects", full[2] == "trust_level", let level = entry.value?.stringValue { trust[full[1]] = level }
            if full.count == 2, full[0] == "projects", let level = entry.value?["trust_level"]?.stringValue { trust[full[1]] = level }
            if full.count >= 3, full[0] == "permissions", !profileNames.contains(full[1]) { profileNames.append(full[1]) }
            if full.count >= 3, full[0] == "mcp_servers", !mcpNames.contains(full[1]) { mcpNames.append(full[1]) }
        }
        for header in document.tables where header.path.count >= 2 && !header.isArray {
            if header.path[0] == "permissions", !profileNames.contains(header.path[1]) { profileNames.append(header.path[1]) }
            if header.path[0] == "mcp_servers", !mcpNames.contains(header.path[1]) { mcpNames.append(header.path[1]) }
        }
        let profiles = profileNames.map { name -> CodexPermissionProfile in
            let base = ["permissions", name]
            return CodexPermissionProfile(
                name: name,
                extends: value(base + ["extends"])?.stringValue,
                filesystem: pairs(document, base + ["filesystem"]).map { CodexPathRule(path: $0.0, access: $0.1) },
                networkEnabled: value(base + ["network", "enabled"])?.boolValue ?? false,
                domains: pairs(document, base + ["network", "domains"]).map { CodexDomainRule(host: $0.0, access: $0.1) }
            )
        }
        let servers = mcpNames.map { name -> MCPServer in
            let base = ["mcp_servers", name]
            let names = ["env", "http_headers", "env_http_headers"].flatMap { table in
                keys(document, base + [table]).map { MCPSecretName(table: table, name: $0) }
            }
            if let url = value(base + ["url"])?.stringValue {
                return MCPServer(name: name, kind: .url, target: url, secretNames: names, plugin: nil)
            }
            let parts = [value(base + ["command"])?.stringValue ?? ""] + (value(base + ["args"])?.strings ?? [])
            return MCPServer(name: name, kind: .command, target: parts.filter { !$0.isEmpty }.joined(separator: " "), secretNames: names, plugin: nil)
        }
        return CodexConfig(
            file: file, exists: exists,
            approvalPolicy: value(["approval_policy"])?.stringValue,
            sandboxMode: value(["sandbox_mode"])?.stringValue,
            networkAccess: value(["sandbox_workspace_write", "network_access"])?.boolValue,
            writableRoots: value(["sandbox_workspace_write", "writable_roots"])?.strings ?? [],
            defaultPermissions: value(["default_permissions"])?.stringValue,
            profiles: profiles,
            networkProxy: value(["features", "network_proxy"])?.boolValue ?? false,
            model: value(["model"])?.stringValue,
            reasoningEffort: value(["model_reasoning_effort"])?.stringValue,
            trust: trust,
            mcpServers: servers
        )
    }

    /// The string values directly under a table path (a `[table]` or an inline table), in file order.
    static func pairs(_ document: TOMLDocument, _ path: [String]) -> [(String, String)] {
        var out: [(String, String)] = []
        func put(_ key: String, _ value: String) {
            out.removeAll { $0.0 == key }
            out.append((key, value))
        }
        for entry in document.entries where !entry.inArrayTable {
            let full = entry.table + entry.keyPath
            if full.count == path.count + 1, Array(full.prefix(path.count)) == path, let text = entry.value?.stringValue { put(full[path.count], text) }
            if full == path, let table = entry.value?.tableValue {
                for pair in table { if let text = pair.value.stringValue { put(pair.key, text) } }
            }
        }
        return out
    }

    /// The keys directly under a table path, without their values.
    static func keys(_ document: TOMLDocument, _ path: [String]) -> [String] {
        var out: [String] = []
        for entry in document.entries where !entry.inArrayTable {
            let full = entry.table + entry.keyPath
            if full.count == path.count + 1, Array(full.prefix(path.count)) == path, !out.contains(full[path.count]) { out.append(full[path.count]) }
            if full == path { for pair in entry.value?.tableValue ?? [] where !out.contains(pair.key) { out.append(pair.key) } }
        }
        return out
    }
}
