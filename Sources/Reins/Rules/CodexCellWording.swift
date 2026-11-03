import ReinsCore

/// One real setting behind a Codex cell.
struct CodexKey: Equatable {
    let key: String
    let value: String

    /// The last part of a dotted key, which is all the collapsed cell has room for.
    var shortKey: String { key.split(separator: ".").last.map(String.init) ?? key }
}

/// What a Codex cell says. Codex stores no Allow / Ask / Deny per capability, so the cell shows the real setting (display only).
struct CodexCellView: Equatable {
    enum Tone { case neutral, warn, none }

    var label: String
    var tone: Tone
    var keys: [CodexKey]
    /// Said in the expanded cell when the keys alone do not explain it.
    var note: String?
}

/// Which real Codex setting answers each grid row. Same mapping as the superseded Electron screen, which followed the
/// Codex permission schema (plan 0.1): Read and Edit are per path only in a `[permissions]` profile, Run commands is
/// `approval_policy` plus rules, Network is per sandbox or profile, Push and deploy and Secrets have no plain setting.
enum CodexCellWording {
    static func cell(_ capability: Capability, _ codex: CodexPermissions) -> CodexCellView {
        guard codex.present else { return none("There is no ~/.codex/config.toml yet, so Codex runs on its defaults.") }
        let sandbox = codex.sandboxMode.map { [CodexKey(key: "sandbox_mode", value: $0)] } ?? []
        let unrestricted = CodexCellView(label: "unrestricted", tone: .warn, keys: sandbox)

        switch capability {
        case .push:
            return none("Codex has no setting for push or deploy. A command rule in ~/.codex/rules can approximate it.")
        case .secrets:
            return none("Codex can only block secrets with deny globs in a [permissions] profile, which this file does not use.")
        case .run:
            let approval = approvalText(codex)
            if codex.unrestricted, approval == "never" {
                return CodexCellView(label: "unrestricted", tone: .warn, keys: approvalKeys(codex) + sandbox)
            }
            guard let approval else {
                var cell = none("approval_policy is not set; Codex uses its default.")
                cell.keys = approvalKeys(codex)
                return cell
            }
            return CodexCellView(label: approvalLabels[approval] ?? approval, tone: .neutral, keys: approvalKeys(codex))
        case .read, .edit, .network:
            break
        }
        if codex.unrestricted { return unrestricted }

        if let name = codex.defaultPermissions {
            let profile = codex.profiles.first { $0.name == name }
            let base = [CodexKey(key: "default_permissions", value: name)]
            if capability == .network {
                let flags = (profile?.networkFlags ?? []).map { CodexKey(key: "permissions.\(name).network.\($0.key)", value: networkFlagText($0.value)) }
                return CodexCellView(label: "set by profile", tone: .neutral, keys: base + flags, note: flags.isEmpty ? "The profile has no network flags." : nil)
            }
            return CodexCellView(label: "set by profile", tone: .neutral, keys: base + [CodexKey(key: "permissions.\(name).filesystem", value: "\(profile?.filesystemEntries ?? 0) entries")])
        }

        if capability == .read { return none("Codex has no read setting without a [permissions] profile.") }
        guard let mode = codex.sandboxMode else { return none("sandbox_mode is not set; Codex uses its default.") }
        if capability == .edit {
            let label = mode == "read-only" ? "read-only" : mode == "workspace-write" ? "workspace only" : mode
            return CodexCellView(label: label, tone: .neutral, keys: sandbox)
        }
        let network = codex.sandboxWorkspaceWrite?.networkAccess
        let keys = (network.map { [CodexKey(key: "sandbox_workspace_write.network_access", value: String($0))] } ?? []) + sandbox
        return CodexCellView(label: mode == "workspace-write" && network == true ? "on" : "off", tone: .neutral, keys: keys)
    }

    static func approvalText(_ codex: CodexPermissions) -> String? {
        switch codex.approvalPolicy {
        case .mode(let text): text
        case .granular: "granular"
        case nil: nil
        }
    }

    /// "3 allow, 1 prompt, 0 forbidden", or "none" when there are no rules files.
    static func rulesSummary(_ codex: CodexPermissions) -> String {
        let rules = codex.rules
        guard rules.files > 0 else { return "none" }
        var parts = ["\(rules.allow) allow", "\(rules.prompt) prompt", "\(rules.forbidden) forbidden"]
        if rules.other > 0 { parts.append("\(rules.other) other") }
        return parts.joined(separator: ", ")
    }

    /// Project trust levels as counts: "3 trusted, 1 unset".
    static func trustSummary(_ codex: CodexPermissions) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for project in codex.projects {
            let level = project.trustLevel ?? "unset"
            if counts[level] == nil { order.append(level) }
            counts[level, default: 0] += 1
        }
        return order.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
    }

    /// What a `[permissions.<name>.network]` flag shows. The reader keeps any string there, and a string can be a proxy URL
    /// with a password or a token (AGENTS.md S-R3), so text is shown only when it reads as a mode word such as "limited".
    static let hiddenFlagText = "text, not shown"

    static func networkFlagText(_ value: JSONValue) -> String {
        guard case .string(let text) = value else { return show(value) }
        let isModeWord = (1...24).contains(text.count) && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || $0 == "-" }
        return isModeWord ? text : hiddenFlagText
    }

    static func show(_ value: JSONValue) -> String {
        switch value {
        case .bool(let flag): String(flag)
        case .string(let text): text
        case .number(let text): text
        default: "set"
        }
    }

    private static let approvalLabels = [
        "on-request": "asks when needed", "never": "never asks", "on-failure": "asks on failure", "untrusted": "asks (retired value)", "granular": "granular",
    ]

    private static func none(_ note: String) -> CodexCellView {
        CodexCellView(label: "no setting", tone: .none, keys: [], note: note)
    }

    private static func approvalKeys(_ codex: CodexPermissions) -> [CodexKey] {
        var keys: [CodexKey] = []
        if let text = approvalText(codex) { keys.append(CodexKey(key: "approval_policy", value: text)) }
        if codex.rules.files > 0 { keys.append(CodexKey(key: "~/.codex/rules", value: rulesSummary(codex))) }
        return keys
    }
}
