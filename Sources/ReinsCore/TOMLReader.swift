import Foundation

/// A TOML value. Read-only: Reins displays Codex config and never writes it.
public indirect enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)
    case array([TOMLValue])
    /// An inline table `{ a = 1 }`, pairs in file order.
    case table([TOMLPair])
    /// A bare token that is none of the above (a date and time, `inf`, a malformed number), as written.
    case raw(String)

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var intValue: Int? { if case .integer(let n) = self { return n } else { return nil } }
    public var arrayValue: [TOMLValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var tableValue: [TOMLPair]? { if case .table(let t) = self { return t } else { return nil } }

    /// The string elements of an array; other elements are skipped.
    public var strings: [String] { arrayValue?.compactMap(\.stringValue) ?? [] }

    /// A key of an inline table.
    public subscript(key: String) -> TOMLValue? { tableValue?.last(where: { $0.key == key })?.value }
}

public struct TOMLPair: Equatable, Sendable {
    public let key: String
    public let value: TOMLValue
}

/// One `key = value` line (or a multi-line value) and the table it sits in.
public struct TOMLEntry: Equatable, Sendable {
    /// The table header path in effect: `[projects."/a/b"]` is `["projects", "/a/b"]`; `[]` for the top level.
    public let table: [String]
    /// The key as written, split at dots outside quotes. `a.b = 1` is `["a", "b"]`.
    public let keyPath: [String]
    /// Nil when the value could not be read; the key still counts as present.
    public let value: TOMLValue?
    public let line: Int
    /// True for entries under `[[name]]`.
    public let inArrayTable: Bool

    public var key: String { keyPath.joined(separator: ".") }
}

public struct TOMLTableHeader: Equatable, Sendable {
    public let path: [String]
    /// `[[name]]` rather than `[name]`.
    public let isArray: Bool
}

public struct TOMLDocument: Equatable, Sendable {
    public let entries: [TOMLEntry]
    public let tables: [TOMLTableHeader]
    /// Lines the reader could not make sense of and skipped.
    public let skippedLines: Int

    public func entries(in table: [String]) -> [TOMLEntry] { entries.filter { $0.table == table } }

    /// The value of `key` in `table`. The last assignment wins.
    public func value(_ table: [String], _ key: String) -> TOMLValue? {
        entries.last(where: { $0.table == table && $0.key == key })?.value
    }

    /// Header paths that start with `prefix`, in file order, without repeats.
    public func tablePaths(under prefix: [String]) -> [[String]] {
        var seen: [[String]] = []
        for header in tables where header.path.count >= prefix.count && Array(header.path.prefix(prefix.count)) == prefix {
            if !seen.contains(header.path) { seen.append(header.path) }
        }
        return seen
    }
}

/// A forgiving TOML reader for Codex `config.toml` and agent `.toml` files: tables, `[[arrays]]`, quoted and dotted keys,
/// scalars, arrays (also over several lines), inline tables, and basic, literal and triple-quoted strings. It never throws;
/// lines it cannot read are skipped and counted in `skippedLines`. It does not validate TOML, so a file Codex rejects can
/// still be shown.
public enum TOMLReader {
    public static func read(_ text: String) -> TOMLDocument {
        var parser = TOMLParser(bytes: Array(text.utf8))
        return parser.run()
    }

    /// The document at a URL, or nil when the file is missing or not UTF-8.
    public static func read(contentsOf url: URL) -> TOMLDocument? {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return read(text)
    }
}

private struct TOMLParser {
    let b: [UInt8]
    var i = 0
    var skipped = 0
    let lineStarts: [Int]

    init(bytes: [UInt8]) {
        b = bytes
        var starts = [0]
        for (offset, byte) in bytes.enumerated() where byte == 0x0A { starts.append(offset + 1) }
        lineStarts = starts
    }

