import Foundation

/// What the Rules tab shows, derived in one place from the global snapshot and the CLIs on this Mac (V5-R53, V5-R67, V5-R68): the
/// state, Codex's reading, the bands, the redundant rules and the Answer. Pure; `RulesModel.page` builds it.
struct RulesPage: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case loading
        /// The core could not be asked at all; the message is its sentence.
        case unreadable(String)
        /// `~/.claude/settings.json` does not parse (or cannot be read): the rules stay hidden and nothing is written over it.
        case invalid(String)
        case empty
        case ready
    }

    let state: State
    let reading: CodexReading
    let layout: RulesLayout
    let answer: RulesAnswer
    /// The rules of the global file, before the Filter.
    let rules: [CoreRule]

    /// `snapshot` counts only when it is the global scope (the tab shows no other); `codexInstalled` is the shell's reading.
    init(snapshot: RulesSnapshot?, failure: String?, codexInstalled: Bool, filter: RulesFilter) {
        let global = snapshot.flatMap { $0.selection == .global ? $0 : nil }
        reading = CodexReading(codex: global?.codex, installed: codexInstalled)
        rules = global?.rules.filter { $0.scope == .global } ?? []
        if let global, !global.problems.isEmpty || global.notReadable {
            state = .invalid(global.problems.first ?? RulesWording.globalNotReadable)
        } else if let global {
            state = global.rules.isEmpty ? .empty : .ready
        } else if let failure {
            state = .unreadable(failure)
        } else {
            state = .loading
        }
        layout = state == .ready ? RulesLayout(rules: rules, reading: reading, filter: filter) : RulesLayout(rules: [], reading: reading, filter: filter)
        answer = RulesAnswer.of(state: state, layout: layout, reading: reading)
    }

    /// Rows the Filter and an empty file leave nothing of.
    var isListEmpty: Bool { layout.bands.isEmpty }
}

/// The Answer card's content (V5-R53, V5-R67): one sentence from one function, then, only when a family is open in one CLI and
/// denied in the other, a Claude Code row with the verdict button and a read-only Codex row, and "Also <families>.".
struct RulesAnswer: Equatable, Sendable {
    /// Nil while loading.
    var sentence: String?
    /// The line under the sentence: an unreadable file's own sentence, or what the sandbox would have to be for a family to be flagged.
    var detail: String?
    var showsRetry = false
    /// The first family that disagrees; the two CLI rows are about it.
    var family: RuleBand?
    var also: [RuleFamily] = []

    var alsoLine: String? { also.isEmpty ? nil : "Also \(also.map(\.title).joined(separator: ", "))." }

    static func of(state: RulesPage.State, layout: RulesLayout, reading: CodexReading) -> RulesAnswer {
        switch state {
        case .loading:
            return RulesAnswer(sentence: nil)
        case .unreadable(let message):
            return RulesAnswer(sentence: "Can't read Claude Code's rules.", detail: message, showsRetry: true)
        case .invalid(let problem):
            return RulesAnswer(sentence: "Can't read Claude Code's rules.", detail: problem, showsRetry: true)
        case .empty:
            return RulesAnswer(sentence: "Claude Code has no rules yet.")
        case .ready:
            break
        }
        switch reading {
        case .notInstalled: return RulesAnswer(sentence: "Nothing to compare: Codex is not installed.")
        case .unknown(let reason): return RulesAnswer(sentence: "Nothing to compare: \(reason.sentence)")
        case .known: break
        }
        guard layout.hasComparison else { return notCompared(reading) }
        guard let first = layout.mismatches.first, let open = first.fact?.isOpen else {
            return RulesAnswer(sentence: "No tool is open in one CLI and denied in the other.")
        }
        let partly = first.allStance.isMixed ? "partly " : ""
        return RulesAnswer(
            sentence: "\(first.family.title): \(open ? "open" : "off") in Codex, \(partly)\(open ? "denied" : "allowed") in Claude Code.",
            family: first, also: layout.mismatches.dropFirst().map(\.family)
        )
    }
}

