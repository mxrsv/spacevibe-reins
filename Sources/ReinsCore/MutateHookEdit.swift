import Foundation

/// The two pure edits on a hook file, `withHook` and `withoutHook` of core/mutate.mjs, done on an `OrderedJSON` so the
/// file keeps its key order, indent and every byte outside the edited array.
///
/// A hook file holds `hooks: { <event>: [ { matcher?, hooks: [ { type, command, ... } ] } ] }`. A group is identified by
/// its matcher (missing and null count as the same).
enum HookEdit {
    static func layoutError(_ file: String) -> ReinsError {
        ReinsError("The hooks in \(file) have an unexpected layout. Nothing was changed.", status: 409)
    }

    /// The hook object written for a new hook: `{type: "command", command, timeout?}`.
    static func hookValue(command: String, timeout: Double?) throws -> JSONValue {
        var members = [JSONMember("type", "command"), JSONMember("command", .string(command))]
        if let timeout, timeout != 0 {
            guard timeout.isFinite else { throw ReinsError("The timeout must be a number.") }
            members.append(JSONMember("timeout", .number(timeout == timeout.rounded() && abs(timeout) < 1e15 ? String(Int64(timeout)) : "\(timeout)")))
        }
        return .object(members)
    }

    static func sameGroup(_ group: JSONValue, matcher: String?) -> Bool {
        switch group["matcher"] {
        case nil, .some(.null): return matcher == nil
        case .some(.string(let own)): return matcher == own
        default: return false
        }
    }

    /// Adds the hook to the first group with the same matcher that does not run this command yet, else as a new group.
    static func adding(_ doc: OrderedJSON, file: String, event: String, matcher: String?, hook: JSONValue) throws -> OrderedJSON {
        let command = hook["command"]?.stringValue
        let groups = doc.root["hooks"]?[event]?.arrayValue ?? []
        do {
            for (index, group) in groups.enumerated() where sameGroup(group, matcher: matcher) {
                let runs = (group["hooks"]?.arrayValue ?? []).contains { $0["command"]?.stringValue == command }
                if !runs { return try doc.appending(hook, to: ["hooks", .key(event), .index(index), "hooks"]) }
            }
            var members: [JSONMember] = []
            if let matcher, !matcher.isEmpty { members.append(JSONMember("matcher", .string(matcher))) }
            members.append(JSONMember("hooks", .array([hook])))
            return try doc.appending(.object(members), to: ["hooks", .key(event)])
        } catch is OrderedJSONError {
            throw layoutError(file)
        }
    }

    /// Removes the first hook with this command from the first group with this matcher that has it. An empty group goes
    /// with it, and so does an event left with no group. Returns the hook that was removed, or nil when none matched.
    static func removing(_ doc: OrderedJSON, file: String, event: String, matcher: String?, command: String) throws -> (doc: OrderedJSON, found: JSONValue?) {
        let groups = doc.root["hooks"]?[event]?.arrayValue ?? []
        do {
            for (groupIndex, group) in groups.enumerated() where sameGroup(group, matcher: matcher) {
                guard let hooks = group["hooks"]?.arrayValue,
                      let hookIndex = hooks.firstIndex(where: { $0["command"]?.stringValue == command }) else { continue }
                let path: [PathStep]
                if hooks.count > 1 {
                    path = ["hooks", .key(event), .index(groupIndex), "hooks", .index(hookIndex)]
                } else if groups.count > 1 {
                    path = ["hooks", .key(event), .index(groupIndex)]
                } else {
                    path = ["hooks", .key(event)]
                }
                return (try doc.removing(path), hooks[hookIndex])
            }
        } catch is OrderedJSONError {
            throw layoutError(file)
        }
        return (doc, nil)
    }
}
