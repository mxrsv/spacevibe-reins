import Foundation

/// The canonical golden text (C1, Q1): what the Go `goldentest` writer must also produce, byte for byte.
/// Sorted keys (UTF-16 order), 2-space indent, `JSON.stringify` number text (ES6 `Number::toString`), no HTML escaping,
/// one trailing newline; `replacingHome` writes a home folder as `$HOME` in keys and values.
enum CanonicalJSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([CanonicalJSON])
    case object([String: CanonicalJSON])

    struct NotEncodable: Error { let reason: String }

    static let homeToken = "$HOME"

    func text() throws -> String {
        var out = ""
        try write(into: &out, indent: "")
        return out + "\n"
    }

    /// The value with `root` written as `$HOME` in every key and string.
    func replacingHome(_ root: String) -> CanonicalJSON {
        func swap(_ text: String) -> String { text.replacingOccurrences(of: root, with: Self.homeToken) }
        switch self {
        case .string(let value): return .string(swap(value))
        case .array(let items): return .array(items.map { $0.replacingHome(root) })
        case .object(let members): return .object(Dictionary(uniqueKeysWithValues: members.map { (swap($0.key), $0.value.replacingHome(root)) }))
        default: return self
        }
    }

    private func write(into out: inout String, indent: String) throws {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let value): out += try Self.numberText(value)
        case .string(let value): Self.writeString(value, into: &out)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            let inner = indent + "  "
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += inner
                try item.write(into: &out, indent: inner)
                out += index == items.count - 1 ? "\n" : ",\n"
            }
            out += indent + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            let inner = indent + "  "
            let keyed = members.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
            out += "{\n"
            for (index, member) in keyed.enumerated() {
                out += inner
                Self.writeString(member.key, into: &out)
                out += ": "
                try member.value.write(into: &out, indent: inner)
                out += index == keyed.count - 1 ? "\n" : ",\n"
            }
            out += indent + "}"
        }
    }

    /// `JSON.stringify` string escaping: `"` `\` and C0 controls only; `/`, `<`, `&`, U+2028 and non-ASCII stay raw.
    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += "\\u" + String(format: "%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    /// ES6 `Number::toString(10)`: integers have no `.0`, and the digits are the shortest that round-trip. Swift's
    /// `description` supplies those digits (it is shortest round-trip too) but chooses other layouts, so the digits
    /// are laid out again by the ES6 rules.
    static func numberText(_ value: Double) throws -> String {
        guard value.isFinite else { throw NotEncodable(reason: "\(value) is not a JSON number") }
        if value == 0 { return "0" }
        let sign = value < 0 ? "-" : ""
        let described = "\(abs(value))"
        let parts = described.split(separator: "e", maxSplits: 1).map(String.init)
        let mantissa = parts[0].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let exponent = parts.count > 1 ? Int(parts[1])! : 0
        var digits = Array(mantissa[0] + (mantissa.count > 1 ? mantissa[1] : ""))
        // n: the value is 0.d1d2...dk * 10^n
        var n = mantissa[0].count + exponent
        while digits.first == "0" { digits.removeFirst(); n -= 1 }
        while digits.last == "0" { digits.removeLast() }
        let k = digits.count
        let run = String(digits)
        switch n {
        case k...21: return sign + run + String(repeating: "0", count: n - k)
        case 1...21: return sign + String(digits[..<n]) + "." + String(digits[n...])
        case -5...0: return sign + "0." + String(repeating: "0", count: -n) + run
        default:
            let e = n - 1
            let power = "e" + (e < 0 ? "-" : "+") + String(abs(e))
            return sign + String(digits[0]) + (k > 1 ? "." + String(digits[1...]) : "") + power
        }
    }
}

extension CanonicalJSON: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(nilLiteral: ()) { self = .null }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(stringLiteral value: String) { self = .string(value) }
    init(arrayLiteral elements: CanonicalJSON...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, CanonicalJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
