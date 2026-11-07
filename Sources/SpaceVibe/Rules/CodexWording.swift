import Foundation

/// One line of the Codex page's "How Codex runs" card: a plain name, the real key (or why there is none) under it, and the
/// value, either every option of the key with the real one picked or a single tag.
struct CodexSettingRow: Equatable {
    enum Value: Equatable {
        /// Every option of the key, the real one picked (nil when none of them is set). `warn` marks a value that needs a look.
        case options([String], picked: String?, warn: Bool)
        case tag(String, tone: TagTone)
    }

    let title: String
    let key: String
    /// False when `key` is a sentence rather than a key.
    var keyIsCode = true
    let value: Value
}

/// The sentence at the top of the Codex page and of the Claude Code page's summary bar.
struct CodexStatus: Equatable {
    let tone: StatusTone
    let sentence: String
    /// The keys the sentence rests on.
    let detail: String?
}

/// What the Codex page says, in Codex's own terms (no Allow / Ask / Deny: Codex has none per capability). Pure.
///
/// Values come from `config.toml`, where any string could be a secret (AGENTS.md S-R3), so free text is shown only when it
/// reads as a plain word ("on-request", "dev"); anything else shows as `hiddenText`. The meaning of each `approval_policy`
/// value follows Codex's `AskForApproval` (`untrusted` asks unless a rule allows the command, `on-failure` is an alias of
/// `on-request`, `never` never asks).
enum CodexWording {
    static let hiddenText = "text, not shown"

    static let approvalTitles: [(value: String, title: String)] = [("untrusted", "Unless allowed"), ("on-request", "When needed"), ("never", "Never")]
    static let sandboxTitles: [(value: String, title: String)] = [("read-only", "Read only"), ("workspace-write", "Workspace"), ("danger-full-access", "Full access")]
    static let networkTitles = ["Off", "On"]

    /// `config.toml` exists but cannot be read: nothing about Codex's settings is known, so nothing is guessed, least of all the defaults.
    static let notReadableSentence = "Cannot read ~/.codex/config.toml, so Codex's settings are not known."
    static let trustNotReadableSentence = "Cannot read ~/.codex/config.toml, so project trust is not known."

    /// A config string as it may be shown: itself when it is a short lowercase word, else `hiddenText`.
    static func word(_ text: String) -> String { isWord(text) ? text : hiddenText }

    static func isWord(_ text: String) -> Bool {
        (1...24).contains(text.count)
            && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
            && text.unicodeScalars.filter { ("0"..."9").contains($0) }.count <= 2
    }

    /// The `approval_policy` string, `granular` for the table form, nil when unset. `on-failure` stays as written.
    static func approval(_ codex: CoreCodexPermissions) -> String? {
        switch codex.approvalPolicy {
        case .mode(let text): text
        case .granular: "granular"
        case nil: nil
        }
    }

    // MARK: Status

    static func status(_ codex: CoreCodexPermissions) -> CodexStatus {
        // Unreadable is checked first: `present` and every setting below it are unknown then, not the defaults.
        guard !codex.notReadable else { return CodexStatus(tone: .warn, sentence: notReadableSentence, detail: nil) }
        guard codex.present else {
            return CodexStatus(tone: .neutral, sentence: "Runs on its defaults: there is no ~/.codex/config.toml", detail: nil)
        }
        let detail = detailLine(codex)
        if codex.model == .both {
            return CodexStatus(tone: .warn, sentence: "Two permission models are set, and Codex expects one", detail: detail)
        }
        if let profile = codex.defaultPermissions {
            return CodexStatus(tone: .neutral, sentence: "Takes its permissions from the profile \(quoted(profile))", detail: detail)
        }
        let approval = approval(codex)
        switch codex.sandboxMode {
        case "danger-full-access":
            // Literal to the config: command rules that forbid or prompt still apply, so they are named, not assumed away.
            let held = codex.rules.forbidden + codex.rules.prompt
            let except = approval == "never" && held > 0 ? ", except for \(held) command \(held == 1 ? "rule" : "rules")" : ""
            return CodexStatus(tone: .warn, sentence: "Has no sandbox\(askClause(approval))\(except)", detail: detail)
        case "workspace-write":
            return CodexStatus(tone: approval == "never" ? .neutral : .success, sentence: "Writes only inside the workspace\(askClause(approval))", detail: detail)
        case "read-only":
            return CodexStatus(tone: approval == "never" ? .neutral : .success, sentence: "Only reads files\(askClause(approval))", detail: detail)
        case nil:
            return CodexStatus(tone: .neutral, sentence: "sandbox_mode is not set, so Codex uses its default", detail: detail)
        case let other?:
            return CodexStatus(tone: .neutral, sentence: "Runs with sandbox_mode \(quoted(other))", detail: detail)
        }
    }

