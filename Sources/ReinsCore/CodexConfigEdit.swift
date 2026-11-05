import Foundation

/// The edits the Codex panels make to `config.toml` (plan A5), each a line-level `TOMLEdit`, so comments, order and every
/// untouched key stay byte-identical. A write never leaves both `sandbox_mode` and `default_permissions` set (AG6).
public enum CodexConfigEdit {
    public enum Change: Equatable, Sendable {
        case approvalPolicy(String)
        case sandboxMode(String)
        case networkAccess(Bool)
        case writableRoots([String])
        /// A project's `trust_level`; nil removes it ("Not set").
        case trust(project: String, level: String?)
        case model(String?)
        case reasoningEffort(String?)
        case addServer(name: String, kind: MCPServer.Kind, target: String)
        case removeServer(name: String)
        case replaceSecret(server: String, table: String, name: String, value: String)
        case defaultPermissions(String)
        /// The both-models card: keep `sandbox_mode` (removes `default_permissions`), or keep the profile (removes
        /// `sandbox_mode` and `[sandbox_workspace_write]`).
        case keepModel(CodexPermissionModel)
        case profileExtends(profile: String, parent: String?)
        case pathRule(profile: String, path: String, access: String?)
        case networkEnabled(profile: String, Bool)
        case networkProxy(Bool)
        case domain(profile: String, host: String, access: String?)
    }

    static let bothRefusal = ReinsError("Codex would have both sandbox_mode and default_permissions set. Keep one in Permissions first. Nothing was saved.", status: 409)

    /// `guardModels: false` is for showing a draft only: the both-models state must still read while the user picks one.
    public static func apply(_ changes: [Change], to text: String, guardModels: Bool = true) throws -> String {
        var edit = TOMLEdit(text)
        for change in changes { edit = try apply(change, to: edit) }
        if guardModels { try guardOneModel(edit.text) }
        return edit.text
    }

    public static func fileChange(_ file: URL, _ changes: [Change]) -> AgentFileChange {
        AgentFileChange(file: file) { text in try apply(changes, to: text ?? "") }
    }

    /// The Advanced editor's check for `config.toml`: every line must read as TOML, and one permission model only.
    public static func check(_ text: String) throws {
        if let line = TOMLLayout(text: text).firstUnreadableLine() {
            throw ReinsError("config.toml is not valid TOML at line \(line).", status: 400)
        }
        try guardOneModel(text)
    }

    static func guardOneModel(_ text: String) throws {
        let edit = TOMLEdit(text)
        if edit.value(["sandbox_mode"]) != nil, edit.value(["default_permissions"]) != nil { throw bothRefusal }
    }

    private static func apply(_ change: Change, to edit: TOMLEdit) throws -> TOMLEdit {
        switch change {
        case .approvalPolicy(let value): return try edit.setting(["approval_policy"], to: .string(value))
        case .sandboxMode(let value): return try edit.setting(["sandbox_mode"], to: .string(value))
        case .networkAccess(let on): return try edit.setting(["sandbox_workspace_write", "network_access"], to: .bool(on))
        case .writableRoots(let roots):
            if roots.isEmpty { return try edit.removing(["sandbox_workspace_write", "writable_roots"]) }
            return try edit.setting(["sandbox_workspace_write", "writable_roots"], to: .strings(roots))
        case .trust(let project, let level):
            let path = ["projects", project, "trust_level"]
            if let level { return try edit.setting(path, to: .string(level)) }
            return try edit.removing(path)
        case .model(let model): return try optional(edit, ["model"], model)
        case .reasoningEffort(let effort): return try optional(edit, ["model_reasoning_effort"], effort)
        case .addServer(let name, let kind, let target):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !target.trimmingCharacters(in: .whitespaces).isEmpty else { throw ReinsError("A server needs a name and a target.") }
            guard edit.value(["mcp_servers", trimmed, "command"]) == nil, edit.value(["mcp_servers", trimmed, "url"]) == nil else {
                throw ReinsError("A server named \(trimmed) already exists.")
            }
            if kind == .url { return try edit.setting(["mcp_servers", trimmed, "url"], to: .string(target.trimmingCharacters(in: .whitespaces))) }
            let words = target.split(separator: " ").map(String.init)
            var next = try edit.setting(["mcp_servers", trimmed, "command"], to: .string(words[0]))
            if words.count > 1 { next = try next.setting(["mcp_servers", trimmed, "args"], to: .strings(Array(words.dropFirst()))) }
            return next
        case .removeServer(let name): return try edit.removingTable(["mcp_servers", name])
        case .replaceSecret(let server, let table, let name, let value):
            return try edit.setting(["mcp_servers", server, table, name], to: .string(value))
        case .defaultPermissions(let name): return try edit.setting(["default_permissions"], to: .string(name))
        case .keepModel(let model):
            switch model {
            case .profiles:
                return try edit.removing(["sandbox_mode"]).removingTable(["sandbox_workspace_write"])
            case .legacy, .both:
                return try edit.removing(["default_permissions"])
            }
        case .profileExtends(let profile, let parent): return try optional(edit, ["permissions", profile, "extends"], parent)
        case .pathRule(let profile, let path, let access): return try optional(edit, ["permissions", profile, "filesystem", path], access)
        case .networkEnabled(let profile, let on): return try edit.setting(["permissions", profile, "network", "enabled"], to: .bool(on))
        case .networkProxy(let on): return try edit.setting(["features", "network_proxy"], to: .bool(on))
        case .domain(let profile, let host, let access): return try optional(edit, ["permissions", profile, "network", "domains", host], access)
        }
    }

    /// Sets a string, or removes the key for nil or an empty string.
    private static func optional(_ edit: TOMLEdit, _ path: [String], _ value: String?) throws -> TOMLEdit {
        if let value, !value.isEmpty { return try edit.setting(path, to: .string(value)) }
        return try edit.removing(path)
    }
}
