import Foundation

/// The `permissions` block of one Claude Code settings file: shape checks and the edit that adds or removes rules.
/// Nothing here reads or returns any other key; `env` and friends are never looked at, and no message quotes content.
enum RulesSettingsFile {
    /// The `permissions` object, or nil when the file has none (a missing key or `null` counts as empty, as in Node).
    /// Refuses, with a 409, a `permissions` that is not an object and a verdict list that is not an array.
    static func permissions(in root: JSONValue, file: URL) throws -> JSONValue? {
        guard let value = root["permissions"], value != .null else { return nil }
        guard value.objectValue != nil else {
            throw ReinsError("\(file.path) has a permissions value that is not an object. Nothing was changed.", status: 409)
        }
        for verdict in RuleVerdict.allCases {
            if let list = value[verdict.rawValue], list.arrayValue == nil {
                throw ReinsError("\(file.path) has permissions.\(verdict.rawValue) that is not a list. Nothing was changed.", status: 409)
            }
        }
        return value
    }

    /// The string rules of one verdict, in file order. Values that are not strings are skipped.
    static func rules(_ verdict: RuleVerdict, in permissions: JSONValue?) -> [String] {
        (permissions?[verdict.rawValue]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    // MARK: Editing

    /// What one verdict list becomes: which elements go (highest index first) and which rules are appended.
    private struct ListChange {
        let verdict: RuleVerdict
        let removeIndices: [Int]
        let appended: [String]
    }

    /// Removes every occurrence of each `remove` rule and appends each `add` rule that is not already there, one list per
    /// verdict, exactly as `withRules` in core/rules.mjs: kept elements first (non-strings are kept), then the new ones.
    /// Returns the document unchanged when no list would differ, so a no-op writes nothing.
    static func edit(_ document: OrderedJSON, file: URL, remove: [VerdictRule], add: [VerdictRule]) throws -> OrderedJSON {
        let permissions = try permissions(in: document.root, file: file)
        var changes: [ListChange] = []
        for verdict in RuleVerdict.allCases {
            let drop = Set(remove.filter { $0.verdict == verdict }.map(\.rule))
            let put = add.filter { $0.verdict == verdict }.map(\.rule)
            if drop.isEmpty, put.isEmpty { continue }
            let current = permissions?[verdict.rawValue]?.arrayValue ?? []
            var removeIndices: [Int] = []
            var kept: [JSONValue] = []
            for (index, item) in current.enumerated() {
                if let text = item.stringValue, drop.contains(text) { removeIndices.append(index) } else { kept.append(item) }
            }
            var appended: [String] = []
            for rule in put where !kept.contains(.string(rule)) && !appended.contains(rule) { appended.append(rule) }
            // Compare the lists, not the operations: removing a rule and writing it back at the end is a no-op when it was last.
            let next = kept + appended.map(JSONValue.string)
            if next != current { changes.append(ListChange(verdict: verdict, removeIndices: removeIndices.reversed(), appended: appended)) }
        }
        guard !changes.isEmpty else { return document }
        do {
            var result = document
            if document.root["permissions"] == .null { result = try result.setting(["permissions"], to: .object([])) }
            for change in changes {
                let path: [PathStep] = ["permissions", .key(change.verdict.rawValue)]
                for index in change.removeIndices { result = try result.removing(path + [.index(index)]) }
                for rule in change.appended { result = try result.appending(.string(rule), to: path) }
            }
            return result
        } catch {
            throw ReinsError("\(file.path) could not be edited. Nothing was changed.", status: 409)
        }
    }
}
