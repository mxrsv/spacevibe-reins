import Foundation

/// A member the wire always writes, as `null` when it has no value (docs/internals/core-protocol.md, "Wire types").
/// Swift's synthesized `Encodable` leaves a nil member out, which would not round-trip the core's JSON; this wrapper
/// writes the `null`. A missing key decodes as nil, like an explicit `null`.
///
/// Members the wire omits when absent (`cells`, a counted cell's `errors`) stay plain optionals.
@propertyWrapper
struct CoreNullable<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue) } else { try container.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    func decode<Value>(_ type: CoreNullable<Value>.Type, forKey key: Key) throws -> CoreNullable<Value> {
        try decodeIfPresent(type, forKey: key) ?? CoreNullable(wrappedValue: nil)
    }
}
