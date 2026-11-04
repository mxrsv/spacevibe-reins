import Foundation
import ReinsCore

/// What a draft item does to which file. Each case maps to one engine edit, so a save is exactly the draft.
enum DraftChange: Equatable {
    case claude(ClaudeSettingsEdit.Change)
    case mcp(MCPEdit.Change)
    case codex(CodexConfigEdit.Change)
    case codexRule(file: URL, CodexRulesFile.Change)
    case codexHook(CodexHooksFile.Change)
    /// New text for an instruction file (the panel's file or one it imports).
    case text(file: URL, String)
    /// The Advanced editor's whole (masked) text.
    case advanced(String)
}

/// One line of the review: the verb, what it touches, an optional verdict tag and the consequence of a risky value.
struct DraftItem: Identifiable, Equatable {
    enum Verb: String {
        case add = "Add", remove = "Remove", change = "Change", replace = "Replace", edit = "Edit"
    }

    let id: Int
    let verb: Verb
    let text: String
    var tag: String?
    var tagTone: TagTone = .neutral
    var warning: String?
    let change: DraftChange
}

/// The draft of the open panel: items in the order they were made. An edit to the same thing replaces the earlier item
/// (one Edit per instruction file, one mode change, one model), so the count is what the review will list.
struct AgentDraft: Equatable {
    private(set) var items: [DraftItem] = []
    private var next = 0

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    mutating func add(_ verb: DraftItem.Verb, _ text: String, tag: String? = nil, tone: TagTone = .neutral, warning: String? = nil, _ change: DraftChange) {
        if let index = items.firstIndex(where: { Self.sameTarget($0.change, change) }) {
            // Undoing an earlier add or remove of the same thing cancels both.
            if Self.cancels(items[index].change, change) { items.remove(at: index); return }
            items.remove(at: index)
        }
        next += 1
        items.append(DraftItem(id: next, verb: verb, text: text, tag: tag, tagTone: tone, warning: warning, change: change))
    }

    mutating func clear() { items = [] }

    mutating func remove(where match: (DraftChange) -> Bool) { items.removeAll { match($0.change) } }

    var claudeChanges: [ClaudeSettingsEdit.Change] { items.compactMap { if case .claude(let c) = $0.change { return c } else { return nil } } }
    var mcpChanges: [MCPEdit.Change] { items.compactMap { if case .mcp(let c) = $0.change { return c } else { return nil } } }
    var codexChanges: [CodexConfigEdit.Change] { items.compactMap { if case .codex(let c) = $0.change { return c } else { return nil } } }
    var codexHookChanges: [CodexHooksFile.Change] { items.compactMap { if case .codexHook(let c) = $0.change { return c } else { return nil } } }

    func text(for file: URL) -> String? {
        for item in items.reversed() { if case .text(let url, let text) = item.change, url == file { return text } }
        return nil
    }

    var advancedText: String? {
        for item in items.reversed() { if case .advanced(let text) = item.change { return text } }
        return nil
    }

    func rules(for file: URL) -> [CodexRulesFile.Change] {
        items.compactMap { if case .codexRule(let url, let c) = $0.change, url == file { return c } else { return nil } }
    }

    /// Two changes that set the same thing: the later one wins.
    static func sameTarget(_ a: DraftChange, _ b: DraftChange) -> Bool {
        switch (a, b) {
        case (.claude(.defaultMode), .claude(.defaultMode)), (.claude(.model), .claude(.model)), (.advanced, .advanced): return true
        case (.text(let x, _), .text(let y, _)): return x == y
        case (.codex(let x), .codex(let y)): return codexKey(x) != nil && codexKey(x) == codexKey(y)
        default: return a == b || cancels(a, b)
        }
    }

    /// An add followed by the matching remove (or the reverse) leaves the file as it was.
    static func cancels(_ a: DraftChange, _ b: DraftChange) -> Bool {
        switch (a, b) {
        case (.claude(.addRule(let v1, let r1)), .claude(.removeRule(let v2, let r2))), (.claude(.removeRule(let v1, let r1)), .claude(.addRule(let v2, let r2))):
            return v1 == v2 && r1 == r2
        case (.claude(.addDirectory(let x)), .claude(.removeDirectory(let y))), (.claude(.removeDirectory(let x)), .claude(.addDirectory(let y))):
            return x == y
        default:
            return false
        }
    }

