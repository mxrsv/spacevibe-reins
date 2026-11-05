import Foundation
import ReinsCore

/// An agent on the page. The layout leaves room for a third.
enum AgentKind: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var cli: InventoryCLI { self == .claude ? .claude : .codex }
    var name: String { self == .claude ? "Claude Code" : "Codex" }
    var root: String { self == .claude ? "~/.claude" : "~/.codex" }
    var other: AgentKind { self == .claude ? .codex : .claude }
}

/// The panels a card opens, in card order (Advanced last, as a ghost button).
enum AgentPanel: String, CaseIterable, Identifiable {
    case rules, permissions, hooks, mcp, model, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: "Rules"
        case .permissions: "Permissions"
        case .hooks: "Hooks"
        case .mcp: "MCP"
        case .model: "Model"
        case .advanced: "Advanced"
        }
    }

    var icon: PageGlyph {
        switch self {
        case .rules: .file
        case .permissions: .permissions
        case .hooks: .hook
        case .mcp: .mcp
        case .model: .model
        case .advanced: .advanced
        }
    }
}

/// One choice of a fixed list: its value as written in the file, its words, a line about it, and whether it is risky.
struct AgentChoice: Equatable {
    let value: String
    let title: String
    var detail: String = ""
    var warn = false
}

/// Every sentence and list the Agents page shows that depends on state. Pure, so the tests pin it without a window.
enum AgentsWording {
    static let modes = [
        AgentChoice(value: "default", title: "Ask first", detail: "Asks the first time it uses each tool."),
        AgentChoice(value: "acceptEdits", title: "Accept edits", detail: "Edits files without asking, asks before commands."),
        AgentChoice(value: "plan", title: "Plan", detail: "Reads and plans, changes nothing."),
        AgentChoice(value: "bypassPermissions", title: "Bypass", detail: "Runs every tool without asking.", warn: true),
    ]
    static let approvals = [
        AgentChoice(value: "untrusted", title: "Unless allowed"), AgentChoice(value: "on-request", title: "When needed"),
        AgentChoice(value: "never", title: "Never", warn: true),
    ]
    static let sandboxes = [
        AgentChoice(value: "read-only", title: "Read only"), AgentChoice(value: "workspace-write", title: "Workspace"),
        AgentChoice(value: "danger-full-access", title: "Full access", warn: true),
    ]
    static let trust = [AgentChoice(value: "", title: "Not set"), AgentChoice(value: "trusted", title: "Trusted"), AgentChoice(value: "untrusted", title: "Untrusted")]
    static let efforts = ["minimal", "low", "medium", "high"].map { AgentChoice(value: $0, title: $0.capitalized) }
    static let fileAccess = [AgentChoice(value: "read", title: "Read"), AgentChoice(value: "write", title: "Write"), AgentChoice(value: "deny", title: "Deny")]
    static let domainAccess = [AgentChoice(value: "allow", title: "Allow"), AgentChoice(value: "deny", title: "Deny")]
    static let decisions = [AgentChoice(value: "allow", title: "Allow"), AgentChoice(value: "prompt", title: "Prompt"), AgentChoice(value: "forbidden", title: "Forbidden")]
    static let builtinProfiles = [
        AgentChoice(value: ":read-only", title: ":read-only", detail: "Reads files, writes nothing, no network."),
        AgentChoice(value: ":workspace", title: ":workspace", detail: "Reads files, writes inside the workspace roots, no network."),
        AgentChoice(value: ":danger-full-access", title: ":danger-full-access", detail: "Reads and writes anywhere, with network.", warn: true),
    ]

    /// The consequence each risky value adds to the confirmation (spec, Draft and save).
    static let bypassWarning = "Claude Code will run every tool, including edits and shell commands, without asking."
    static let fullAccessWarning = "Codex will be able to read and write anywhere on this Mac and use the network."
    static let neverWarning = "Codex will never stop to ask before running a command."
    static let openNetworkWarning = "Codex will reach every domain: the domain rules stop applying."

    static let events: [AgentKind: [String]] = [
        .claude: ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Notification", "Stop", "SubagentStop", "PreCompact", "SessionStart", "SessionEnd"],
        .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop", "Interrupt", "Stop", "SessionEnd"],
    ]

    static func title(_ value: String?, in list: [AgentChoice]) -> String {
        list.first { $0.value == value }?.title ?? value ?? "Not set"
    }

    static func plural(_ count: Int, _ one: String, _ many: String? = nil) -> String {
        "\(count) \(count == 1 ? one : (many ?? one + "s"))"
    }

    // MARK: Card sentences

