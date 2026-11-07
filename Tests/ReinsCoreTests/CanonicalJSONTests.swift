import Foundation
import Testing

/// The canonical writer behind the Swift-recorded goldens (C1). The Go writer must pass the same vectors.
@Suite("Canonical JSON")
struct CanonicalJSONTests {
    @Test("numbers print as ES6 JSON.stringify does")
    func numbers() throws {
        let vectors: [(Double, String)] = [
            (0, "0"), (-0.0, "0"), (8, "8"), (-12.5, "-12.5"), (100, "100"), (95.5, "95.5"),
            (1_793_500_000.25, "1793500000.25"), (1_794_000_000, "1794000000"),
            (0.1 + 0.2, "0.30000000000000004"), (0.000001, "0.000001"), (0.0000001, "1e-7"),
            (1.5e-7, "1.5e-7"), (1e20, "100000000000000000000"), (1e21, "1e+21"),
            (123_456_789_012_345_680_000, "123456789012345680000"), (1.5e300, "1.5e+300"),
            (5e-324, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308"),
            (9_007_199_254_740_993, "9007199254740992"),
        ]
        for (value, expected) in vectors {
            #expect(try CanonicalJSON.numberText(value) == expected, "\(value)")
        }
        #expect(throws: CanonicalJSON.NotEncodable.self) { try CanonicalJSON.numberText(.nan) }
        #expect(throws: CanonicalJSON.NotEncodable.self) { try CanonicalJSON.numberText(.infinity) }
    }

    @Test("keys sort by UTF-16 units, strings escape as JSON.stringify does, and $HOME replaces the root in keys and values")
    func layout() throws {
        let value: CanonicalJSON = [
            "b": [],
            "a": [:],
            "\u{1F600}": 1,
            "\u{FFFD}": 2,
            "text": "q\" b\\ s/ <&> \u{08}\u{0C}\n\r\t\u{01}\u{7F} \u{2028} é",
            "/tmp/root/key": ["/tmp/root/value", nil, true, 1.5],
        ]
        // U+1F600 is the surrogate pair D83D DE00, which sorts before U+FFFD; scalar order would put it after.
        let expected = """
        {
          "$HOME/key": [
            "$HOME/value",
            null,
            true,
            1.5
          ],
          "a": {},
          "b": [],
          "text": "q\\" b\\\\ s/ <&> \\b\\f\\n\\r\\t\\u0001\u{7F} \u{2028} é",
          "\u{1F600}": 1,
          "\u{FFFD}": 2
        }

        """
        #expect(try value.replacingHome("/tmp/root").text() == expected)
    }
}
