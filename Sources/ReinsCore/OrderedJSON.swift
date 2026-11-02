import Foundation

/// Why a JSON file could not be read or edited. Never carries file content, so it is safe to log and show.
public enum OrderedJSONError: Error, Equatable, Sendable {
    public enum Problem: String, Sendable {
        case unexpectedEnd, unexpectedCharacter, invalidNumber, invalidEscape, controlCharacterInString
        case expectedColon, expectedCommaOrEnd, expectedKey, trailingContent
    }

    case invalidUTF8
    case syntax(Problem, line: Int, column: Int)
    case tooDeep
    /// An edit named a key or index that does not exist.
    case pathNotFound
    /// An edit walked through, or onto, a value of the wrong kind (a key on an array, an append to a string).
    case typeMismatch
    /// A value that cannot be written, such as a `.number` that is not a JSON number.
    case invalidValue
}

/// A JSON document that is edited in place. It keeps the file's exact bytes and a parsed tree with byte positions; an
/// edit splices new text into only the region it changes and parses the result again. So:
/// - a file that is read and written back unchanged is the same bytes (indent, CRLF, key order, trailing newline, spacing);
/// - after an edit, every byte outside the edited member, element or separator is untouched;
/// - new text copies the document's style: tab or N spaces, CRLF or LF, spacing after `:` and `,`.
///
/// Values are immutable: every edit returns a new `OrderedJSON`. Strict JSON only (no comments, no trailing commas, no BOM),
/// the same files `JSON.parse` accepts. Duplicate keys are kept; lookups and edits use the last one, as `JSON.parse` does.
public struct OrderedJSON: Sendable {
    public static let maxDepth = 256

    /// The exact bytes of the document.
    public let bytes: [UInt8]
    /// The parsed root.
    public let root: JSONValue
    let tree: JSONNode

    public init(data: Data) throws {
        try self.init(bytes: [UInt8](data))
    }

    public init(text: String) throws {
        try self.init(bytes: Array(text.utf8))
    }

    init(bytes: [UInt8]) throws {
        guard String(validating: bytes, as: UTF8.self) != nil else { throw OrderedJSONError.invalidUTF8 }
        var parser = JSONParser(bytes: bytes)
        let tree = try parser.parseDocument()
        self.bytes = bytes
        self.tree = tree
        self.root = tree.value
    }

    public var data: Data { Data(bytes) }
    public var text: String { String(decoding: bytes, as: UTF8.self) }

    /// The value at a key path, or nil when the path does not exist.
    public subscript(path: [PathStep]) -> JSONValue? {
        var current = root
        for step in path {
            switch step {
            case .key(let key): guard let next = current[key] else { return nil }; current = next
            case .index(let index): guard let next = current[index] else { return nil }; current = next
            }
        }
        return current
    }

    // MARK: Edits

    /// Sets the value at a path. A missing last key is added at the end of its object, and missing parent objects are created.
    /// `.index(count)` as the last step appends. An existing value is replaced in place and keeps its position.
    public func setting(_ path: [PathStep], to value: JSONValue) throws -> OrderedJSON {
        try apply(path, .set(value))
    }

    /// Removes the member or element at a path, with its separator.
    public func removing(_ path: [PathStep]) throws -> OrderedJSON {
        guard !path.isEmpty else { throw OrderedJSONError.pathNotFound }
        return try apply(path, .remove)
    }

    /// Appends to the array at a path. A missing array (and missing parent objects) is created.
    public func appending(_ value: JSONValue, to path: [PathStep]) throws -> OrderedJSON {
        try apply(path, .append(value))
    }

    private enum Operation {
        case set(JSONValue)
        case remove
        case append(JSONValue)
    }

    private func apply(_ path: [PathStep], _ operation: Operation) throws -> OrderedJSON {
        let style = Style(document: self)
        let edit = try edit(node: tree, steps: path[...], operation, style: style)
        var next = bytes
        next.replaceSubrange(edit.range, with: Array(edit.replacement.utf8))
        return try OrderedJSON(bytes: next)
    }