    func line(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    mutating func run() -> TOMLDocument {
        var table: [String] = []
        var inArrayTable = false
        var entries: [TOMLEntry] = []
        var headers: [TOMLTableHeader] = []
        while true {
            skipTrivia()
            guard i < b.count else { break }
            if b[i] == UInt8(ascii: "[") {
                if let header = parseHeader() {
                    headers.append(header)
                    table = header.path
                    inArrayTable = header.isArray
                } else {
                    skipLine(count: true)
                }
                continue
            }
            let start = i
            guard let keyPath = parseKeyPath() else { skipLine(count: true); continue }
            skipSpaces()
            guard i < b.count, b[i] == UInt8(ascii: "=") else { skipLine(count: true); continue }
            i += 1
            skipSpaces()
            let value = parseValue()
            entries.append(TOMLEntry(table: table, keyPath: keyPath, value: value, line: line(at: start), inArrayTable: inArrayTable))
            if value == nil { skipLine(count: true) } else { skipRestOfLine() }
        }
        return TOMLDocument(entries: entries, tables: headers, skippedLines: skipped)
    }

    // MARK: Lines

    private mutating func skipSpaces() {
        while i < b.count, b[i] == 0x20 || b[i] == 0x09 { i += 1 }
    }

    private mutating func skipComment() {
        if i < b.count, b[i] == UInt8(ascii: "#") { while i < b.count, b[i] != 0x0A { i += 1 } }
    }

    private mutating func skipTrivia() {
        while i < b.count {
            if b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D { i += 1 } else if b[i] == UInt8(ascii: "#") { skipComment() } else { break }
        }
    }

    private mutating func skipLine(count: Bool) {
        while i < b.count, b[i] != 0x0A { i += 1 }
        if count { skipped += 1 }
    }

    /// After a value: blanks and a comment are fine; anything else is garbage on the line and is skipped.
    private mutating func skipRestOfLine() {
        skipSpaces()
        skipComment()
        if i < b.count, b[i] != 0x0A, b[i] != 0x0D { skipLine(count: true) }
    }

    // MARK: Headers and keys

    private mutating func parseHeader() -> TOMLTableHeader? {
        let isArray = i + 1 < b.count && b[i + 1] == UInt8(ascii: "[")
        i += isArray ? 2 : 1
        guard let path = parseKeyPath() else { return nil }
        skipSpaces()
        for _ in 0..<(isArray ? 2 : 1) {
            guard i < b.count, b[i] == UInt8(ascii: "]") else { return nil }
            i += 1
        }
        skipRestOfLine()
        return TOMLTableHeader(path: path, isArray: isArray)
    }

    private mutating func parseKeyPath() -> [String]? {
        var parts: [String] = []
        while true {
            skipSpaces()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: "\"") {
                guard let s = parseBasicString() else { return nil }
                parts.append(s)
            } else if b[i] == UInt8(ascii: "'") {
                guard let s = parseLiteralString() else { return nil }
                parts.append(s)
            } else {
                let start = i
                while i < b.count, Self.isBare(b[i]) { i += 1 }
                if i == start { return nil }
                parts.append(String(decoding: b[start..<i], as: UTF8.self))
            }
            skipSpaces()
            if i < b.count, b[i] == UInt8(ascii: ".") { i += 1; continue }
            return parts
        }
    }

    private static func isBare(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
    }

    // MARK: Values

    private mutating func parseValue() -> TOMLValue? {
        guard i < b.count else { return nil }
        switch b[i] {
        case UInt8(ascii: "\""):
            if has("\"\"\"") { return parseMultiline(quote: UInt8(ascii: "\""), literal: false).map(TOMLValue.string) }
            return parseBasicString().map(TOMLValue.string)
        case UInt8(ascii: "'"):
            if has("'''") { return parseMultiline(quote: UInt8(ascii: "'"), literal: true).map(TOMLValue.string) }
            return parseLiteralString().map(TOMLValue.string)
        case UInt8(ascii: "["): return parseArray()
        case UInt8(ascii: "{"): return parseInlineTable()
        default: return parseBare()
        }
    }

    private func has(_ text: String) -> Bool {
        let letters = Array(text.utf8)
        return i + letters.count <= b.count && Array(b[i..<i + letters.count]) == letters
    }