    private static func askClause(_ approval: String?) -> String {
        switch approval {
        case "never": " and never asks"
        case "on-request", "on-failure": " and asks when it needs more"
        case "untrusted": " and asks before any command no rule allows"
        case "granular": ", with granular approvals"
        default: ""
        }
    }

    private static func detailLine(_ codex: CoreCodexPermissions) -> String? {
        var parts: [String] = []
        if let mode = codex.sandboxMode { parts.append("sandbox_mode = \(quoted(mode))") }
        if let profile = codex.defaultPermissions { parts.append("default_permissions = \(quoted(profile))") }
        switch codex.approvalPolicy {
        case .mode(let text): parts.append("approval_policy = \(quoted(text))")
        case .granular: parts.append("[approval_policy.granular]")
        case nil: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private static func quoted(_ text: String) -> String {
        let shown = word(text)
        return shown == hiddenText ? shown : "\"\(shown)\""
    }

    // MARK: Rows

    static func rows(_ codex: CoreCodexPermissions) -> [CodexSettingRow] {
        guard codex.present, !codex.notReadable else { return [] }
        var out = [approvalRow(codex)]
        if codex.sandboxMode != nil || codex.defaultPermissions == nil { out += sandboxRows(codex) }
        if let name = codex.defaultPermissions { out += profileRows(codex, name: name) }
        if let reviewer = codex.approvalsReviewer {
            out.append(CodexSettingRow(title: "Approvals reviewed by", key: "approvals_reviewer", value: .tag(word(reviewer), tone: .neutral)))
        }
        return out
    }

    private static func approvalRow(_ codex: CoreCodexPermissions) -> CodexSettingRow {
        let title = "Asks before acting"
        switch codex.approvalPolicy {
        case nil:
            return CodexSettingRow(title: title, key: "approval_policy is not set, so Codex uses its default", keyIsCode: false, value: .tag("not set", tone: .neutral))
        case .granular(let switches):
            return CodexSettingRow(title: title, key: "[approval_policy.granular], \(switches.count) \(switches.count == 1 ? "switch" : "switches")", value: .tag("granular", tone: .neutral))
        case .mode(let text):
            let key = "approval_policy = \(quoted(text))"
            let picked = text == "on-failure" ? "on-request" : text
            guard let title2 = approvalTitles.first(where: { $0.value == picked })?.title else {
                return CodexSettingRow(title: title, key: key, value: .tag(word(text), tone: .neutral))
            }
            return CodexSettingRow(title: title, key: key, value: .options(approvalTitles.map(\.title), picked: title2, warn: picked == "never"))
        }
    }

    private static func sandboxRows(_ codex: CoreCodexPermissions) -> [CodexSettingRow] {
        guard let mode = codex.sandboxMode else {
            return [CodexSettingRow(title: "Sandbox", key: "sandbox_mode is not set, so Codex uses its default", keyIsCode: false, value: .tag("not set", tone: .neutral))]
        }
        let key = "sandbox_mode = \(quoted(mode))"
        guard let picked = sandboxTitles.first(where: { $0.value == mode })?.title else {
            return [CodexSettingRow(title: "Sandbox", key: key, value: .tag(word(mode), tone: .neutral))]
        }
        let sandbox = CodexSettingRow(title: "Sandbox", key: key, value: .options(sandboxTitles.map(\.title), picked: picked, warn: mode == "danger-full-access"))
        switch mode {
        case "danger-full-access":
            return [
                sandbox,
                CodexSettingRow(title: "Network", key: "No sandbox, so nothing limits it", keyIsCode: false, value: .tag("open", tone: .warn)),
                CodexSettingRow(title: "Can write to", key: "Full access ignores writable_roots", keyIsCode: false, value: .tag("anywhere", tone: .warn)),
            ]
        case "read-only":
            return [
                sandbox,
                CodexSettingRow(title: "Network", key: "The read-only sandbox has no network", keyIsCode: false, value: .tag("off", tone: .neutral)),
                CodexSettingRow(title: "Can write to", key: "The read-only sandbox writes nowhere", keyIsCode: false, value: .tag("nowhere", tone: .neutral)),
            ]
        default:
            let write = codex.sandboxWorkspaceWrite
            let network: CodexSettingRow
            if let access = write?.networkAccess {
                network = CodexSettingRow(title: "Network", key: "sandbox_workspace_write.network_access = \(access)", value: .options(networkTitles, picked: access ? "On" : "Off", warn: false))
            } else {
                network = CodexSettingRow(title: "Network", key: "network_access is not set, so Codex uses its default", keyIsCode: false, value: .tag("not set", tone: .neutral))
            }
            let roots = write?.writableRoots.count ?? 0
            let folders = roots == 0 ? "the workspace" : "the workspace and \(roots) more \(roots == 1 ? "folder" : "folders")"
            return [sandbox, network, CodexSettingRow(title: "Can write to", key: "sandbox_workspace_write.writable_roots", value: .tag(folders, tone: .neutral))]
        }
    }

    private static func profileRows(_ codex: CoreCodexPermissions, name: String) -> [CodexSettingRow] {
        let shown = word(name)
        let path = shown == hiddenText ? "permissions.<profile>" : "permissions.\(shown)"
        let profile = codex.profiles.first { $0.name == name }
        let entries = profile?.filesystemEntries ?? 0
        let flags = (profile?.networkFlags ?? []).map { "\(word($0.key)) = \(networkFlagText($0.value))" }
        return [
            CodexSettingRow(title: "Permission profile", key: "default_permissions", value: .tag(shown, tone: .neutral)),
            CodexSettingRow(title: "Files in the profile", key: "\(path).filesystem", value: .tag("\(entries) \(entries == 1 ? "entry" : "entries")", tone: .neutral)),
            CodexSettingRow(title: "Network in the profile", key: "\(path).network", value: .tag(flags.isEmpty ? "no flags" : flags.joined(separator: ", "), tone: .neutral)),
        ]
    }

    /// What a `[permissions.<name>.network]` flag shows. The core keeps any string there, and a string can be a proxy URL
    /// with a password or a token, so text is shown only when it reads as a word such as "limited".
    static func networkFlagText(_ value: CoreFlagValue) -> String {
        switch value {
        case .bool(let flag): String(flag)
        case .number(let number): number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .string(let text): word(text)
        }
    }

    // MARK: Command rules and trust

    /// The per-decision counts of `~/.codex/rules`, strictest first. The patterns are never read into the app.
    static func ruleCounts(_ codex: CoreCodexPermissions) -> [(title: String, meaning: String, count: Int)] {
        let rules = codex.rules
        var out: [(title: String, meaning: String, count: Int)] = [
            ("Forbidden", "Refused without asking", rules.forbidden),
            ("Prompt", "Asks before running", rules.prompt),
            ("Allow", "Runs without asking", rules.allow),
        ]
        if rules.other > 0 { out.append((title: "Other", meaning: "A decision SpaceVibe does not know", count: rules.other)) }
        return out
    }

    static func trustTag(_ level: String?) -> (text: String, tone: TagTone) {
        switch level {
        case "trusted": ("trusted", .success)
        case "untrusted": ("untrusted", .warn)
        case nil: ("unset", .neutral)
        case let other?: (word(other), .neutral)
        }
    }
}
