import Foundation

/// Parsed JSON with the byte range of every value in the source.
indirect enum JSONNode: Sendable {
    case scalar(JSONValue, Range<Int>)
    case array([JSONNode], Range<Int>)
    case object([JSONNodeMember], Range<Int>)

    var range: Range<Int> {
        switch self {
        case .scalar(_, let r), .array(_, let r), .object(_, let r): return r
        }
    }

    var value: JSONValue {
        switch self {
        case .scalar(let v, _): return v
        case .array(let items, _): return .array(items.map(\.value))
        case .object(let members, _): return .object(members.map { JSONMember($0.key, $0.value.value) })
        }
    }

    /// The text between the first key's closing quote and its value (`: `), when the document has an object member.
    func firstMemberSeparator(in bytes: [UInt8]) -> String? {
        switch self {
        case .scalar: return nil
        case .object(let members, _):
            if let first = members.first {
                return String(decoding: bytes[first.keyEnd..<first.value.range.lowerBound], as: UTF8.self)
            }
            return nil
        case .array(let items, _):
            for item in items { if let found = item.firstMemberSeparator(in: bytes) { return found } }
            return nil
        }
    }
}

struct JSONNodeMember: Sendable {
    let key: String
    let keyStart: Int
    let keyEnd: Int
    let value: JSONNode
}

/// A strict JSON parser (RFC 8259) over UTF-8 bytes that already passed UTF-8 validation.
struct JSONParser {
    let bytes: [UInt8]
    var index = 0
    var depth = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> JSONNode {
        skipBlanks()
        let node = try parseValue()
        skipBlanks()
        if index != bytes.count { throw fail(.trailingContent) }
        return node
    }

    private func fail(_ problem: OrderedJSONError.Problem) -> OrderedJSONError {
        var line = 1
        var column = 1
        for byte in bytes[0..<min(index, bytes.count)] {
            if byte == 0x0A { line += 1; column = 1 } else { column += 1 }
        }
        return .syntax(problem, line: line, column: column)
    }

    private mutating func skipBlanks() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func parseValue() throws -> JSONNode {
        guard index < bytes.count else { throw fail(.unexpectedEnd) }
        let start = index
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""):
            let text = try parseString()
            return .scalar(.string(text), start..<index)
        case UInt8(ascii: "t"): try expect("true"); return .scalar(.bool(true), start..<index)
        case UInt8(ascii: "f"): try expect("false"); return .scalar(.bool(false), start..<index)
        case UInt8(ascii: "n"): try expect("null"); return .scalar(.null, start..<index)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            let end = Self.numberEnd(bytes, from: index)
            guard Self.isNumber(Array(bytes[index..<end])) else { throw fail(.invalidNumber) }
            index = end
            return .scalar(.number(String(decoding: bytes[start..<end], as: UTF8.self)), start..<end)
        default:
            throw fail(.unexpectedCharacter)
        }
    }

    private mutating func expect(_ word: String) throws {
        let letters = Array(word.utf8)
        guard index + letters.count <= bytes.count, Array(bytes[index..<index + letters.count]) == letters else { throw fail(.unexpectedCharacter) }
        index += letters.count
    }

    private mutating func enter() throws {
        depth += 1
        if depth > OrderedJSON.maxDepth { throw OrderedJSONError.tooDeep }
    }

    private mutating func parseObject() throws -> JSONNode {
        try enter()
        defer { depth -= 1 }
        let start = index
        index += 1
        var members: [JSONNodeMember] = []
        skipBlanks()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(members, start..<index)
        }
        while true {
            skipBlanks()
            guard index < bytes.count else { throw fail(.unexpectedEnd) }
            guard bytes[index] == UInt8(ascii: "\"") else { throw fail(.expectedKey) }
            let keyStart = index
            let key = try parseString()
            let keyEnd = index
            skipBlanks()
            guard index < bytes.count else { throw fail(.unexpectedEnd) }
            guard bytes[index] == UInt8(ascii: ":") else { throw fail(.expectedColon) }
            index += 1
            skipBlanks()
            let value = try parseValue()
            members.append(JSONNodeMember(key: key, keyStart: keyStart, keyEnd: keyEnd, value: value))
            skipBlanks()
            guard index < bytes.count else { throw fail(.unexpectedEnd) }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members, start..<index) }
            throw fail(.expectedCommaOrEnd)
        }
    }

    private mutating func parseArray() throws -> JSONNode {
        try enter()
        defer { depth -= 1 }
        let start = index
        index += 1
        var items: [JSONNode] = []
        skipBlanks()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items, start..<index)
        }
        while true {
            skipBlanks()
            items.append(try parseValue())
            skipBlanks()
            guard index < bytes.count else { throw fail(.unexpectedEnd) }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items, start..<index) }
            throw fail(.expectedCommaOrEnd)
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var out: [UInt8] = []
        while true {
            guard index < bytes.count else { throw fail(.unexpectedEnd) }
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return String(decoding: out, as: UTF8.self)
            case 0x00..<0x20:
                throw fail(.controlCharacterInString)
            case UInt8(ascii: "\\"):
                index += 1
                guard index < bytes.count else { throw fail(.unexpectedEnd) }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var unit = try hex4()
                    var scalar = Unicode.Scalar(0xFFFD)!
                    if (0xD800...0xDBFF).contains(unit) {
                        if index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            let save = index
                            index += 2
                            let low = try hex4()
                            if (0xDC00...0xDFFF).contains(low) {
                                unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                                scalar = Unicode.Scalar(unit) ?? scalar
                            } else {
                                index = save // lone high surrogate; the next escape is read on its own
                            }
                        }
                    } else if !(0xDC00...0xDFFF).contains(unit) {
                        scalar = Unicode.Scalar(unit) ?? scalar
                    }
                    out.append(contentsOf: Array(String(scalar).utf8))
                default:
                    index -= 1
                    throw fail(.invalidEscape)
                }
            default:
                out.append(byte)
                index += 1
            }
        }
    }

    private mutating func hex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw fail(.unexpectedEnd) }
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let digit = Self.hexValue(bytes[index]) else { throw fail(.invalidEscape) }
            value = value << 4 | digit
            index += 1
        }
        return value
    }

    private static func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return UInt32(byte - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return UInt32(byte - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }

    /// The end of a run of number characters; `isNumber` then checks the grammar.
    private static func numberEnd(_ bytes: [UInt8], from start: Int) -> Int {
        var end = start
        while end < bytes.count, "+-.0123456789eE".utf8.contains(bytes[end]) { end += 1 }
        return end
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
    static func isNumber(_ text: [UInt8]) -> Bool {
        var i = 0
        func digits() -> Int {
            let start = i
            while i < text.count, (0x30...0x39).contains(text[i]) { i += 1 }
            return i - start
        }
        if i < text.count, text[i] == UInt8(ascii: "-") { i += 1 }
        guard i < text.count else { return false }
        if text[i] == UInt8(ascii: "0") { i += 1 } else if digits() == 0 { return false }
        if i < text.count, text[i] == UInt8(ascii: ".") { i += 1; if digits() == 0 { return false } }
        if i < text.count, text[i] == UInt8(ascii: "e") || text[i] == UInt8(ascii: "E") {
            i += 1
            if i < text.count, text[i] == UInt8(ascii: "+") || text[i] == UInt8(ascii: "-") { i += 1 }
            if digits() == 0 { return false }
        }
        return i == text.count
    }
}