    private mutating func parseBare() -> TOMLValue? {
        let start = i
        while i < b.count, ![0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), UInt8(ascii: "#")].contains(b[i]) { i += 1 }
        guard i > start else { return nil }
        var token = String(decoding: b[start..<i], as: UTF8.self)
        // A datetime may hold one space between date and time.
        if token.count == 10, token.contains("-"), i + 1 < b.count, b[i] == 0x20, (0x30...0x39).contains(b[i + 1]) {
            let save = i
            i += 1
            let timeStart = i
            while i < b.count, ![0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), UInt8(ascii: "#")].contains(b[i]) { i += 1 }
            let time = String(decoding: b[timeStart..<i], as: UTF8.self)
            if time.contains(":") { token += " " + time } else { i = save }
        }
        if token == "true" { return .bool(true) }
        if token == "false" { return .bool(false) }
        let digits = token.replacingOccurrences(of: "_", with: "")
        if let n = Int(digits) { return .integer(n) }
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where digits.hasPrefix(prefix) {
            if let n = Int(digits.dropFirst(2), radix: radix) { return .integer(n) }
        }
        if digits.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }), let d = Double(digits), !digits.hasSuffix(".") { return .float(d) }
        return .raw(token)
    }

    private mutating func parseArray() -> TOMLValue? {
        i += 1
        var items: [TOMLValue] = []
        while true {
            skipTrivia()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            guard let item = parseValue() else { return nil }
            items.append(item)
            skipTrivia()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: ",") { i += 1 } else if b[i] != UInt8(ascii: "]") { return nil }
        }
    }

    private mutating func parseInlineTable() -> TOMLValue? {
        i += 1
        var pairs: [TOMLPair] = []
        while true {
            skipTrivia()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: "}") { i += 1; return .table(pairs) }
            guard let path = parseKeyPath() else { return nil }
            skipSpaces()
            guard i < b.count, b[i] == UInt8(ascii: "=") else { return nil }
            i += 1
            skipSpaces()
            guard let value = parseValue() else { return nil }
            pairs.append(TOMLPair(key: path.joined(separator: "."), value: value))
            skipTrivia()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: ",") { i += 1 } else if b[i] != UInt8(ascii: "}") { return nil }
        }
    }

    // MARK: Strings

    private mutating func parseLiteralString() -> String? {
        i += 1
        let start = i
        while i < b.count, b[i] != UInt8(ascii: "'") {
            if b[i] == 0x0A { return nil }
            i += 1
        }
        guard i < b.count else { return nil }
        defer { i += 1 }
        return String(decoding: b[start..<i], as: UTF8.self)
    }

    private mutating func parseBasicString() -> String? {
        i += 1
        var out: [UInt8] = []
        while i < b.count {
            let byte = b[i]
            if byte == UInt8(ascii: "\"") { i += 1; return String(decoding: out, as: UTF8.self) }
            if byte == 0x0A { return nil }
            if byte == UInt8(ascii: "\\") {
                guard appendEscape(&out) else { return nil }
            } else {
                out.append(byte)
                i += 1
            }
        }
        return nil
    }

    /// `"""` or `'''` strings. A newline right after the opening is dropped; up to two quotes may precede the closing.
    private mutating func parseMultiline(quote: UInt8, literal: Bool) -> String? {
        i += 3
        if i < b.count, b[i] == 0x0D, i + 1 < b.count, b[i + 1] == 0x0A { i += 2 } else if i < b.count, b[i] == 0x0A { i += 1 }
        var out: [UInt8] = []
        while i < b.count {
            let byte = b[i]
            if byte == quote, i + 2 < b.count, b[i + 1] == quote, b[i + 2] == quote {
                var extra = 0
                while extra < 2, i + 3 + extra < b.count, b[i + 3 + extra] == quote { extra += 1 }
                out.append(contentsOf: [UInt8](repeating: quote, count: extra))
                i += 3 + extra
                return String(decoding: out, as: UTF8.self)
            }
            if !literal, byte == UInt8(ascii: "\\") {
                // A backslash at the end of a line swallows the newline and the blanks that follow.
                var look = i + 1
                while look < b.count, b[look] == 0x20 || b[look] == 0x09 || b[look] == 0x0D { look += 1 }
                if look < b.count, b[look] == 0x0A {
                    i = look + 1
                    while i < b.count, [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
                    continue
                }
                guard appendEscape(&out) else { return nil }
                continue
            }
            out.append(byte)
            i += 1
        }
        return nil
    }

    /// Reads `\x` at `i`. An unknown escape is kept as written rather than failing the file.
    private mutating func appendEscape(_ out: inout [UInt8]) -> Bool {
        i += 1
        guard i < b.count else { return false }
        let code = b[i]
        i += 1
        switch code {
        case UInt8(ascii: "b"): out.append(0x08)
        case UInt8(ascii: "t"): out.append(0x09)
        case UInt8(ascii: "n"): out.append(0x0A)
        case UInt8(ascii: "f"): out.append(0x0C)
        case UInt8(ascii: "r"): out.append(0x0D)
        case UInt8(ascii: "e"): out.append(0x1B)
        case UInt8(ascii: "\""): out.append(0x22)
        case UInt8(ascii: "\\"): out.append(0x5C)
        case UInt8(ascii: "u"), UInt8(ascii: "U"):
            let length = code == UInt8(ascii: "u") ? 4 : 8
            guard i + length <= b.count, let value = UInt32(String(decoding: b[i..<i + length], as: UTF8.self), radix: 16), let scalar = Unicode.Scalar(value) else { return false }
            i += length
            out.append(contentsOf: Array(String(scalar).utf8))
        default:
            out.append(UInt8(ascii: "\\"))
            out.append(code)
        }
        return true
    }
}
