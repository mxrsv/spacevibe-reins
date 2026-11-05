import Foundation

/// Where things sit in a TOML file, by byte: each table header and each `key = value` statement, with the value's exact
/// bytes and the whole line around it (comment and newline included). `TOMLEdit` splices edits into these ranges and
/// `SecretMask` finds secret values with them; every other byte (comments, blank lines, spacing) is left as it is.
///
/// It reads the same shapes as `TOMLReader` (tables, `[[arrays]]`, quoted and dotted keys, scalars, multi-line arrays,
/// inline tables, basic, literal and triple-quoted strings) and, like it, never throws: a line it cannot read is skipped.
struct TOMLLayout {
    struct Header: Equatable {
        let path: [String]
        let isArray: Bool
        /// The header's line, from its first byte to after its newline.
        let lines: Range<Int>
    }

    struct Statement: Equatable {
        /// The header in effect (`[]` before the first one).
        let table: [String]
        let inArrayTable: Bool
        let keyPath: [String]
        /// The value as written: a string literal with its quotes, an array or inline table with its brackets.
        let value: Range<Int>
        /// From the first byte of the statement's line to after the newline ending its last line.
        let lines: Range<Int>

        var path: [String] { table + keyPath }
    }

    /// A scalar inside a value, for `SecretMask`: its path below the statement (`["env", "API_KEY"]` inside an inline
    /// table, `"[0]"` for an array element) and its bytes.
    struct Leaf: Equatable {
        let path: [String]
        let range: Range<Int>
    }

