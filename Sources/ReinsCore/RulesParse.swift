import Foundation

/// Reading a rule string, and the text tests the capability grid needs. Same results as `parseRule`, `PUSH_RE` and
/// `ENV_RE` in core/rules.mjs, including JavaScript's ASCII-only `\w` and `\b` (ICU's are Unicode-aware).
public enum Rules {
    public static let maxRuleLength = 1000

    // MARK: Rule shape

    /// `Tool` or `Tool(specifier)`; nil when the text is neither. The tool name is `[A-Za-z][A-Za-z0-9_.-]*`, and the
    /// specifier is everything between the first `(` and the final `)`.
    public static func parseRule(_ rule: String) -> ParsedRule? {
        let scalars = Array(jsTrim(rule).unicodeScalars)
        guard let first = scalars.first, isAsciiLetter(first) else { return nil }
        var i = 1
        while i < scalars.count, isAsciiLetter(scalars[i]) || isAsciiDigit(scalars[i]) || "_.-".unicodeScalars.contains(scalars[i]) { i += 1 }
        let tool = String(String.UnicodeScalarView(scalars[0..<i]))
        if i == scalars.count { return ParsedRule(tool: tool, specifier: nil) }
        guard scalars[i] == "(", scalars.last == ")", scalars.count - 1 > i else { return nil }
        let specifier = String(String.UnicodeScalarView(scalars[(i + 1)..<(scalars.count - 1)]))
        return ParsedRule(tool: tool, specifier: jsTrim(specifier).isEmpty ? nil : specifier)
    }

    /// The rule text a caller may add: trimmed, one line, at most 1000 UTF-16 units, and a valid rule.
    static func checkedRule(_ rule: String) throws -> String {
        let text = jsTrim(rule)
        guard !text.isEmpty else { throw ReinsError("Enter a rule such as Bash(npm test *).") }
        guard text.utf16.count <= maxRuleLength, !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }), parseRule(text) != nil else {
            throw ReinsError("That is not a valid rule. Use Tool or Tool(pattern) on one line.")
        }
        return text
    }

    // MARK: Text tests used by the grid

    /// A bare `Tool`, `Tool()` or `Tool(*)`: the rule covers every use of the tool.
    static func isWide(_ rule: ParsedRule) -> Bool {
        rule.specifier == nil || jsTrim(rule.specifier ?? "") == "*"
    }

    /// The specifier names a `.env` file: `.env` at the start or right after a `/` or `*`. Tested on the untrimmed specifier.
    static func namesEnvFile(_ specifier: String) -> Bool {
        let bytes = Array(specifier.utf8)
        let needle = Array(".env".utf8)
        guard bytes.count >= needle.count else { return false }
        for start in 0...(bytes.count - needle.count) where Array(bytes[start..<(start + needle.count)]) == needle {
            if start == 0 || bytes[start - 1] == UInt8(ascii: "/") || bytes[start - 1] == UInt8(ascii: "*") { return true }
        }
        return false
    }

    /// A command that pushes or deploys: starts with a push or deploy prefix, or has the word `deploy` anywhere.
    static func looksLikePushOrDeploy(_ command: String) -> Bool {
        let text = jsTrim(command)
        return pushPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // `\s` and `\b` of JavaScript, written out so ICU matches the same characters.
    static let space = #"[\t\n\u000B\f\r    -     　﻿]"#
    static let boundary = #"(?:(?<=[A-Za-z0-9_])(?![A-Za-z0-9_])|(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]))"#

    private static let pushPattern: NSRegularExpression = {
        let s = space + "+"
        let prefixes = [
            "git\(s)push", "vercel", "netlify", "firebase\(s)deploy", "fly\(s)deploy", "wrangler\(s)(?:deploy|publish)",
            "(?:npm|pnpm|yarn)\(s)publish", "docker\(s)push", "gh\(s)release", "gh\(s)pr\(s)merge",
        ]
        // The pattern is a constant; a typo in it fails every test at once.
        return try! NSRegularExpression(pattern: "^(?:\(prefixes.joined(separator: "|")))\(boundary)|\(boundary)deploy\(boundary)")
    }()

    // MARK: JavaScript string trim

    private static let jsSpace: Set<Unicode.Scalar> = {
        var set: Set<Unicode.Scalar> = ["\u{09}", "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", " ", "\u{A0}", "\u{1680}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}"]
        for value in 0x2000...0x200A { set.insert(Unicode.Scalar(UInt32(value))!) }
        return set
    }()

    /// `String.prototype.trim`.
    static func jsTrim(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard let start = scalars.firstIndex(where: { !jsSpace.contains($0) }) else { return "" }
        let end = scalars.lastIndex(where: { !jsSpace.contains($0) })!
        return String(String.UnicodeScalarView(scalars[start...end]))
    }

    /// `String.prototype.trimStart`.
    static func jsTrimStart(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let start = scalars.firstIndex(where: { !jsSpace.contains($0) }) else { return "" }
        return String(scalars[start...])
    }

    private static func isAsciiLetter(_ s: Unicode.Scalar) -> Bool { (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122) }
    private static func isAsciiDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 48 && s.value <= 57 }
}
