/// Words and tones for verdicts, grid states and the confirmation. Pure.
enum RulesWording {
    static let verdicts: [CoreVerdict] = [.allow, .ask, .deny]
    /// The rule list reads strictest first.
    static let listOrder: [CoreVerdict] = [.deny, .ask, .allow]

    static func title(_ verdict: CoreVerdict) -> String {
        switch verdict {
        case .allow: "Allow"
        case .ask: "Ask"
        case .deny: "Deny"
        }
    }

    static func groupTitle(_ verdict: CoreVerdict) -> String {
        verdict == .ask ? "Ask first" : title(verdict)
    }

    static func tone(_ verdict: CoreVerdict) -> TagTone {
        switch verdict {
        case .allow: .neutral
        case .ask: .warn
        case .deny: .danger
        }
    }

    static func stateLabel(_ state: CoreCapabilityState) -> String {
        switch state {
        case .allow: "Allow"
        case .ask: "Ask"
        case .deny: "Deny"
        case .mixed: "mixed"
        case .none: "no rule"
        }
    }

    /// Where a "mixed" cell's tag explains itself (tooltip and accessibility hint).
    static let mixedHelp = "Disabled because this cell holds rules for specific paths or commands, so it has no single value. Edit those rules in the list below."

    static let invalidFileHelp = "Disabled because the settings file is not valid JSON."

    static func ruleCount(_ count: Int) -> String {
        count == 0 ? "" : "\(count) \(count == 1 ? "rule" : "rules")"
    }

    /// The Claude Code side in one line, for the Codex page's summary bar: what the scope's file asks before and blocks.
    static func summary(_ grid: [CoreCapabilityCell], ruleCount: Int) -> String {
        let asks = grid.filter { $0.state == .ask }.map { object($0.capability) }
        let blocks = grid.filter { $0.state == .deny }.map { object($0.capability) }
        var parts: [String] = []
        if !asks.isEmpty { parts.append("asks before \(list(asks))") }
        if !blocks.isEmpty { parts.append("blocks \(list(blocks))") }
        guard let first = parts.first else {
            return ruleCount == 0 ? "No rules in this file" : "\(Self.ruleCount(ruleCount)) here, none decides a whole row"
        }
        let sentence = ([first] + parts.dropFirst()).joined(separator: ", ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    private static func object(_ capability: CoreCapability) -> String {
        switch capability {
        case .read: "reading files"
        case .edit: "editing files"
        case .run: "running commands"
        case .network: "network access"
        case .push: "push and deploy"
        case .secrets: "secrets (.env)"
        }
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    static func setLabel(_ capabilityLabel: String, _ verdict: CoreVerdict) -> String {
        "Set \(capabilityLabel) to \(title(verdict))"
    }

    /// Shown with the other banners when the global file could not be read while another scope is on screen: the badge and
    /// the Global scope cannot count rules they could not see.
    /// The core's warnings for the Codex page besides the two-models one (which has its own banner and comes first): what it
    /// could not read or understand in `config.toml` and `~/.codex/rules`. Fixed sentences with counts only.
    static func codexNotices(_ codex: CoreCodexPermissions) -> [String] {
        codex.model == .both ? Array(codex.warnings.dropFirst()) : codex.warnings
    }

    static let globalNotReadable = "~/.claude/settings.json could not be read, so its rules are not counted."
}

/// A grid write waiting for the user's confirmation: what `rules.preview` says it replaces and writes.
///
/// It carries the scope the preview was made for, and the write goes to exactly that scope, never to whatever is selected
/// when Confirm is pressed.
struct RulesPending: Equatable {
    let preview: CoreCapabilityPreview
    let scope: RulesScope
    let scopeTitle: String
    /// The grid row's own label ("Push and deploy"), as the core names the capability.
    let capabilityLabel: String

    var capability: CoreCapability { preview.capability }
    var verdict: CoreVerdict { preview.verdict }
    var question: String { "\(RulesWording.setLabel(capabilityLabel, verdict))?" }
    var location: String { "Writes to \(scopeTitle): \(preview.scopeLabel)." }

    /// The file already holds exactly what the write would produce.
    var isNoOp: Bool { Set(preview.replaces) == Set(preview.writes) }

    /// What to tell the user instead of opening a confirmation for a write that changes nothing. The cell may still read
    /// something else because a rule that stays wins, so the words come from the resulting state.
    var noOpMessage: String {
        if preview.resulting == CoreCapabilityState(rawValue: verdict.rawValue) {
            return "\(capabilityLabel) already reads \(RulesWording.title(verdict)) here."
        }
        return "\(capabilityLabel) stays \(RulesWording.stateLabel(preview.resulting)) here: a rule that stays in this file wins."
    }

    /// A rule that is kept (for example a bare `Bash` ask under Push and deploy) still wins over what is written.
    var warning: String? {
        guard preview.resulting != CoreCapabilityState(rawValue: verdict.rawValue) else { return nil }
        return "A rule that stays in this file still wins, so \(capabilityLabel) will read \(RulesWording.stateLabel(preview.resulting)), not \(RulesWording.title(verdict))."
    }
}