    /// Claude Code at Global: its default mode, then the ask and deny rule counts. Bypass reads in the warn tone.
    static func claudeSentence(_ settings: ClaudeSettings) -> (text: String, warn: Bool) {
        if settings.defaultMode == "bypassPermissions" { return ("Runs every tool without asking", true) }
        let mode = modes.first { $0.value == (settings.defaultMode ?? "default") }?.detail ?? modes[0].detail
        return ("\(mode.dropLast()) \u{00B7} \(plural(settings.ask.count, "ask rule")) \u{00B7} \(plural(settings.deny.count, "deny rule"))", false)
    }

    /// How Codex runs, in the warn tone when it has no sandbox or never asks.
    static func codexSentence(_ config: CodexConfig) -> (text: String, warn: Bool) {
        let asks = ["untrusted": "asks before commands it does not trust", "on-request": "asks when it needs more", "never": "never asks"][config.approvalPolicy ?? "on-request"] ?? "asks when it needs more"
        switch config.permissionModel {
        case .both:
            return ("Uses sandbox_mode and ignores the profile \(config.defaultPermissions ?? ""), because both are set", true)
        case .profiles:
            let profile = profileSentence(config)
            return ("\(profile.text); \(asks)", profile.warn || config.approvalPolicy == "never")
        case .legacy:
            let sandbox = ["read-only": "Reads only", "workspace-write": "Writes only inside the workspace", "danger-full-access": "Can write anywhere"][config.sandboxMode ?? "read-only"] ?? "Reads only"
            return ("\(sandbox) and \(asks)", config.sandboxMode == "danger-full-access" || config.approvalPolicy == "never")
        }
    }

    /// The active profile in one plain sentence (mock C′): what it writes, what it blocks, and its network.
    static func profileSentence(_ config: CodexConfig) -> (text: String, warn: Bool) {
        let active = config.defaultPermissions ?? ""
        switch active {
        case ":read-only": return ("Reads only", false)
        case ":workspace": return ("Writes only inside the workspace roots", false)
        case ":danger-full-access": return ("Can write anywhere", true)
        default: break
        }
        guard let profile = config.profile(active) else { return ("Uses the profile \(active)", false) }
        let writes = profile.filesystem.filter { $0.access == "write" }.map { pathLabel($0.path).lowercased() }
        var parts = [writes.isEmpty ? "Writes nothing" : "Writes in \(writes.joined(separator: " and "))"]
        let denies = profile.filesystem.filter { $0.access == "deny" }.count
        if denies > 0 { parts.append("blocks \(plural(denies, "path"))") }
        let allowed = profile.domains.filter { $0.access == "allow" }.count
        parts.append(!profile.networkEnabled ? "no network" : config.networkProxy ? "network to \(plural(allowed, "domain"))" : "open network")
        return (parts.joined(separator: ", "), profile.networkEnabled && !config.networkProxy)
    }

    /// `:workspace_roots` reads "Workspace roots", `:tmpdir` "Temp folder"; a path below one follows after "›".
    static func pathLabel(_ path: String) -> String {
        let names = [":workspace_roots": "Workspace roots", ":tmpdir": "Temp folder", ":slash_tmp": "/tmp", ":root": "Whole disk", ":minimal": "System basics"]
        let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let root = parts.first, let name = names[root] else { return path }
        return parts.count > 1 ? "\(name) \u{203A} \(parts[1])" : name
    }

    // MARK: Card values

    static func hooksValue(total: Int, dead: Int) -> CardButtonValue {
        .count("\(total)", alert: dead > 0 ? "\(dead) dead" : nil)
    }

    static func codexPermissionsValue(_ config: CodexConfig) -> CardButtonValue {
        switch config.permissionModel {
        case .both: return .count("2 models", warn: true)
        case .profiles: return .code(config.defaultPermissions ?? "", warn: config.defaultPermissions == ":danger-full-access")
        case .legacy: return .count(title(config.sandboxMode ?? "read-only", in: sandboxes), warn: config.sandboxMode == "danger-full-access")
        }
    }

    /// The hint bar (spec, Interface: Hint bar).
    static func hints(panelOpen: Bool, hasDraft: Bool) -> [(keys: String, label: String)] {
        guard panelOpen else { return [("Tab", "Next button"), ("Return", "Open")] }
        return hasDraft ? [("Esc", "Close panel"), ("\u{2318}S", "Review and save")] : [("Esc", "Close panel")]
    }

    /// The scope picker's words for a scope.
    static func scopeTitle(_ scope: RuleScope) -> String {
        switch scope {
        case .global: "Global"
        case .project(let dir): (dir as NSString).lastPathComponent
        case .local(let dir): "\((dir as NSString).lastPathComponent) \u{00B7} Local"
        }
    }
}
