import Foundation

/// One `prefix_rule(...)` call of a Codex `.rules` file: the command prefix it matches and its decision.
public struct CodexCommandRule: Equatable, Sendable, Identifiable {
    /// The prefix words, as written (`["git", "push"]`).
    public let pattern: [String]
    /// `allow`, `prompt` or `forbidden`; Codex's default is `allow`.
    public let decision: String
    /// The call's bytes in its file, for change and remove.
    let range: Range<Int>

    public var id: String { pattern.joined(separator: " ") + "|" + decision }
    /// The pattern as one line (S-R3 covers values, not commands: patterns are shown).
    public var text: String { pattern.joined(separator: " ") }
}

/// A `~/.codex/rules/*.rules` file (plan A5). Reins edits only files that hold nothing but `prefix_rule` calls and
/// comments; anything else makes the file read-only, with the reason.
public struct CodexRulesFile: Equatable, Sendable {
    public let file: URL
    public let rules: [CodexCommandRule]
    /// Why Reins will not edit the file, or nil.
    public let readOnlyReason: String?

    public static let decisions = ["allow", "prompt", "forbidden"]

    /// Where Reins adds a rule when no rules file exists yet.
    public static func defaultFile(_ roots: Roots) -> URL {
        roots.codex.root.appendingPathComponent("rules", isDirectory: true).appendingPathComponent("default.rules")
    }

    /// Every `.rules` file in the folder, by name; the default file when there is none.
    public static func readAll(_ roots: Roots) -> [CodexRulesFile] {
        let folder = roots.codex.root.appendingPathComponent("rules", isDirectory: true)
        let names = InventoryFileIO.list(folder).filter { $0.hasSuffix(".rules") }.sorted()
        if names.isEmpty { return [read(defaultFile(roots))] }
        return names.map { read(folder.appendingPathComponent($0)) }
    }

    public static func read(_ file: URL) -> CodexRulesFile {
        let text = InventoryFileIO.readText(file) ?? ""
        return parse(text, file: file)
    }

    static func parse(_ text: String, file: URL) -> CodexRulesFile {
        var scanner = RulesScanner(bytes: Array(text.utf8))
        let found = scanner.scan()
        return CodexRulesFile(file: file, rules: found.rules, readOnlyReason: found.problem)
    }

    public enum Change: Equatable, Sendable {
        case add(pattern: [String], decision: String)
        case decision(pattern: [String], to: String)
        case remove(pattern: [String])
    }

    /// The file with the changes applied, or a refusal when it is read-only.
    public static func apply(_ changes: [Change], to text: String, file: URL) throws -> String {
        var current = text
        for change in changes {
            let parsed = parse(current, file: file)
            if let reason = parsed.readOnlyReason { throw ReinsError(reason, status: 409) }
            var bytes = Array(current.utf8)
            switch change {
            case .add(let pattern, let decision):
                let words = pattern.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !words.isEmpty, decisions.contains(decision) else { throw ReinsError("A command rule needs a command and Allow, Prompt or Forbidden.") }
                if parsed.rules.contains(where: { $0.pattern == words }) { throw ReinsError("\(words.joined(separator: " ")) already has a rule.") }
                let line = "prefix_rule(pattern=[\(words.map(TOMLWrite.quote).joined(separator: ", "))], decision=\(TOMLWrite.quote(decision)))\n"
                if let last = bytes.last, last != 0x0A { bytes.append(0x0A) }
                bytes += Array(line.utf8)
            case .decision(let pattern, let decision):
                guard decisions.contains(decision), let rule = parsed.rules.first(where: { $0.pattern == pattern }) else { throw ReinsError("That command rule is gone.", status: 404) }
                let call = "prefix_rule(pattern=[\(rule.pattern.map(TOMLWrite.quote).joined(separator: ", "))], decision=\(TOMLWrite.quote(decision)))"
                bytes.replaceSubrange(rule.range, with: Array(call.utf8))
            case .remove(let pattern):
                guard let rule = parsed.rules.first(where: { $0.pattern == pattern }) else { continue }
                var end = rule.range.upperBound
                if end < bytes.count, bytes[end] == 0x0A { end += 1 }
                bytes.removeSubrange(rule.range.lowerBound..<end)
            }
            current = String(decoding: bytes, as: UTF8.self)
        }
        return current
    }

    public static func fileChange(_ file: URL, _ changes: [Change]) -> AgentFileChange {
        AgentFileChange(file: file, validate: { text in
            if let reason = parse(text, file: file).readOnlyReason { throw ReinsError(reason, status: 409) }
        }) { text in try apply(changes, to: text ?? "", file: file) }
    }
}

