import Foundation

/// Claude Code's `settings.json` at one scope, as the Agents page shows it (plan A3). Only what the panels need is read;
/// `env` and every other key stay in the file and reach the UI only through the masked Advanced editor.
public struct ClaudeSettings: Equatable, Sendable {
    public let file: URL
    public let exists: Bool
    /// Why the file could not be read (not valid JSON, not an object, a list of the wrong shape). Never content.
    public let problem: String?
    public let defaultMode: String?
    public let allow: [String]
    public let ask: [String]
    public let deny: [String]
    public let additionalDirectories: [String]
    public let model: String?
    /// Organisation policy: shown, never written.
    public let managed: Bool

    public func rules(_ verdict: RuleVerdict) -> [String] {
        switch verdict {
        case .allow: allow
        case .ask: ask
        case .deny: deny
        }
    }

    /// The verdict that already holds `rule`, if any.
    public func verdict(of rule: String) -> RuleVerdict? {
        RuleVerdict.allCases.first { rules($0).contains(rule) }
    }

    /// These settings as a draft of `changes` would leave them, for the panel to show before a save. Hooks are not part
    /// of this struct; the Hooks panel shows its own draft.
    public func applying(_ changes: [ClaudeSettingsEdit.Change]) -> ClaudeSettings {
        var mode = defaultMode, model = model, folders = additionalDirectories
        var lists: [RuleVerdict: [String]] = [.allow: allow, .ask: ask, .deny: deny]
        for change in changes {
            switch change {
            case .defaultMode(let next): mode = next
            case .addRule(let verdict, let rule): if !(lists[verdict] ?? []).contains(rule) { lists[verdict, default: []].append(rule) }
            case .removeRule(let verdict, let rule): lists[verdict]?.removeAll { $0 == rule }
            case .moveRule(let rule, let from, let to):
                lists[from]?.removeAll { $0 == rule }
                if !(lists[to] ?? []).contains(rule) { lists[to, default: []].append(rule) }
            case .addDirectory(let folder): if !folders.contains(folder) { folders.append(folder) }
            case .removeDirectory(let folder): folders.removeAll { $0 == folder }
            case .model(let next): model = (next?.isEmpty ?? true) ? nil : next
            case .addHook, .removeHook: break
            }
        }
        return ClaudeSettings(file: file, exists: exists, problem: problem, defaultMode: mode, allow: lists[.allow] ?? [], ask: lists[.ask] ?? [],
                              deny: lists[.deny] ?? [], additionalDirectories: folders, model: model, managed: managed)
    }
}

/// The edits the Claude Code panels make to one settings file (plan A3). Each is a smallest edit through `OrderedJSON`, so
/// every other byte of the file stays; rules and hooks go through the same code as the Rules page and Loadout.
public enum ClaudeSettingsEdit {
    public enum Change: Equatable, Sendable {
        /// `permissions.defaultMode`; nil removes it ("Same as Global").
        case defaultMode(String?)
        case addRule(RuleVerdict, String)
        case removeRule(RuleVerdict, String)
        /// A rule's verdict tag menu: out of one list and into another, in one change.
        case moveRule(String, from: RuleVerdict, to: RuleVerdict)
        /// `permissions.additionalDirectories`.
        case addDirectory(String)
        case removeDirectory(String)
        /// `model`; nil removes it.
        case model(String?)
        case addHook(event: String, matcher: String?, command: String)
        case removeHook(event: String, matcher: String?, command: String)
    }

    /// The modes of `permissions.defaultMode`, in menu order.
    public static let modes = ["default", "acceptEdits", "plan", "bypassPermissions"]