    private struct Edit {
        let range: Range<Int>
        let replacement: String
    }

    private func edit(node: JSONNode, steps: ArraySlice<PathStep>, _ operation: Operation, style: Style) throws -> Edit {
        guard let step = steps.first else {
            switch operation {
            case .set(let value):
                let expanded: Bool
                if case .scalar = node { expanded = style.multiline } else { expanded = style.multiline && bytes[node.range].contains(0x0A) }
                return Edit(range: node.range, replacement: try style.render(value, base: indent(ofLineAt: node.range.lowerBound), expanded: expanded))
            case .append(let value):
                guard case .array(let items, let range) = node else { throw OrderedJSONError.typeMismatch }
                return try insertion(into: range, existing: items.map { ($0.range, $0.range.lowerBound) }, text: { try style.render(value, base: $0, expanded: $1) }, style: style)
            case .remove:
                throw OrderedJSONError.pathNotFound
            }
        }
        let rest = steps.dropFirst()
        switch (node, step) {
        case (.object(let members, let range), .key(let key)):
            if let found = members.lastIndex(where: { $0.key == key }) {
                if rest.isEmpty, case .remove = operation {
                    return removal(count: members.count, at: found, container: range, starts: members.map(\.keyStart), ends: members.map { $0.value.range.upperBound })
                }
                return try edit(node: members[found].value, steps: rest, operation, style: style)
            }
            let leaf: JSONValue
            switch operation {
            case .remove: throw OrderedJSONError.pathNotFound
            case .set(let value): leaf = value
            case .append(let value): leaf = .array([value])
            }
            var nested = leaf
            for next in rest.reversed() {
                guard case .key(let name) = next else { throw OrderedJSONError.pathNotFound }
                nested = .object([JSONMember(name, nested)])
            }
            return try insertion(
                into: range, existing: members.map { ($0.value.range, $0.keyStart) },
                text: { base, expanded in "\(style.quote(key))\(style.colon)\(try style.render(nested, base: base, expanded: expanded))" },
                style: style
            )
        case (.array(let items, let range), .index(let index)):
            if items.indices.contains(index) {
                if rest.isEmpty, case .remove = operation {
                    return removal(count: items.count, at: index, container: range, starts: items.map { $0.range.lowerBound }, ends: items.map { $0.range.upperBound })
                }
                return try edit(node: items[index], steps: rest, operation, style: style)
            }
            if index == items.count, rest.isEmpty, case .set(let value) = operation {
                return try insertion(into: range, existing: items.map { ($0.range, $0.range.lowerBound) }, text: { try style.render(value, base: $0, expanded: $1) }, style: style)
            }
            throw OrderedJSONError.pathNotFound
        default:
            throw OrderedJSONError.typeMismatch
        }
    }

    /// Where and what to write for a new member or element at the end of a container.
    private func insertion(
        into container: Range<Int>,
        existing: [(value: Range<Int>, start: Int)],
        text: (_ base: String, _ expanded: Bool) throws -> String,
        style: Style
    ) throws -> Edit {
        let base = indent(ofLineAt: container.lowerBound)
        guard let last = existing.last else {
            let expanded = style.multiline
            let childBase = base + style.unit
            let body = try text(childBase, expanded)
            let inner = (container.lowerBound + 1)..<(container.upperBound - 1)
            return Edit(range: inner, replacement: expanded ? "\(style.newline)\(childBase)\(body)\(style.newline)\(base)" : body)
        }
        let expanded = bytes[container].contains(0x0A)
        let childBase = expanded ? indent(ofLineAt: last.start) : base
        let body = try text(childBase, expanded)
        let at = last.value.upperBound
        return Edit(range: at..<at, replacement: expanded ? ",\(style.newline)\(childBase)\(body)" : "\(style.comma)\(body)")
    }

