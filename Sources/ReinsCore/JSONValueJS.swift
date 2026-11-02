import Foundation

// JSON access with JavaScript semantics, for the log folds that port core/*.mjs (Activity, the token ledger).
// `field` treats JSON null like a missing key, as `??` does in the Node code.

extension JSONValue {
    /// The member, or nil for a missing key or JSON null (what `??` treats as nullish).
    func field(_ key: String) -> JSONValue? {
        guard let v = self[key], v != .null else { return nil }
        return v
    }

    var number: Double? { numberText.flatMap { Double($0) } }

    /// JavaScript truthiness.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let text): return Double(text).map { $0 != 0 && !$0.isNaN } ?? true
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// `Number.isInteger`
    var integer: Int? {
        guard let d = number, d.isFinite, d == d.rounded(), abs(d) < 9e15 else { return nil }
        return Int(d)
    }
}

extension Optional where Wrapped == JSONValue {
    func field(_ key: String) -> JSONValue? { self?.field(key) }
    var string: String? { self?.stringValue }
    var truthy: Bool { self?.truthy ?? false }
}