    let bytes: [UInt8]
    private(set) var headers: [Header] = []
    private(set) var statements: [Statement] = []

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        scan()
    }

    init(text: String) { self.init(Array(text.utf8)) }

    /// The statement that sets `path` (table plus dotted key), the last one when it is set twice.
    func statement(_ path: [String]) -> Statement? {
        statements.last { $0.path == path && !$0.inArrayTable }
    }

    /// The first line (from 1) that holds something other than a header, a statement, a comment or blanks, or nil.
    func firstUnreadableLine() -> Int? {
        var covered = [Bool](repeating: false, count: bytes.count)
        for range in headers.map(\.lines) + statements.map(\.lines) {
            for index in range { covered[index] = true }
        }
        var line = 1
        var i = 0
        while i < bytes.count {
            var j = i
            while j < bytes.count, bytes[j] != 0x0A { j += 1 }
            var k = i
            while k < j, bytes[k] == 0x20 || bytes[k] == 0x09 || bytes[k] == 0x0D { k += 1 }
            if k < j, bytes[k] != 0x23, !covered[k] { return line }
            line += 1
            i = j + 1
        }
        return nil
    }

    // MARK: Scan

    private mutating func scan() {
        var i = 0
        var table: [String] = []
        var inArray = false
        let n = bytes.count
        while i < n {
            let lineStart = i
            i = skipBlanks(i)
            guard i < n else { break }
            let c = bytes[i]
            if c == 0x0A { i += 1; continue }
            if c == 0x0D || c == 0x23 { i = lineEnd(i); continue }
            if c == 0x5B {
                let isArray = i + 1 < n && bytes[i + 1] == 0x5B
                guard let found = key(at: i + (isArray ? 2 : 1)) else { i = lineEnd(i); continue }
                let (path, after) = found
                var j = skipBlanks(after)
                guard j < n, bytes[j] == 0x5D else { i = lineEnd(i); continue }
                j += 1
                if isArray {
                    guard j < n, bytes[j] == 0x5D else { i = lineEnd(i); continue }
                    j += 1
                }
                table = path
                inArray = isArray
                i = lineEnd(j)
                headers.append(Header(path: path, isArray: isArray, lines: lineStart..<i))
                continue
            }
            guard let found = key(at: i) else { i = lineEnd(i); continue }
            let (keyPath, after) = found
            var j = skipBlanks(after)
            guard j < n, bytes[j] == 0x3D else { i = lineEnd(i); continue }
            j = skipBlanks(j + 1)
            guard let end = valueEnd(at: j) else { i = lineEnd(i); continue }
            i = lineEnd(end)
            statements.append(Statement(table: table, inArrayTable: inArray, keyPath: keyPath, value: j..<end, lines: lineStart..<i))
        }
    }

    /// Spaces and tabs.
    private func skipBlanks(_ start: Int) -> Int {
        var i = start
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x09 { i += 1 }
        return i
    }

    /// After the newline that ends the line `start` is on (a comment or stray text before it is skipped).
    private func lineEnd(_ start: Int) -> Int {
        var i = start
        while i < bytes.count, bytes[i] != 0x0A { i += 1 }
        return min(i + 1, bytes.count)
    }

    private static func isBare(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F || byte == 0x2D
    }

    /// A dotted key: bare, "basic" or 'literal' parts with optional blanks around the dots.
    func key(at start: Int) -> ([String], Int)? {
        var parts: [String] = []
        var i = start
        while true {
            i = skipBlanks(i)
            guard i < bytes.count else { return nil }
            if bytes[i] == 0x22 || bytes[i] == 0x27 {
                guard let found = quotedKey(at: i) else { return nil }
                parts.append(found.0)
                i = found.1
            } else {
                var j = i
                while j < bytes.count, Self.isBare(bytes[j]) { j += 1 }
                guard j > i else { return nil }
                parts.append(String(decoding: bytes[i..<j], as: UTF8.self))
                i = j
            }
            let next = skipBlanks(i)
            if next < bytes.count, bytes[next] == 0x2E {
                i = next + 1
                continue
            }
            return (parts, i)
        }
    }

    /// A one-line quoted key, decoded (basic strings take their escapes).
    private func quotedKey(at start: Int) -> (String, Int)? {
        let quote = bytes[start]
        var out: [UInt8] = []
        var i = start + 1
        while i < bytes.count, bytes[i] != quote {
            if bytes[i] == 0x0A { return nil }
            if quote == 0x22, bytes[i] == 0x5C, i + 1 < bytes.count {
                let next = bytes[i + 1]
                switch next {
                case 0x6E: out.append(0x0A)
                case 0x74: out.append(0x09)
                case 0x72: out.append(0x0D)
                case 0x22, 0x5C: out.append(next)
                default: out.append(contentsOf: [0x5C, next])
                }
                i += 2
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        guard i < bytes.count else { return nil }
        return (String(decoding: out, as: UTF8.self), i + 1)
    }

    /// The end of the value that starts at `start`, or nil when it does not close.
    func valueEnd(at start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        let c = bytes[start]
        if c == 0x22 || c == 0x27 { return stringEnd(at: start) }
        if c == 0x5B || c == 0x7B { return bracketEnd(at: start) }
        var i = start
        while i < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, 0x23, 0x2C, 0x5D, 0x7D].contains(bytes[i]) { i += 1 }
        return i > start ? i : nil
    }

    private func has(_ text: [UInt8], at i: Int) -> Bool {
        i + text.count <= bytes.count && Array(bytes[i..<(i + text.count)]) == text
    }

    /// A string literal of any of the four kinds.
    private func stringEnd(at start: Int) -> Int? {
        let quote = bytes[start]
        let triple = [quote, quote, quote]
        if has(triple, at: start) {
            var i = start + 3
            while i < bytes.count {
                if quote == 0x22, bytes[i] == 0x5C { i += 2; continue }
                if has(triple, at: i) {
                    var end = i + 3
                    // Up to two more quotes belong to the content: `""""a"""""`.
                    while end < bytes.count, bytes[end] == quote, end - i < 5 { end += 1 }
                    return end
                }
                i += 1
            }
            return nil
        }
        var i = start + 1
        while i < bytes.count, bytes[i] != quote {
            if bytes[i] == 0x0A { return nil }
            if quote == 0x22, bytes[i] == 0x5C { i += 1 }
            i += 1
        }
        return i < bytes.count ? i + 1 : nil
    }

    /// An array or inline table, over several lines too, skipping strings and comments inside it.
    private func bracketEnd(at start: Int) -> Int? {
        var depth = 0
        var i = start
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x22 || c == 0x27 {
                guard let end = stringEnd(at: i) else { return nil }
                i = end
                continue
            }
            if c == 0x23 {
                while i < bytes.count, bytes[i] != 0x0A { i += 1 }
                continue
            }
            if c == 0x5B || c == 0x7B { depth += 1 }
            if c == 0x5D || c == 0x7D {
                depth -= 1
                if depth == 0 { return i + 1 }
            }
            i += 1
        }
        return nil
    }

    // MARK: Leaves

    /// Every scalar inside `range` (a statement's value), with its path below the statement.
    func leaves(in range: Range<Int>) -> [Leaf] {
        var out: [Leaf] = []
        collect(range, path: [], into: &out)
        return out
    }

    private func collect(_ range: Range<Int>, path: [String], into out: inout [Leaf]) {
        guard !range.isEmpty else { return }
        let c = bytes[range.lowerBound]
        if c == 0x7B {
            var i = range.lowerBound + 1
            while i < range.upperBound - 1 {
                i = skipFiller(i, until: range.upperBound - 1)
                guard i < range.upperBound - 1, let found = key(at: i) else { return }
                let (keyPath, after) = found
                var j = skipBlanks(after)
                guard j < range.upperBound, bytes[j] == 0x3D else { return }
                j = skipFiller(j + 1, until: range.upperBound - 1)
                guard let end = valueEnd(at: j), end <= range.upperBound - 1 else { return }
                collect(j..<end, path: path + keyPath, into: &out)
                i = end
            }
        } else if c == 0x5B {
            var i = range.lowerBound + 1
            var index = 0
            while i < range.upperBound - 1 {
                i = skipFiller(i, until: range.upperBound - 1)
                guard i < range.upperBound - 1, let end = valueEnd(at: i), end <= range.upperBound - 1 else { return }
                collect(i..<end, path: path + ["[\(index)]"], into: &out)
                index += 1
                i = end
            }
        } else {
            out.append(Leaf(path: path, range: range))
        }
    }

    /// Blanks, newlines, commas and comments between the parts of an array or inline table.
    private func skipFiller(_ start: Int, until end: Int) -> Int {
        var i = start
        while i < end {
            let c = bytes[i]
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C { i += 1; continue }
            if c == 0x23 {
                while i < end, bytes[i] != 0x0A { i += 1 }
                continue
            }
            break
        }
        return i
    }
}
