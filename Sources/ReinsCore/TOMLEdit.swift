import Foundation

/// A TOML value Reins writes. Rendered on one line; strings are basic strings with JSON-style escapes.
public indirect enum TOMLWrite: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case array([TOMLWrite])
    case table([(String, TOMLWrite)])

    public static func == (a: TOMLWrite, b: TOMLWrite) -> Bool { a.rendered == b.rendered }

    public static func strings(_ values: [String]) -> TOMLWrite { .array(values.map { .string($0) }) }

    /// The value as TOML text.
    public var rendered: String {
        switch self {
        case .string(let text): return Self.quote(text)
        case .integer(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .array(let items): return "[" + items.map(\.rendered).joined(separator: ", ") + "]"
        case .table(let pairs):
            guard !pairs.isEmpty else { return "{}" }
            return "{ " + pairs.map { "\(TOMLEdit.keyText([$0.0])) = \($0.1.rendered)" }.joined(separator: ", ") + " }"
        }
    }

    /// How `TOMLReader` reads the rendered text back, for the check after an edit.
    var readBack: TOMLValue {
        switch self {
        case .string(let text): return .string(text)
        case .integer(let n): return .integer(n)
        case .bool(let b): return .bool(b)
        case .array(let items): return .array(items.map(\.readBack))
        case .table(let pairs): return .table(pairs.map { TOMLPair(key: $0.0, value: $0.1.readBack) })
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}

/// Edits Codex's `config.toml` line by line (spec, Writes: "Only what changed"; plan A2). Every edit keeps comments, order,
/// spacing and every untouched line byte-identical, and its result must read back through `TOMLReader` with the intended
/// value, or the edit throws and nothing is written.
///
/// A path is the table plus the dotted key, as `TOMLLayout.Statement.path`: `["projects", "/w/app", "trust_level"]`
/// matches `[projects."/w/app"]` + `trust_level`, `[projects]` + `"/w/app".trust_level` and a top-level dotted key alike.
public struct TOMLEdit: Sendable {
    public let text: String

    public init(_ text: String) { self.text = text }

    /// Sets the value at `path`. An existing value is replaced where it is; one inside an inline table rewrites that inline
    /// table; a new key goes after the last statement of its table, and a missing table is added at the end of the file.
    public func setting(_ path: [String], to value: TOMLWrite) throws -> TOMLEdit {
        guard !path.isEmpty else { throw Self.refusal }
        let layout = TOMLLayout(text: text)
        var bytes = layout.bytes
        if let statement = layout.statement(path) {
            bytes.replaceSubrange(statement.value, with: Array(value.rendered.utf8))
        } else if let found = enclosingInline(layout, path) {
            let current = try readInline(layout, found.0)
            let rendered = Self.replacing(current, at: found.1, with: value).rendered
            bytes.replaceSubrange(found.0.value, with: Array(rendered.utf8))
        } else {
            let (table, key) = placement(layout, path)
            let line = Array("\(Self.keyText(key)) = \(value.rendered)\n".utf8)
            if let at = insertionPoint(layout, table: table) {
                bytes.insert(contentsOf: Self.newlineBefore(bytes, at) + line, at: at)
            } else {
                var tail = Self.newlineBefore(bytes, bytes.count)
                if !bytes.isEmpty { tail += Array("\n".utf8) }
                tail += Array("[\(Self.keyText(table))]\n".utf8) + line
                bytes += tail
            }
        }
        let next = TOMLEdit(String(decoding: bytes, as: UTF8.self))
        try next.check(path, equals: value.readBack, against: layout)
        return next
    }

    /// Removes the statement that sets `path`, with its line. A key inside an inline table is removed from it. Removing a
    /// key that is not there is a no-op.
    public func removing(_ path: [String]) throws -> TOMLEdit {
        let layout = TOMLLayout(text: text)
        var bytes = layout.bytes
        if let statement = layout.statement(path) {
            bytes.removeSubrange(statement.lines)
        } else if let found = enclosingInline(layout, path) {
            let current = try readInline(layout, found.0)
            bytes.replaceSubrange(found.0.value, with: Array(Self.removing(current, at: found.1).rendered.utf8))
        } else {
            return self
        }
        let next = TOMLEdit(String(decoding: bytes, as: UTF8.self))
        try next.check(path, equals: nil, against: layout)
        return next
    }

    /// Removes the table `[path]`, its statements and every sub-table under it (`[path.x]`), and dotted keys under `path`
    /// elsewhere. Comments inside the removed tables go with them.
    public func removingTable(_ path: [String]) throws -> TOMLEdit {
        let layout = TOMLLayout(text: text)
        var cuts: [Range<Int>] = []
        let starts = layout.headers.map(\.lines.lowerBound) + [layout.bytes.count]
        for (index, header) in layout.headers.enumerated() where header.path.starts(with: path) {
            cuts.append(header.lines.lowerBound..<starts[index + 1])
        }
        for statement in layout.statements where statement.path.starts(with: path) && !cuts.contains(where: { $0.contains(statement.lines.lowerBound) }) {
            cuts.append(statement.lines)
        }
        var bytes = layout.bytes
        for cut in cuts.sorted(by: { $0.lowerBound > $1.lowerBound }) { bytes.removeSubrange(cut) }
        let next = TOMLEdit(String(decoding: bytes, as: UTF8.self))
        let document = TOMLReader.read(next.text)
        if document.entries.contains(where: { ($0.table + $0.keyPath).starts(with: path) }) || document.skippedLines > TOMLReader.read(text).skippedLines {
            throw Self.refusal
        }
        return next
    }

    /// The value at `path` as `TOMLReader` reads it.
    public func value(_ path: [String]) -> TOMLValue? {
        Self.lookup(TOMLReader.read(text), path)
    }

    // MARK: Internals

    static let refusal = ReinsError("Reins could not edit config.toml without changing other lines, so nothing was saved.", status: 409)

    static func keyText(_ parts: [String]) -> String {
        parts.map { part in
            !part.isEmpty && part.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D }
                ? part : TOMLWrite.quote(part)
        }.joined(separator: ".")
    }

    /// A value `TOMLReader` reads at a table-plus-key path, the last assignment winning, inline tables included.
    static func lookup(_ document: TOMLDocument, _ path: [String]) -> TOMLValue? {
        var found: TOMLValue?
        for entry in document.entries where !entry.inArrayTable {
            let full = entry.table + entry.keyPath
            if full == path { found = entry.value }
            else if path.count > full.count, path.starts(with: full), var value = entry.value {
                var ok = true
                for part in path[full.count...] {
                    guard let next = value[part] else { ok = false; break }
                    value = next
                }
                if ok { found = value }
            }
        }
        return found
    }

    private func check(_ path: [String], equals expected: TOMLValue?, against before: TOMLLayout) throws {
        let document = TOMLReader.read(text)
        let previous = TOMLReader.read(String(decoding: before.bytes, as: UTF8.self))
        guard document.skippedLines <= previous.skippedLines, Self.lookup(document, path) == expected else { throw Self.refusal }
    }

    /// The statement whose inline-table value holds `path`, and the path inside it.
    private func enclosingInline(_ layout: TOMLLayout, _ path: [String]) -> (TOMLLayout.Statement, [String])? {
        for statement in layout.statements.reversed() where !statement.inArrayTable && path.count > statement.path.count && path.starts(with: statement.path) {
            guard layout.bytes[statement.value.lowerBound] == 0x7B else { return nil }
            return (statement, Array(path[statement.path.count...]))
        }
        return nil
    }

    private func readInline(_ layout: TOMLLayout, _ statement: TOMLLayout.Statement) throws -> TOMLWrite {
        let snippet = "x = " + String(decoding: layout.bytes[statement.value], as: UTF8.self)
        guard let value = TOMLReader.read(snippet).value([], "x"), let converted = Self.writable(value) else { throw Self.refusal }
        return converted
    }

    static func writable(_ value: TOMLValue) -> TOMLWrite? {
        switch value {
        case .string(let s): return .string(s)
        case .integer(let n): return .integer(n)
        case .bool(let b): return .bool(b)
        case .array(let items):
            let converted = items.compactMap(writable)
            return converted.count == items.count ? .array(converted) : nil
        case .table(let pairs):
            let converted = pairs.compactMap { pair in writable(pair.value).map { (pair.key, $0) } }
            return converted.count == pairs.count ? .table(converted) : nil
        case .float, .raw: return nil
        }
    }

    static func replacing(_ table: TOMLWrite, at path: [String], with value: TOMLWrite) -> TOMLWrite {
        guard let first = path.first else { return value }
        guard case .table(var pairs) = table else { return path.count == 1 ? .table([(first, value)]) : table }
        let rest = Array(path.dropFirst())
        if let index = pairs.lastIndex(where: { $0.0 == first }) {
            pairs[index].1 = replacing(pairs[index].1, at: rest, with: value)
        } else {
            pairs.append((first, replacing(.table([]), at: rest, with: value)))
        }
        return .table(pairs)
    }

    static func removing(_ table: TOMLWrite, at path: [String]) -> TOMLWrite {
        guard let first = path.first, case .table(var pairs) = table else { return table }
        if path.count == 1 {
            pairs.removeAll { $0.0 == first }
        } else if let index = pairs.lastIndex(where: { $0.0 == first }) {
            pairs[index].1 = removing(pairs[index].1, at: Array(path.dropFirst()))
        }
        return .table(pairs)
    }

    /// Where a new key goes: its parent table (added when missing) and the last part as the key.
    private func placement(_ layout: TOMLLayout, _ path: [String]) -> ([String], [String]) {
        (Array(path.dropLast()), [path[path.count - 1]])
    }

    /// After the last statement or header line of `table`, or nil when the table has no header (and is not the top level).
    private func insertionPoint(_ layout: TOMLLayout, table: [String]) -> Int? {
        if table.isEmpty {
            if let last = layout.statements.last(where: { $0.table.isEmpty }) { return last.lines.upperBound }
            return layout.headers.first?.lines.lowerBound ?? layout.bytes.count
        }
        guard let header = layout.headers.last(where: { $0.path == table && !$0.isArray }) else { return nil }
        let inTable = layout.statements.filter { $0.table == table && $0.lines.lowerBound > header.lines.lowerBound }
        let nextHeader = layout.headers.first { $0.lines.lowerBound > header.lines.lowerBound }?.lines.lowerBound ?? layout.bytes.count
        return inTable.filter { $0.lines.lowerBound < nextHeader }.last?.lines.upperBound ?? header.lines.upperBound
    }

    /// A newline when the byte before `at` is not one, so an inserted line never joins the previous one.
    static func newlineBefore(_ bytes: [UInt8], _ at: Int) -> [UInt8] {
        at > 0 && bytes[at - 1] != 0x0A ? [0x0A] : []
    }
}
