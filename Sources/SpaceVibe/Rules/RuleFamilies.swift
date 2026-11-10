import Foundation

// What the Rules tab derives from `rules.snapshot` (V5-R67): a rule's family, a family's Claude Code stance, the one Codex fact a
// family has (C18, G12), the families that are open in one CLI and denied in the other, and the rules another rule already covers.
// A family is judged by its wide rules only (owner call C1, 2026-11-10): a rule scoped to a path (`Edit(~/.ssh/**)`) narrows a tool, so
// it never says the family is denied or allowed. Pure: no view and no model, so `RuleFamiliesTests` drives it.

/// The tool families of the Permissions spine. `other` holds every rule outside the five of the mock (a `Skill`, `Task` or
/// `NotebookEdit` rule), so the tab's count is the number of rules listed and no rule is hidden.
enum RuleFamily: String, CaseIterable, Identifiable, Sendable {
    case bash, edit, read, web, mcp, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bash: "Bash"
        case .edit: "Edit/Write"
        case .read: "Read"
        case .web: "Web"
        case .mcp: "MCP"
        case .other: "Other tools"
        }
    }

    /// The family of a rule's tool (`CoreRule.tool`, the name before the parenthesis). `Edit`, `Write` and `MultiEdit` are the three
    /// the core's Edit capability reads (`core/internal/rules/grid.go`), so the spine and `rules.setCapability` agree on what editing is.
    static func of(tool: String?) -> RuleFamily {
        switch tool {
        case "Bash": .bash
        case "Edit", "Write", "MultiEdit": .edit
        case "Read": .read
        case "WebFetch", "WebSearch": .web
        case let tool? where tool.hasPrefix("mcp__"): .mcp
        default: .other
        }
    }
}

extension CoreRule {
    /// A bare tool, `Tool()` or `Tool(*)`: the rule covers every use of the tool (the core's `isWide`, `core/internal/rules/parse.go`).
    /// Any other specifier is a path or pattern rule.
    var isWide: Bool { RedundantRules.isWide(specifier) }
}

/// A family's Claude Code stance (V5-R67): the one verdict all its rules share, or how many rules each verdict holds.
struct FamilyStance: Equatable, Sendable {
    let counts: [CoreVerdict: Int]

    init(_ rules: [CoreRule]) {
        counts = Dictionary(grouping: rules, by: \.verdict).mapValues(\.count)
    }

    /// The one verdict, nil when the rules disagree or there are none.
    var single: CoreVerdict? { counts.count == 1 ? counts.keys.first : nil }

    var isMixed: Bool { counts.count > 1 }

    func has(_ verdict: CoreVerdict) -> Bool { (counts[verdict] ?? 0) > 0 }

    /// `Deny`, or `Allow 12 · Ask 5 · Deny 7`.
    var summary: String {
        if let single { return RulesWording.title(single) }
        return CoreVerdict.allCases.compactMap { verdict in counts[verdict].map { "\(RulesWording.title(verdict)) \($0)" } }.joined(separator: " \u{00B7} ")
    }
}

// MARK: Codex

/// What the page can say about Codex (C18, G12): nothing when it is not installed, nothing comparable when its permission settings
/// are unknown or come from a profile, else the settings the core read.
enum CodexReading: Equatable, Sendable {
    /// Why no setting can stand next to a rule.
    enum Reason: Equatable, Sendable {
        case notRead, notReadable, noFile, bothModels, profile, noSandbox

        /// The sentence after "Nothing to compare:".
        var sentence: String {
            switch self {
            case .notRead: "Codex's settings were not read."
            case .notReadable: "~/.codex/config.toml can't be read."
            case .noFile: "there is no ~/.codex/config.toml."
            case .bothModels: "Codex has two permission models set."
            case .profile: "Codex takes its permissions from a profile."
            case .noSandbox: "sandbox_mode is not set in ~/.codex/config.toml."
            }
        }
    }

    case notInstalled
    case unknown(Reason)
    case known(CoreCodexPermissions)

    init(codex: CoreCodexPermissions?, installed: Bool) {
        guard installed else { self = .notInstalled; return }
        guard let codex else { self = .unknown(.notRead); return }
        if codex.notReadable { self = .unknown(.notReadable) }
        else if !codex.present { self = .unknown(.noFile) }
        else if codex.model == .both { self = .unknown(.bothModels) }
        else if codex.model == .profiles || codex.defaultPermissions != nil { self = .unknown(.profile) }
        else if codex.sandboxMode == nil { self = .unknown(.noSandbox) }
        else { self = .known(codex) }
    }