/// Reads `prefix_rule(pattern=[...], decision="...")` calls, comments and blanks; reports anything else.
private struct RulesScanner {
    let bytes: [UInt8]
    var i = 0

    mutating func scan() -> (rules: [CodexCommandRule], problem: String?) {
        var rules: [CodexCommandRule] = []
        let call = Array("prefix_rule(".utf8)
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1; continue }
            if c == 0x23 { while i < bytes.count, bytes[i] != 0x0A { i += 1 }; continue }
            guard i + call.count <= bytes.count, Array(bytes[i..<(i + call.count)]) == call else {
                return (rules, "This rules file holds more than prefix_rule calls, so Reins shows it and leaves it alone.")
            }
            let start = i
            i += call.count
            guard let rule = arguments(start: start) else {
                return (rules, "A prefix_rule call here is not one Reins can read, so Reins shows the file and leaves it alone.")
            }
            rules.append(rule)
        }
        return (rules, nil)
    }

    /// `pattern=[...]`, `decision="..."` and any other `name=value` argument, up to the closing parenthesis.
    private mutating func arguments(start: Int) -> CodexCommandRule? {
        var pattern: [String]?
        var decision = "allow"
        while i < bytes.count {
            skipBlanks()
            guard i < bytes.count else { return nil }
            if bytes[i] == 0x29 {
                i += 1
                guard let pattern else { return nil }
                return CodexCommandRule(pattern: pattern, decision: decision, range: start..<i)
            }
            if bytes[i] == 0x2C { i += 1; continue }
            let nameStart = i
            while i < bytes.count, bytes[i] == 0x5F || (bytes[i] >= 0x61 && bytes[i] <= 0x7A) { i += 1 }
            let name = String(decoding: bytes[nameStart..<i], as: UTF8.self)
            skipBlanks()
            guard !name.isEmpty, i < bytes.count, bytes[i] == 0x3D else { return nil }
            i += 1
            skipBlanks()
            guard i < bytes.count else { return nil }
            if bytes[i] == 0x5B {
                guard let list = stringList() else { return nil }
                if name == "pattern" { pattern = list }
            } else if bytes[i] == 0x22 || bytes[i] == 0x27 {
                guard let text = string() else { return nil }
                if name == "decision" { decision = text }
            } else {
                return nil
            }
        }
        return nil
    }

    private mutating func skipBlanks() {
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1; continue }
            if c == 0x23 { while i < bytes.count, bytes[i] != 0x0A { i += 1 }; continue }
            return
        }
    }

    /// `["a", 'b', ...]`; an element that is itself a list (alternatives) makes the call unreadable for Reins.
    private mutating func stringList() -> [String]? {
        i += 1
        var out: [String] = []
        while i < bytes.count {
            skipBlanks()
            guard i < bytes.count else { return nil }
            if bytes[i] == 0x5D { i += 1; return out }
            if bytes[i] == 0x2C { i += 1; continue }
            guard bytes[i] == 0x22 || bytes[i] == 0x27, let text = string() else { return nil }
            out.append(text)
        }
        return nil
    }

    private mutating func string() -> String? {
        let quote = bytes[i]
        i += 1
        var out: [UInt8] = []
        while i < bytes.count, bytes[i] != quote {
            if bytes[i] == 0x0A { return nil }
            if bytes[i] == 0x5C, i + 1 < bytes.count {
                out.append(bytes[i + 1] == 0x6E ? 0x0A : bytes[i + 1])
                i += 2
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        guard i < bytes.count else { return nil }
        i += 1
        return String(decoding: out, as: UTF8.self)
    }
}

/// Codex's `~/.codex/hooks.json`, which has the same shape as Claude Code's hooks (plan A5).
public enum CodexHooksFile {
    public enum Change: Equatable, Sendable {
        case add(event: String, matcher: String?, command: String)
        case remove(event: String, matcher: String?, command: String)
    }

    public static func fileChange(_ roots: Roots, _ changes: [Change]) -> AgentFileChange {
        let file = roots.codex.hookFile
        return AgentSave.jsonChange(file) { document in
            var doc = document
            for change in changes {
                switch change {
                case .add(let event, let matcher, let command):
                    doc = try HookEdit.adding(doc, file: file.path, event: event, matcher: matcher, hook: try HookEdit.hookValue(command: command, timeout: nil))
                case .remove(let event, let matcher, let command):
                    doc = try HookEdit.removing(doc, file: file.path, event: event, matcher: matcher, command: command).doc
                }
            }
            return doc
        }
    }
}
