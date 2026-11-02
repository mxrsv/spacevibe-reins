import Foundation

/// The `---` header of a SKILL.md or an agent `.md` file. Same behaviour as `frontmatter()` in core/inventory.mjs: flat
/// `key: value` lines only, values as text, `>` and `|` block scalars joined (folded with a space, literal with newlines).
/// Not a YAML parser: lists and nested maps are not understood, and their lines are ignored.
public enum Frontmatter {
    /// The fields, or an empty dictionary when the text has no header. With a repeated key the last one wins.
    public static func parse(_ text: String) -> [String: String] {
        guard let lines = headerLines(text) else { return [:] }
        var out: [String: String] = [:]
        var index = 0
        while index < lines.count {
            defer { index += 1 }
            guard let (key, raw) = keyValue(lines[index]) else { continue }
            let marker = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBlockMarker(marker) {
                var block: [String] = []
                while index + 1 < lines.count, lines[index + 1].isEmpty || startsWithWhitespace(lines[index + 1]) {
                    index += 1
                    block.append(lines[index].trimmingCharacters(in: .whitespacesAndNewlines))
                }
                let joined = block.joined(separator: marker.hasPrefix(">") ? " " : "\n")
                out[key] = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                out[key] = unquote(raw)
            }
        }
        return out
    }

    /// A YAML-ish scalar: `"double"` (JSON escapes), `'single'` (`''` is a quote), or plain text.
    static func unquote(_ value: String) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\"") {
            if let doc = try? OrderedJSON(text: t), let s = doc.root.stringValue { return s }
            return String(t.dropFirst().dropLast())
        }
        if t.hasPrefix("'"), t.hasSuffix("'"), t.count >= 2 {
            return String(t.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return t
    }

    /// The lines between the opening `---` and the first line that starts with `---`, or nil without a header.
    private static func headerLines(_ text: String) -> [String]? {
        let bytes = Array(text.utf8)
        var start: Int
        if bytes.starts(with: Array("---\n".utf8)) { start = 4 } else if bytes.starts(with: Array("---\r\n".utf8)) { start = 5 } else { return nil }
        var end = start
        let fence = Array("\n---".utf8)
        var found = false
        while end + fence.count <= bytes.count {
            if bytes[end] == 0x0A, Array(bytes[end..<end + fence.count]) == fence { found = true; break }
            end += 1
        }
        guard found else { return nil }
        if end > start, bytes[end - 1] == 0x0D { end -= 1 }
        if end < start { end = start }
        return bytes[start..<end].split(separator: 0x0A, omittingEmptySubsequences: false).map { slice in
            var line = slice
            if line.last == 0x0D { line = line.dropLast() }
            return String(decoding: line, as: UTF8.self)
        }
    }

    /// `^([A-Za-z][\w-]*):\s*(.*)$`
    private static func keyValue(_ line: String) -> (String, String)? {
        let scalars = Array(line.unicodeScalars)
        guard let first = scalars.first, first.isASCII, first.properties.isAlphabetic else { return nil }
        var end = 1
        while end < scalars.count, isKeyScalar(scalars[end]) { end += 1 }
        guard end < scalars.count, scalars[end] == ":" else { return nil }
        var valueStart = end + 1
        while valueStart < scalars.count, scalars[valueStart].properties.isWhitespace { valueStart += 1 }
        var key = String.UnicodeScalarView()
        key.append(contentsOf: scalars[0..<end])
        var value = String.UnicodeScalarView()
        value.append(contentsOf: scalars[valueStart...])
        return (String(key), String(value))
    }

    private static func isKeyScalar(_ s: Unicode.Scalar) -> Bool {
        s.isASCII && (s.properties.isAlphabetic || ("0"..."9").contains(s) || s == "_" || s == "-")
    }

    private static func isBlockMarker(_ text: String) -> Bool {
        guard let first = text.first, first == ">" || first == "|" else { return false }
        let rest = text.dropFirst()
        return rest.isEmpty || (rest.count == 1 && (rest == "+" || rest == "-"))
    }

    private static func startsWithWhitespace(_ line: String) -> Bool {
        line.unicodeScalars.first?.properties.isWhitespace ?? false
    }
}