    var codex: CoreCodexPermissions? {
        if case .known(let codex) = self { codex } else { nil }
    }

    /// "Codex is read only here. Approval policy <value>, from ~/.codex/config.toml." Only while the file was read.
    var note: String? {
        switch self {
        case .known(let codex):
            "Codex is read only here. Approval policy \(CodexWording.approval(codex).map(CodexWording.word) ?? "not set"), from ~/.codex/config.toml."
        case .unknown(let reason) where reason == .bothModels || reason == .profile:
            "Codex is read only here. \(reason.sentence) Its settings are not compared with these rules."
        case .unknown, .notInstalled: nil
        }
    }
}

/// The one Codex setting that sits beside a family, in Codex's own terms (C18). `isOpen` is set only for a fact that says a tool is
/// on or off; a sandbox mode that is neither (`workspace-write`) is shown and never compared.
struct CodexFact: Equatable, Sendable {
    let label: String
    let value: String
    let isOpen: Bool?

    var text: String { "\(label): \(value)" }

    /// G12, settled against what `CoreCodexPermissions` holds and Codex's own pages (read 2026-11-08):
    /// - Bash and Edit/Write: `sandbox_mode`, which says where commands and edits can reach. Only Edit/Write compares it, and only where
    ///   Codex cannot step past it: `danger-full-access` ("no sandbox") writes anywhere, which is open; `read-only` is off only when
    ///   `approval_policy` is `never` (with any other policy Codex may ask to go past the sandbox, so the setting alone does not say
    ///   off; Hypothesis, unverified: the pages describe presets of both settings, not this pair); `workspace-write` is neither.
    /// - Read, Web, MCP, Other tools: none. No sandbox mode limits reads. `sandbox_workspace_write.network_access` is the network of
    ///   commands, "separate from" Codex's web search tool, which has its own `web_search` key that the core does not read (the
    ///   mock's Web: Network and MCP: Project trust rows are not used: a project's trust level is about project config, not MCP).
    static func of(_ family: RuleFamily, _ reading: CodexReading) -> CodexFact? {
        guard let codex = reading.codex, let mode = codex.sandboxMode, family == .bash || family == .edit else { return nil }
        let never = CodexWording.approval(codex) == "never"
        let isOpen: Bool? = family == .edit ? (mode == "danger-full-access" ? true : mode == "read-only" && never ? false : nil) : nil
        return CodexFact(label: "Sandbox", value: CodexWording.word(mode), isOpen: isOpen)
    }
}

// MARK: Redundant rules

/// A rule another rule with the same verdict already covers.
struct RedundantRule: Identifiable, Equatable, Sendable {
    let rule: CoreRule
    let by: CoreRule

    var id: String { rule.id }
}

enum RedundantRules {
    /// A rule is redundant when one with the same verdict already matches everything it matches. Only the forms where that is certain
    /// count (the mock's three): a bare tool (`Bash`, `Bash(*)`) over any rule of the same tool, `mcp__server` over `mcp__server__tool`,
    /// and a Bash prefix (`Bash(git push:*)` or `Bash(git push *)`) over a longer command. Two rules that cover each other keep
    /// the earlier one. A rule written twice is one rule here (they share an id), so Remove never takes the covering copy too.
    static func of(_ rules: [CoreRule]) -> [RedundantRule] {
        var seen = Set<String>()
        let unique = rules.filter { seen.insert($0.id).inserted }
        return unique.enumerated().compactMap { index, rule in
            let cover = unique.enumerated().first { other in
                other.offset != index && covers(other.element, rule) && (!covers(rule, other.element) || other.offset < index)
            }
            return cover.map { RedundantRule(rule: rule, by: $0.element) }
        }
    }

    static func covers(_ outer: CoreRule, _ inner: CoreRule) -> Bool {
        guard outer.verdict == inner.verdict, let tool = outer.tool, let innerTool = inner.tool else { return false }
        if tool == innerTool, isWide(outer.specifier) { return true }
        if tool.hasPrefix("mcp__"), outer.specifier == nil, innerTool.hasPrefix(tool + "__") { return true }
        guard tool == "Bash", innerTool == "Bash", let prefix = commandPrefix(outer.specifier), let command = command(inner.specifier) else { return false }
        return command == prefix || command.hasPrefix(prefix + " ")
    }