    /// Codex settings that hold one value: a later change to the same key replaces the earlier one.
    private static func codexKey(_ change: CodexConfigEdit.Change) -> String? {
        switch change {
        case .approvalPolicy: "approval"
        case .sandboxMode: "sandbox"
        case .networkAccess: "network"
        case .writableRoots: "roots"
        case .trust(let project, _): "trust:\(project)"
        case .model: "model"
        case .reasoningEffort: "effort"
        case .defaultPermissions: "profile"
        case .keepModel: "keep"
        case .profileExtends(let profile, _): "extends:\(profile)"
        case .networkEnabled(let profile, _): "net:\(profile)"
        case .networkProxy: "proxy"
        case .pathRule(let profile, let path, _): "path:\(profile):\(path)"
        case .domain(let profile, let host, _): "domain:\(profile):\(host)"
        case .addServer, .removeServer, .replaceSecret: nil
        }
    }
}

/// Builds the files a save writes from a draft (plan A8): one `AgentFileChange` per file, all in one journal entry.
enum AgentsSavePlan {
    struct Context {
        let roots: Roots
        let projects: [String]
        let agent: AgentKind
        let panel: AgentPanel
        let scope: RuleScope
        /// The masked text the Advanced editor opened, to put the secrets back.
        var masked: MaskedText?
    }

    static func changes(_ draft: AgentDraft, _ context: Context) throws -> [AgentFileChange] {
        let roots = context.roots
        var out: [AgentFileChange] = []
        var texts: [URL] = []
        var ruleFiles: [URL] = []
        for item in draft.items {
            switch item.change {
            case .text(let file, _): if !texts.contains(file) { texts.append(file) }
            case .codexRule(let file, _): if !ruleFiles.contains(file) { ruleFiles.append(file) }
            default: break
            }
        }
        for file in texts { if let text = draft.text(for: file) { out.append(InstructionFile.fileChange(file, text: text)) } }
        if !draft.claudeChanges.isEmpty { out.append(ClaudeSettingsEdit.fileChange(try settingsFile(context), draft.claudeChanges)) }
        if !draft.mcpChanges.isEmpty {
            switch context.scope {
            case .global: out.append(ClaudeStateMCP.fileChange(roots, project: nil, draft.mcpChanges))
            case .local(let dir): out.append(ClaudeStateMCP.fileChange(roots, project: dir, draft.mcpChanges))
            case .project(let dir): out.append(MCPFile.fileChange(project: dir, draft.mcpChanges))
            }
        }
        if !draft.codexChanges.isEmpty { out.append(CodexConfigEdit.fileChange(codexConfigFile(roots), draft.codexChanges)) }
        for file in ruleFiles { out.append(CodexRulesFile.fileChange(file, draft.rules(for: file))) }
        if !draft.codexHookChanges.isEmpty { out.append(CodexHooksFile.fileChange(roots, draft.codexHookChanges)) }
        if let text = draft.advancedText, let masked = context.masked {
            let file = context.agent == .claude ? try settingsFile(context) : codexConfigFile(roots)
            let check: @Sendable (String) throws -> Void
            if context.agent == .claude { check = AgentsSavePlan.checkJSON } else { check = CodexConfigEdit.check }
            out.append(AgentSave.advancedChange(file, masked: masked, edited: text, check: check))
        }
        return out
    }

    /// The Advanced editor's check for a Claude settings file: valid JSON, naming the line when it is not.
    static func checkJSON(_ text: String) throws {
        do { _ = try OrderedJSON(text: text) } catch let error as OrderedJSONError {
            if case .syntax(_, let line, _) = error { throw ReinsError("The file is not valid JSON at line \(line).") }
            throw ReinsError("The file is not valid JSON.")
        }
    }

    /// The files a save touches, as the review lists them.
    static func files(_ draft: AgentDraft, _ context: Context) -> [String] {
        ((try? changes(draft, context)) ?? []).map { AgentsPaths.display($0.file, roots: context.roots) }
    }

    static func settingsFile(_ context: Context) throws -> URL {
        try RulesStore(roots: context.roots, projects: { context.projects }).file(for: context.scope)
    }

    static func codexConfigFile(_ roots: Roots) -> URL { roots.codex.root.appendingPathComponent("config.toml") }
}

/// Paths as the page shows them: under the agent's root as `~/.claude/...`, under a project as `<name>/...`.
enum AgentsPaths {
    static func display(_ file: URL, roots: Roots) -> String {
        let path = file.path
        for (root, label) in [(roots.claude.root.path, "~/.claude"), (roots.codex.root.path, "~/.codex")] where path == root || path.hasPrefix(root + "/") {
            return label + path.dropFirst(root.count)
        }
        if path == roots.claudeState.path { return "~/.claude.json" }
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty, path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
