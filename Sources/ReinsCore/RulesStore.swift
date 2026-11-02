import Foundation

/// Claude Code permission rules: list them by scope, add, remove and change a verdict. Every write goes through
/// `FileEdit.editJSON`, so it is journaled and undoable, keeps every other key, the indent and the line endings, and
/// refuses a file that is not valid JSON or has the wrong shape (409, never quoting content).
///
/// Behavior reference: core/rules.mjs. Differences from Node, on purpose:
/// - A project folder must be one that project discovery found (404 otherwise). In Node this check sits in the IPC layer;
///   here it is in the engine so no caller can make Reins create `<any folder>/.claude/settings.json`.
/// - The file is edited in place (only the changed list), not rewritten with `JSON.stringify`.
public struct RulesStore: Sendable {
    public let roots: Roots
    private let discover: @Sendable () -> [String]

    /// - Parameter projects: the folders a project scope may name. Default: `Inventory.discoverProjects`, which reads
    ///   log heads, so a caller that lists and writes in quick succession can pass a cached list.
    public init(roots: Roots, projects: (@Sendable () -> [String])? = nil) {
        self.roots = roots
        self.discover = projects ?? { Inventory.discoverProjects(roots: roots) }
    }

    // MARK: Scopes and files

    /// The settings file of a scope. A project folder must be absolute and discovered.
    public func file(for scope: RuleScope) throws -> URL {
        let name: String
        switch scope {
        case .global: return roots.claude.hookFile
        case .project: name = "settings.json"
        case .local: name = "settings.local.json"
        }
        guard let dir = scope.dir, dir.hasPrefix("/") else { throw ReinsError("A project scope needs an absolute folder.") }
        let known = InventoryFileIO.normalize(dir)
        guard discover().contains(known) else { throw ReinsError("That project is not known to Reins.", status: 404) }
        guard InventoryFileIO.isDirectory(URL(fileURLWithPath: known, isDirectory: true)) else {
            throw ReinsError("That project folder does not exist.", status: 404)
        }
        return URL(fileURLWithPath: InventoryFileIO.join(known, ".claude", name))
    }

    // MARK: Listing

    /// The rules of each scope, in the order given, verdicts allow, ask, deny. A file that is not valid settings is
    /// reported in `problems` and contributes no rules; a missing file contributes nothing.
    public func listRules(_ scopes: [RuleScope] = [.global]) throws -> RuleListing {
        var rules: [RuleItem] = []
        var problems: [String] = []
        for scope in scopes {
            let file = try file(for: scope)
            guard InventoryFileIO.exists(file.path) else { continue }
            guard let data = InventoryFileIO.readData(file, maxBytes: InventoryFileIO.maxJSONBytes + 1), data.count <= InventoryFileIO.maxJSONBytes else {
                problems.append("\(file.path) could not be read.")
                continue
            }
            let text = String(decoding: data, as: UTF8.self)
            if text.allSatisfy(\.isWhitespace) { continue }
            do {
                let document = try FileEdit.parseObject(text, file: file)
                let permissions = try RulesSettingsFile.permissions(in: document.root, file: file)
                for verdict in RuleVerdict.allCases {
                    for rule in RulesSettingsFile.rules(verdict, in: permissions) {
                        rules.append(RuleItem(scope: scope, file: file.path, verdict: verdict, rule: rule))
                    }
                }
            } catch let error as ReinsError {
                problems.append(error.message.replacingOccurrences(of: " Nothing was changed.", with: ""))
            }
        }
        return RuleListing(rules: rules, problems: problems)
    }

    // MARK: Single rules

    /// Adds `rule` under `verdict`. Refuses (409) a rule that is already in the file under any verdict.
    @discardableResult
    public func addRule(scope: RuleScope, verdict: RuleVerdict, rule: String) throws -> JournalEntry {
        let text = try Rules.checkedRule(rule)
        return try required(try edit(scope, label: "Added \(verdict.rawValue) rule \(text) (\(scope.journalLabel))") { file, document in
            let permissions = try RulesSettingsFile.permissions(in: document.root, file: file)
            if let at = RuleVerdict.allCases.first(where: { RulesSettingsFile.rules($0, in: permissions).contains(text) }) {
                throw ReinsError("\(text) is already in \(at.rawValue). Change its verdict instead.", status: 409)
            }
            return try RulesSettingsFile.edit(document, file: file, remove: [], add: [VerdictRule(verdict: verdict, rule: text)])
        })
    }

    /// Removes `rule` from `verdict`. Refuses (409) when the file no longer has it there.
    @discardableResult
    public func removeRule(scope: RuleScope, verdict: RuleVerdict, rule: String) throws -> JournalEntry {
        try required(try edit(scope, label: "Removed \(verdict.rawValue) rule \(rule) (\(scope.journalLabel))") { file, document in
            try requireRule(rule, under: verdict, in: document, file: file)
            return try RulesSettingsFile.edit(document, file: file, remove: [VerdictRule(verdict: verdict, rule: rule)], add: [])
        })
    }

    /// Moves `rule` from one verdict to another.
    @discardableResult
    public func changeVerdict(scope: RuleScope, rule: String, from: RuleVerdict, to: RuleVerdict) throws -> JournalEntry {
        guard from != to else { throw ReinsError("The rule already has that verdict.") }
        return try required(try edit(scope, label: "Changed \(rule) from \(from.rawValue) to \(to.rawValue) (\(scope.journalLabel))") { file, document in
            try requireRule(rule, under: from, in: document, file: file)
            return try RulesSettingsFile.edit(document, file: file, remove: [VerdictRule(verdict: from, rule: rule)], add: [VerdictRule(verdict: to, rule: rule)])
        })
    }

    private func requireRule(_ rule: String, under verdict: RuleVerdict, in document: OrderedJSON, file: URL) throws {
        let permissions = try RulesSettingsFile.permissions(in: document.root, file: file)
        guard RulesSettingsFile.rules(verdict, in: permissions).contains(rule) else {
            throw ReinsError("This rule has already changed. Refresh the list.", status: 409)
        }
    }

    // MARK: Writing

    func edit(_ scope: RuleScope, label: String, change: (URL, OrderedJSON) throws -> OrderedJSON) throws -> JournalEntry? {
        let file = try file(for: scope)
        return try FileEdit.editJSON(roots, file: file, label: label) { document in try change(file, document) }
    }

    private func required(_ entry: JournalEntry?) throws -> JournalEntry {
        guard let entry else { throw ReinsError("Nothing to change: the file already holds that.", status: 409) }
        return entry
    }
}