    /// The settings at `file`. A missing file reads as empty; a file that is not settings reads as empty with a problem.
    public static func read(_ file: URL, managed: Bool = false) -> ClaudeSettings {
        let exists = InventoryFileIO.exists(file.path)
        var problem: String?
        var root = JSONValue.object([])
        if exists {
            if let data = InventoryFileIO.readData(file, maxBytes: InventoryFileIO.maxJSONBytes), let text = String(data: data, encoding: .utf8) {
                if !text.allSatisfy(\.isWhitespace) {
                    do { root = try FileEdit.parseObject(text, file: file).root } catch let error as ReinsError { problem = error.message } catch { problem = "\(file.path) could not be read." }
                }
            } else {
                problem = "\(file.path) could not be read."
            }
        }
        var permissions: JSONValue?
        do {
            permissions = try RulesSettingsFile.permissions(in: root, file: file)
        } catch {
            if problem == nil { problem = "\(file.path) has a permissions value of the wrong shape." }
        }
        return ClaudeSettings(
            file: file, exists: exists, problem: problem,
            defaultMode: permissions?["defaultMode"]?.stringValue,
            allow: RulesSettingsFile.rules(.allow, in: permissions),
            ask: RulesSettingsFile.rules(.ask, in: permissions),
            deny: RulesSettingsFile.rules(.deny, in: permissions),
            additionalDirectories: (permissions?["additionalDirectories"]?.arrayValue ?? []).compactMap(\.stringValue),
            model: root["model"]?.stringValue,
            managed: managed
        )
    }

    /// Applies the changes in order to a parsed settings file.
    public static func apply(_ changes: [Change], to document: OrderedJSON, file: URL) throws -> OrderedJSON {
        var doc = document
        for change in changes {
            doc = try apply(change, to: doc, file: file)
        }
        return doc
    }

    /// The file change for one save of these edits.
    public static func fileChange(_ file: URL, _ changes: [Change]) -> AgentFileChange {
        AgentSave.jsonChange(file) { try apply(changes, to: $0, file: file) }
    }

    /// Refuses a rule that is not `Tool` or `Tool(pattern)`, and one that a verdict already holds, naming that verdict.
    public static func checkNewRule(_ rule: String, in settings: ClaudeSettings) throws -> String {
        let text = try Rules.checkedRule(rule)
        if let held = settings.verdict(of: text) {
            throw ReinsError("\(text) is already in \(held.rawValue.capitalized).")
        }
        return text
    }

    private static func apply(_ change: Change, to doc: OrderedJSON, file: URL) throws -> OrderedJSON {
        do {
            switch change {
            case .defaultMode(let mode):
                if let mode { return try doc.setting(["permissions", "defaultMode"], to: .string(mode)) }
                return doc[["permissions", "defaultMode"]] == nil ? doc : try doc.removing(["permissions", "defaultMode"])
            case .addRule(let verdict, let rule):
                return try RulesSettingsFile.edit(doc, file: file, remove: [], add: [VerdictRule(verdict: verdict, rule: try Rules.checkedRule(rule))])
            case .removeRule(let verdict, let rule):
                return try RulesSettingsFile.edit(doc, file: file, remove: [VerdictRule(verdict: verdict, rule: rule)], add: [])
            case .moveRule(let rule, let from, let to):
                return try RulesSettingsFile.edit(doc, file: file, remove: [VerdictRule(verdict: from, rule: rule)], add: [VerdictRule(verdict: to, rule: rule)])
            case .addDirectory(let folder):
                let current = (doc[["permissions", "additionalDirectories"]]?.arrayValue ?? []).compactMap(\.stringValue)
                if current.contains(folder) { return doc }
                return try doc.appending(.string(folder), to: ["permissions", "additionalDirectories"])
            case .removeDirectory(let folder):
                let items = doc[["permissions", "additionalDirectories"]]?.arrayValue ?? []
                guard let index = items.lastIndex(of: .string(folder)) else { return doc }
                return try doc.removing(["permissions", "additionalDirectories", .index(index)])
            case .model(let model):
                if let model, !model.isEmpty { return try doc.setting(["model"], to: .string(model)) }
                return doc[["model"]] == nil ? doc : try doc.removing(["model"])
            case .addHook(let event, let matcher, let command):
                return try HookEdit.adding(doc, file: file.path, event: event, matcher: matcher, hook: try HookEdit.hookValue(command: command, timeout: nil))
            case .removeHook(let event, let matcher, let command):
                return try HookEdit.removing(doc, file: file.path, event: event, matcher: matcher, command: command).doc
            }
        } catch is OrderedJSONError {
            throw ReinsError("\(file.path) has an unexpected layout. Nothing was changed.", status: 409)
        }
    }
}