extension RulesAnswer {
    /// Codex's settings were read but no family with rules has a fact that says on or off. The spine shows `Sandbox: <mode>` beside Bash
    /// and Edit/Write, so the sentence names that sandbox and says what it does and does not decide, from the value the core read.
    static func notCompared(_ reading: CodexReading) -> RulesAnswer {
        let mode = reading.codex?.sandboxMode.map(CodexWording.word) ?? ""
        if CodexFact.of(.edit, reading)?.isOpen != nil {
            // The sandbox is open or off for editing, and Claude Code has no Edit/Write rule that could disagree.
            return RulesAnswer(sentence: "Codex's sandbox is \(mode), and Claude Code has no Edit/Write rule to compare with it.")
        }
        return RulesAnswer(
            sentence: "Codex's sandbox is \(mode), so it opens or closes no tool outright.",
            detail: "Edit/Write would show as open under danger-full-access, or as off under read-only with approvals never."
        )
    }
}

/// The sentences of the tab that no other file owns: the verdict's meaning, the toasts and the empty states.
enum RulesTabWording {
    /// What a verdict means (V5-R68), in the detail popover.
    static func meaning(_ verdict: CoreVerdict) -> String {
        switch verdict {
        case .allow: "Claude Code runs it without asking."
        case .ask: "Claude Code asks you each time."
        case .deny: "Claude Code blocks it."
        }
    }

    static let settingsFile = "~/.claude/settings.json"

    /// "Rules stay hidden until ~/.claude/settings.json parses, so SpaceVibe writes nothing over it."
    static let hiddenUntilParses = "Rules stay hidden until \(settingsFile) parses, so \(SpaceVibeMark.productName) writes nothing over it."

    static let undone = "Undone. \(settingsFile) is back to how it was."

    static func ruleChanged(_ rule: String, to verdict: CoreVerdict) -> String { "\(rule) is now \(RulesWording.title(verdict)) in Claude Code" }

    /// "Edit/Write is now Allow in Claude Code (1 rule changed, 2 path rules kept)": `kept` counts the path rules that keep another verdict.
    static func familyChanged(_ family: RuleFamily, to verdict: CoreVerdict, count: Int, kept: Int = 0) -> String {
        let keptClause = kept > 0 ? ", \(kept) path \(kept == 1 ? "rule" : "rules") kept" : ""
        return "\(family.title) is now \(RulesWording.title(verdict)) in Claude Code (\(count) \(count == 1 ? "rule" : "rules") changed\(keptClause))"
    }

    static func familyUnchanged(_ family: RuleFamily, to verdict: CoreVerdict) -> String {
        "\(family.title) is already \(RulesWording.title(verdict)) in Claude Code."
    }

    /// A family with no wide rule has nothing the family menu can change (C1): nothing is written.
    static func familyNoWide(_ family: RuleFamily) -> String {
        "\(family.title) has no rule for the whole tool, so there is nothing to change. Path rules keep their verdicts."
    }

    static func removed(_ rule: String) -> String { "Removed \(rule) from \(settingsFile)" }

    /// A row's spoken name.
    static func spoken(_ rule: CoreRule) -> String { "\(rule.rule), \(RulesWording.title(rule.verdict)) in Claude Code" }

    /// "Covered by <pattern>" on a redundant rule's row.
    static func coveredBy(_ rule: CoreRule) -> String { "Covered by \(rule.rule)" }

    /// The band's count label for the card header: "3 rules".
    static func countLabel(_ count: Int) -> String { "\(count) \(count == 1 ? "rule" : "rules")" }
}

/// A verdict menu of the tab: one rule's (from its detail popover) or a whole family's (from the Answer).
enum VerdictTarget: Hashable, Sendable {
    case rule(String)
    case family(RuleFamily)

    var id: String {
        switch self {
        case .rule(let id): "rule:\(id)"
        case .family(let family): "family:\(family.rawValue)"
        }
    }
}
