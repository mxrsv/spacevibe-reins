import ReinsCore

/// Words and tones for verdicts, grid states and the confirmation. Pure.
enum RulesWording {
    static let verdicts: [RuleVerdict] = [.allow, .ask, .deny]
    /// The rule list reads strictest first.
    static let listOrder: [RuleVerdict] = [.deny, .ask, .allow]

    static func title(_ verdict: RuleVerdict) -> String {
        switch verdict {
        case .allow: "Allow"
        case .ask: "Ask"
        case .deny: "Deny"
        }
    }

    static func groupTitle(_ verdict: RuleVerdict) -> String {
        verdict == .ask ? "Ask first" : title(verdict)
    }

    static func tone(_ verdict: RuleVerdict) -> TagTone {
        switch verdict {
        case .allow: .neutral
        case .ask: .warn
        case .deny: .danger
        }
    }

    static func stateLabel(_ state: CapabilityState) -> String {
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

    static func setLabel(_ capability: Capability, _ verdict: RuleVerdict) -> String {
        "Set \(capability.label) to \(title(verdict))"
    }
}

/// A grid write waiting for the user's confirmation: what `previewSetCapability` says it replaces and writes.
struct RulesPending: Equatable {
    let preview: CapabilityPreview
    let scopeTitle: String

    var capability: Capability { preview.capability }
    var verdict: RuleVerdict { preview.verdict }
    var question: String { "\(RulesWording.setLabel(capability, verdict))?" }
    var location: String { "In \(scopeTitle), \(preview.scopeLabel)." }

    /// The file already holds exactly what the write would produce.
    var isNoOp: Bool { Set(preview.replaces) == Set(preview.writes) }

    /// A rule that is kept (for example a bare `Bash` ask under Push and deploy) still wins over what is written.
    var warning: String? {
        guard preview.resulting != CapabilityState(rawValue: verdict.rawValue) else { return nil }
        return "A rule that stays in this file still wins, so \(capability.label) will read \(RulesWording.stateLabel(preview.resulting)), not \(RulesWording.title(verdict))."
    }
}