    static func isWide(_ specifier: String?) -> Bool {
        guard let specifier else { return true }
        let trimmed = specifier.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "*"
    }

    /// The command a Bash rule matches by prefix: `git push` for `git push:*` and for `git push *`; nil for an exact command.
    private static func commandPrefix(_ specifier: String?) -> String? {
        guard let specifier else { return nil }
        for suffix in [":*", " *"] where specifier.hasSuffix(suffix) { return String(specifier.dropLast(suffix.count)) }
        return nil
    }

    /// The command text of a Bash rule, with its wildcard suffix removed.
    private static func command(_ specifier: String?) -> String? {
        guard let specifier else { return nil }
        return commandPrefix(specifier) ?? specifier
    }
}

// MARK: Filter

/// The one field of the Rules tab's Filter (V5-R61, V5-R68): the verdict in Claude Code, so the menu has one level.
enum RulesFilterField: String, FilterFieldKind {
    case verdict

    var title: String { "Verdict in Claude Code" }

    var chipTitle: String { "Verdict" }

    var values: [FilterValue] { CoreVerdict.allCases.map { FilterValue($0.rawValue, RulesWording.title($0)) } }
}

typealias RulesFilter = PickFilter<RulesFilterField>

// MARK: Bands

/// One family of the spine: its rules (after the Filter), Claude Code's stance, Codex's fact and whether the two disagree.
struct RuleBand: Identifiable, Equatable, Sendable {
    let family: RuleFamily
    /// The rules the Filter leaves.
    let rules: [CoreRule]
    /// Every rule of the family, whatever the Filter says.
    let all: [CoreRule]
    let fact: CodexFact?
    let holdsProblem: Bool

    var id: String { family.rawValue }
    /// What the header says: the verdicts of the rules listed, path rules included.
    var stance: FamilyStance { FamilyStance(rules) }
    /// The family's verdict (C1): the stance of its wide rules, whatever the Filter says. The Answer and the family's verdict menu read
    /// this one, and the menu changes exactly these rules.
    var allStance: FamilyStance { FamilyStance(all.filter(\.isWide)) }
}

/// The spine's bands in order: the families open in one CLI and denied in the other first (they open), then the rest in family order;
/// a family with no rule after the Filter is left out (V5-R67).
struct RulesLayout: Equatable, Sendable {
    let bands: [RuleBand]
    /// The families that disagree, in family order, whatever the Filter says (the Answer reads these).
    let mismatches: [RuleBand]
    /// At least one family with rules has a Codex fact that says on or off: only then can "nothing is open in one CLI and denied in the
    /// other" be said (otherwise nothing was compared).
    let hasComparison: Bool
    let redundant: [RedundantRule]

    init(rules: [CoreRule], reading: CodexReading, filter: RulesFilter) {
        let unique = Self.unique(rules)
        let all = RuleFamily.allCases.map { family -> RuleBand in
            let members = unique.filter { RuleFamily.of(tool: $0.tool) == family }
            let fact = CodexFact.of(family, reading)
            let stance = FamilyStance(members.filter(\.isWide))
            let disagrees = (fact?.isOpen == true && stance.has(.deny)) || (fact?.isOpen == false && stance.has(.allow))
            let shown = filter.isOn ? members.filter { filter.isPicked(.verdict, $0.verdict.rawValue) } : members
            return RuleBand(family: family, rules: shown, all: members, fact: fact, holdsProblem: disagrees)
        }
        mismatches = all.filter(\.holdsProblem)
        hasComparison = all.contains { !$0.all.isEmpty && $0.fact?.isOpen != nil }
        let listed = all.filter { !$0.rules.isEmpty }
        bands = listed.filter(\.holdsProblem) + listed.filter { !$0.holdsProblem }
        redundant = RedundantRules.of(unique)
    }

    /// A rule written twice in one file has one id: it is one row.
    static func unique(_ rules: [CoreRule]) -> [CoreRule] {
        var seen = Set<String>()
        return rules.filter { seen.insert($0.id).inserted }
    }

    /// The rows in the order the keys walk them: the rows of every band in `bands` the caller lists as open.
    func rows(inOpen isOpen: (RuleBand) -> Bool) -> [CoreRule] { bands.filter(isOpen).flatMap(\.rules) }
}
