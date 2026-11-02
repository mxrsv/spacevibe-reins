import Foundation

/// One `"key": value` pair. Objects keep their pairs in file order, duplicates included.
public struct JSONMember: Equatable, Sendable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

/// A JSON value that keeps object key order. Numbers keep their source text so `1.0` and `1e3` survive a round trip.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])

    public static func int(_ value: Int) -> JSONValue { .number(String(value)) }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var objectValue: [JSONMember]? { if case .object(let o) = self { return o } else { return nil } }
    public var numberText: String? { if case .number(let n) = self { return n } else { return nil } }

    /// The value for a key. With duplicate keys the last one wins, as in `JSON.parse`.
    public subscript(key: String) -> JSONValue? {
        objectValue?.last(where: { $0.key == key })?.value
    }

    public subscript(index: Int) -> JSONValue? {
        guard let items = arrayValue, items.indices.contains(index) else { return nil }
        return items[index]
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(String(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

/// One step of a key path: an object key or an array index. `["permissions", "allow", 0]` is a path.
public enum PathStep: Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case key(String)
    case index(Int)

    public init(stringLiteral value: String) { self = .key(value) }
    public init(integerLiteral value: Int) { self = .index(value) }
}
