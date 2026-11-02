import Foundation

/// What Claude Code does when a tool call matches a rule. Raw values are the keys of `permissions` in settings.json.
public enum RuleVerdict: String, CaseIterable, Sendable {
    case allow, ask, deny

    /// Capitalised for sentences such as the journal label: "Set Run commands to Deny".
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// One row of the capability grid. Same ids and order as `CAPABILITIES` in core/rules.mjs.
public enum Capability: String, CaseIterable, Sendable {
    case read, edit, run, network, push, secrets

    public var label: String {
        switch self {
        case .read: return "Read files"
        case .edit: return "Edit files"
        case .run: return "Run commands"
        case .network: return "Network"
        case .push: return "Push and deploy"
        case .secrets: return "Secrets (.env)"
        }
    }
}

/// The value of a grid cell. `mixed` means rules for specific paths or commands disagree, so there is no single value to show or write.
public enum CapabilityState: String, Sendable {
    case allow, ask, deny, mixed, none
}

/// Where a rule lives: the global `settings.json`, or a project's `settings.json` / `settings.local.json`.
public enum RuleScope: Equatable, Hashable, Sendable {
    case global
    case project(String)
    case local(String)

    public var kind: String {
        switch self {
        case .global: return "global"
        case .project: return "project"
        case .local: return "local"
        }
    }

    public var dir: String? {
        switch self {
        case .global: return nil
        case .project(let dir), .local(let dir): return dir
        }
    }

    /// The scopes shown for a project: global, project, local (just global without a project).
    public static func scopes(for dir: String?) -> [RuleScope] {
        guard let dir else { return [.global] }
        return [.global, .project(dir), .local(dir)]
    }

    /// Short name of the settings file, without any folder: safe to show next to a preview.
    public var fileLabel: String {
        switch self {
        case .global: return "~/.claude/settings.json"
        case .project: return ".claude/settings.json"
        case .local: return ".claude/settings.local.json"
        }
    }

    /// Used in journal labels, as in core/rules.mjs.
    var journalLabel: String { dir.map { "\(kind) \($0)" } ?? "global" }
}

/// `Tool` or `Tool(specifier)`. The specifier is kept as written (not trimmed); nil when absent or blank.
public struct ParsedRule: Equatable, Sendable {
    public let tool: String
    public let specifier: String?
}

public struct VerdictRule: Equatable, Hashable, Sendable {
    public let verdict: RuleVerdict
    public let rule: String

    public init(verdict: RuleVerdict, rule: String) {
        self.verdict = verdict
        self.rule = rule
    }
}

/// One rule string found in a settings file, or a synthetic one (`id` empty) built to ask what a grid would say.
public struct RuleItem: Equatable, Sendable {
    public let id: String
    public let scope: RuleScope
    /// The settings file the rule came from; empty for a synthetic rule.
    public let file: String
    public let verdict: RuleVerdict
    public let rule: String
    public let tool: String?
    public let specifier: String?

    public init(scope: RuleScope, file: String, verdict: RuleVerdict, rule: String) {
        let parsed = Rules.parseRule(rule)
        self.id = "\(scope.kind):\(verdict.rawValue):\(rule)"
        self.scope = scope
        self.file = file
        self.verdict = verdict
        self.rule = rule
        self.tool = parsed?.tool
        self.specifier = parsed?.specifier
    }

    /// A rule that is not in any file, for `capabilityGrid` what-if questions.
    init(verdict: RuleVerdict, rule: String) {
        self.init(scope: .global, file: "", verdict: verdict, rule: rule)
    }

    public var entry: VerdictRule { VerdictRule(verdict: verdict, rule: rule) }
}

public struct RuleListing: Equatable, Sendable {
    public let rules: [RuleItem]
    /// One sentence per file that could not be read as settings. Names the file, never quotes it.
    public let problems: [String]
}

public struct CapabilityCell: Equatable, Sendable {
    public let capability: Capability
    public let label: String
    public let state: CapabilityState
    /// False for `mixed`: the engine refuses to write it.
    public let editable: Bool
    /// The concrete rules behind the state: wide first, then the cell's own, then narrow.
    public let rules: [RuleItem]
}

/// What `setCapability` would remove and write. Carries no absolute path.
public struct CapabilityPreview: Equatable, Sendable {
    public let capability: Capability
    public let verdict: RuleVerdict
    /// "~/.claude/settings.json" or ".claude/settings.json" / ".claude/settings.local.json".
    public let scopeLabel: String
    public let current: CapabilityState
    /// Differs from `verdict` when a rule that is kept (for example a bare `Bash` deny for Push and deploy) still wins.
    public let resulting: CapabilityState
    public let replaces: [VerdictRule]
    public let writes: [VerdictRule]
}
