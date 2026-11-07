import Foundation

/// In-memory rules, a Codex reading and a snapshot for the Rules shots and tests: the states the synthetic home cannot hold (a family
/// open in Codex and denied in Claude Code with other families, a redundant rule, 60 rules). Names are made up (S-R2).
enum RulesSynthetic {
    static let file = RulesTabWording.settingsFile

    /// `Tool(specifier)` or a bare `Tool`, as the core lists it.
    static func rule(_ text: String, _ verdict: CoreVerdict) -> CoreRule {
        let open = text.firstIndex(of: "(")
        let tool = open.map { String(text[..<$0]) } ?? text
        let specifier = open.flatMap { start in text.hasSuffix(")") ? String(text[text.index(after: start) ..< text.index(before: text.endIndex)]) : nil }
        return CoreRule(id: "global:\(verdict.rawValue):\(text)", scope: .global, dir: nil, file: file, verdict: verdict, rule: text, tool: tool, specifier: specifier)
    }

    /// The mock's set (`system/data.js`), with a deny on `~/.ssh` for Edit so the family is mixed, and one rule another covers.
    static let sample: [CoreRule] = {
        let allowBash = ["git status:*", "git diff:*", "git log:*", "git add:*", "git commit:*", "pnpm test:*", "pnpm tsc:*", "pnpm eslint:*", "pnpm run build", "ls:*", "rg:*", "cat:*"]
        let askBash = ["pnpm install:*", "pnpm add:*", "curl:*", "docker:*", "gh pr merge:*"]
        let denyBash = ["git push:*", "git push --force:*", "rm -rf:*", "sudo:*", "git reset --hard:*", "pnpm publish:*", "chmod -R:*"]
        return allowBash.map { rule("Bash(\($0))", .allow) } + askBash.map { rule("Bash(\($0))", .ask) } + denyBash.map { rule("Bash(\($0))", .deny) }
            + [rule("Edit(src/**)", .allow), rule("Write(src/**)", .allow), rule("Edit(docs/**)", .allow), rule("Edit(~/.ssh/**)", .deny)]
            + [rule("Read(./.env)", .deny), rule("Read(./.env.*)", .deny), rule("Read(~/.ssh/**)", .deny)]
            + [rule("WebFetch", .deny), rule("WebSearch", .deny)]
            + [rule("mcp__playwright", .allow), rule("mcp__tolaria", .allow), rule("mcp__neon__run_sql", .ask), rule("mcp__neon__delete_project", .deny)]
            + [rule("Skill(deploy)", .ask)]
    }()

    /// `sample` without the rule another covers.
    static let healthy: [CoreRule] = {
        let redundant = Set(RedundantRules.of(sample).map(\.id))
        return sample.filter { !redundant.contains($0.id) }
    }()

    /// 60 rules (the mock's "many"): the sample and more written like it.
    static let many: [CoreRule] = sample + (1 ... 60 - sample.count).map { n in
        switch n % 4 {
        case 0: rule("Bash(pnpm run lint-pkg-\(n):*)", .allow)
        case 1: rule("Edit(packages/pkg-\(n)/**)", .allow)
        case 2: rule("WebFetch(domain:site-\(n).dev)", .ask)
        default: rule("mcp__playwright__tool-\(n)", .ask)
        }
    }

    /// A Codex reading: `sandbox` is `sandbox_mode`; nil means the file does not set it.
    static func codex(sandbox: String? = "workspace-write", approval: String? = "on-request", present: Bool = true, model: CoreCodexModel = .legacy,
                      profile: String? = nil, notReadable: Bool = false) -> CoreCodexPermissions {
        CoreCodexPermissions(
            present: present, model: model, unrestricted: false, warnings: [], approvalPolicy: approval.map { .mode($0) }, sandboxMode: sandbox,
            sandboxWorkspaceWrite: nil, defaultPermissions: profile, approvalsReviewer: nil, profiles: [], projects: [],
            rules: CoreCodexRulesSummary(files: 0, allow: 0, prompt: 0, forbidden: 0, other: 0, unreadable: 0, folderNotReadable: false),
            notReadable: notReadable, skippedLines: 0
        )
    }

    /// The snapshot `rules.snapshot` would answer for the global scope.
    static func snapshot(_ rules: [CoreRule], codex: CoreCodexPermissions = codex(), problems: [String] = [], notReadable: Bool = false) -> RulesSnapshot {
        RulesSnapshot(CoreRulesSnapshot(
            projectDirs: [], globalRuleCount: rules.count, scope: .global, dir: nil, fileLabel: file, exists: true, problems: problems, rules: rules, grid: [],
            codex: codex, notReadable: notReadable, globalNotReadable: notReadable
        ))
    }
}