    /// The bytes to delete so that member or element `index` and one separator go.
    private func removal(count: Int, at index: Int, container: Range<Int>, starts: [Int], ends: [Int]) -> Edit {
        if count == 1 { return Edit(range: (container.lowerBound + 1)..<(container.upperBound - 1), replacement: "") }
        if index < count - 1 { return Edit(range: starts[index]..<starts[index + 1], replacement: "") }
        return Edit(range: ends[index - 1]..<ends[index], replacement: "")
    }

    /// The leading blanks of the line holding `offset`.
    private func indent(ofLineAt offset: Int) -> String {
        var lineStart = offset
        while lineStart > 0, bytes[lineStart - 1] != 0x0A { lineStart -= 1 }
        var end = lineStart
        while end < bytes.count, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
        return String(decoding: bytes[lineStart..<end], as: UTF8.self)
    }

    // MARK: Writing a new document

    /// Pretty text for a value that has no source file yet (the journal, a new settings file).
    public static func pretty(_ value: JSONValue, indent: String = "  ", newline: String = "\n", trailingNewline: Bool = true) throws -> String {
        let style = Style(unit: indent, newline: newline, colon: ": ", multiline: true)
        return try style.render(value, base: "", expanded: true) + (trailingNewline ? newline : "")
    }
}

// MARK: - Style

/// How a document spells things, so new text looks like the old text.
struct Style {
    let unit: String
    let newline: String
    let colon: String
    let multiline: Bool

    var comma: String { colon.hasSuffix(" ") ? ", " : "," }

    init(unit: String, newline: String, colon: String, multiline: Bool) {
        self.unit = unit
        self.newline = newline
        self.colon = colon
        self.multiline = multiline
    }

    init(document: OrderedJSON) {
        let bytes = document.bytes
        let range = document.tree.range
        let body = bytes[range]
        let emptyRoot: Bool
        switch document.tree {
        case .object(let members, _): emptyRoot = members.isEmpty
        case .array(let items, _): emptyRoot = items.isEmpty
        case .scalar: emptyRoot = false
        }
        // A fresh `{}` followed by a newline is a pretty-printed file waiting for its first key.
        multiline = body.contains(0x0A) || (emptyRoot && bytes.contains(0x0A))
        newline = bytes.indices.contains(where: { bytes[$0] == 0x0D && $0 + 1 < bytes.count && bytes[$0 + 1] == 0x0A }) ? "\r\n" : "\n"

        // The first indented line inside the root is one level deep, so its blanks are one unit.
        var found: String?
        var scan = range.lowerBound
        while scan < range.upperBound, found == nil {
            guard let lineBreak = bytes[scan..<range.upperBound].firstIndex(of: 0x0A) else { break }
            let lineStart = lineBreak + 1
            var end = lineStart
            while end < range.upperBound, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
            if end > lineStart, end < range.upperBound, bytes[end] != 0x0A, bytes[end] != 0x0D {
                found = String(decoding: bytes[lineStart..<end], as: UTF8.self)
            }
            scan = lineStart
        }
        unit = found ?? "  "

        colon = document.tree.firstMemberSeparator(in: bytes) ?? (multiline ? ": " : ":")
    }

    func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    func render(_ value: JSONValue, base: String, expanded: Bool) throws -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let text):
            guard JSONParser.isNumber(Array(text.utf8)) else { throw OrderedJSONError.invalidValue }
            return text
        case .string(let s): return quote(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let inner = base + unit
            let parts = try items.map { try render($0, base: expanded ? inner : base, expanded: expanded) }
            return expanded ? "[\(newline)\(parts.map { inner + $0 }.joined(separator: ",\(newline)"))\(newline)\(base)]" : "[\(parts.joined(separator: comma))]"
        case .object(let members):
            if members.isEmpty { return "{}" }
            let inner = base + unit
            let parts = try members.map { "\(quote($0.key))\(colon)\(try render($0.value, base: expanded ? inner : base, expanded: expanded))" }
            return expanded ? "{\(newline)\(parts.map { inner + $0 }.joined(separator: ",\(newline)"))\(newline)\(base)}" : "{\(parts.joined(separator: comma))}"
        }
    }
}
