import Foundation
import Testing
@testable import ReinsCore

@Suite("OrderedJSON")
struct OrderedJSONTests {
    private func doc(_ text: String) throws -> OrderedJSON { try OrderedJSON(text: text) }

    // MARK: Round trip

    private static let samples: [(name: String, text: String)] = [
        ("two spaces, trailing newline", "{\n  \"b\": 1,\n  \"a\": [\n    true,\n    null\n  ]\n}\n"),
        ("tabs, no trailing newline", "{\n\t\"b\": {\n\t\t\"c\": \"x\"\n\t}\n}"),
        ("four spaces", "{\n    \"z\": 1,\n    \"y\": 2\n}\n"),
        ("CRLF", "{\r\n  \"a\": 1,\r\n  \"b\": [\r\n    2\r\n  ]\r\n}\r\n"),
        ("minified", "{\"a\":1,\"b\":[1,2,{\"c\":null}]}"),
        ("odd spacing", "{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2 ]   }  \n\n"),
        ("numbers keep their text", "[1.0, 1e3, -0, 0.50, 1E+2, 12345678901234567890]"),
        ("escapes and unicode", "{\"é\":\"\\u00e9 \\ud83d\\ude42 🙂 \\n \\/ \\\\ \\\"\",\"k\":\"\\ud800\"}"),
        ("scalar root", "  \"just a string\"\n"),
        ("empty containers", "{\"a\":{},\"b\":[],\"c\":[ ],\"d\":{ }}"),
        ("duplicate keys", "{\"a\":1,\"a\":2}"),
    ]

    @Test("an unmodified document is written back as the same bytes", arguments: samples)
    func roundTrip(sample: (name: String, text: String)) throws {
        let parsed = try doc(sample.text)
        #expect(parsed.data == Data(sample.text.utf8), "\(sample.name)")
        #expect(parsed.text == sample.text)
    }

    @Test("a fixture settings file round-trips byte for byte")
    func fixtureRoundTrip() throws {
        let original = try Fixtures.data("home/.claude/settings.json")
        #expect(try OrderedJSON(data: original).data == original)
    }

    @Test("values parse with key order and duplicates kept")
    func values() throws {
        let parsed = try doc("{\"b\":1,\"a\":[true,null,\"x\"],\"b\":2}")
        #expect(parsed.root.objectValue?.map(\.key) == ["b", "a", "b"])
        #expect(parsed.root["b"] == .number("2"))
        #expect(parsed[["a", 2]] == "x")
        #expect(parsed[["a", 9]] == nil)
        #expect(parsed[["nope", "deeper"]] == nil)
    }

    @Test("escapes decode, including surrogate pairs and a lone surrogate")
    func escapes() throws {
        let parsed = try doc("{\"s\":\"\\u00e9\\ud83d\\ude42\\n\\/\",\"lone\":\"\\ud800x\"}")
        #expect(parsed.root["s"] == .string("é🙂\n/"))
        #expect(parsed.root["lone"] == .string("\u{FFFD}x"))
    }

    // MARK: Edits keep the rest of the file

    @Test("replacing a value touches only that value")
    func replaceInPlace() throws {
        let source = "{\n  \"a\": 1,\n  \"model\": \"old\",\n  \"z\": [1, 2]\n}\n"
        let edited = try doc(source).setting(["model"], to: "new")
        #expect(edited.text == "{\n  \"a\": 1,\n  \"model\": \"new\",\n  \"z\": [1, 2]\n}\n")
        let nested = try doc(source).setting(["z", 1], to: .int(20))
        #expect(nested.text == "{\n  \"a\": 1,\n  \"model\": \"old\",\n  \"z\": [1, 20]\n}\n")
    }

    @Test("a new key goes at the end, in the document's indent")
    func addKey() throws {
        #expect(try doc("{\n  \"a\": 1\n}\n").setting(["b"], to: true).text == "{\n  \"a\": 1,\n  \"b\": true\n}\n")
        #expect(try doc("{\n\t\"a\": 1\n}").setting(["b"], to: "x").text == "{\n\t\"a\": 1,\n\t\"b\": \"x\"\n}")
        #expect(try doc("{\r\n    \"a\": 1\r\n}\r\n").setting(["b"], to: .int(2)).text == "{\r\n    \"a\": 1,\r\n    \"b\": 2\r\n}\r\n")
        #expect(try doc("{\"a\":1}").setting(["b"], to: .int(2)).text == "{\"a\":1,\"b\":2}")
        #expect(try doc("{ \"a\": 1 }").setting(["b"], to: .int(2)).text == "{ \"a\": 1, \"b\": 2 }")
    }

    @Test("missing parents are created as nested objects")
    func createParents() throws {
        let edited = try doc("{\n  \"a\": 1\n}\n").setting(["permissions", "defaultMode"], to: "plan")
        #expect(edited.text == "{\n  \"a\": 1,\n  \"permissions\": {\n    \"defaultMode\": \"plan\"\n  }\n}\n")
        #expect(try doc("{}\n").setting(["a", "b"], to: .int(1)).text == "{\n  \"a\": {\n    \"b\": 1\n  }\n}\n")
        #expect(try doc("{}").setting(["a"], to: .int(1)).text == "{\"a\":1}")
    }

    @Test("appending to an array: multi-line, inline, empty and missing")
    func append() throws {
        let multi = "{\n  \"permissions\": {\n    \"allow\": [\n      \"Read\",\n      \"Edit\"\n    ]\n  }\n}\n"
        #expect(try doc(multi).appending("Bash(git status:*)", to: ["permissions", "allow"]).text ==
            "{\n  \"permissions\": {\n    \"allow\": [\n      \"Read\",\n      \"Edit\",\n      \"Bash(git status:*)\"\n    ]\n  }\n}\n")
        #expect(try doc("{\"a\": [\"x\", \"y\"]}").appending("z", to: ["a"]).text == "{\"a\": [\"x\", \"y\", \"z\"]}")
        #expect(try doc("{\"a\":[\"x\"]}").appending("z", to: ["a"]).text == "{\"a\":[\"x\",\"z\"]}")
        #expect(try doc("{\n  \"a\": []\n}\n").appending("z", to: ["a"]).text == "{\n  \"a\": [\n    \"z\"\n  ]\n}\n")
        #expect(try doc("{\n  \"a\": 1\n}\n").appending("z", to: ["permissions", "deny"]).text ==
            "{\n  \"a\": 1,\n  \"permissions\": {\n    \"deny\": [\n      \"z\"\n    ]\n  }\n}\n")
    }

    @Test("removing keeps the commas valid wherever the member sits")
    func remove() throws {
        let source = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3\n}\n"
        #expect(try doc(source).removing(["a"]).text == "{\n  \"b\": 2,\n  \"c\": 3\n}\n")
        #expect(try doc(source).removing(["b"]).text == "{\n  \"a\": 1,\n  \"c\": 3\n}\n")
        #expect(try doc(source).removing(["c"]).text == "{\n  \"a\": 1,\n  \"b\": 2\n}\n")
        #expect(try doc("{\n  \"a\": 1\n}\n").removing(["a"]).text == "{}\n")
        #expect(try doc("{\"a\":[1,2,3]}").removing(["a", 1]).text == "{\"a\":[1,3]}")
        #expect(try doc("{\"a\":[1,2,3]}").removing(["a", 2]).text == "{\"a\":[1,2]}")
        #expect(try doc("{\"a\":[1]}").removing(["a", 0]).text == "{\"a\":[]}")
    }

    @Test("a nested object value is written in the document's style")
    func nestedValue() throws {
        let value = JSONValue.object([JSONMember("type", "command"), JSONMember("args", .array(["a", "b"]))])
        let edited = try doc("{\n  \"hooks\": []\n}\n").setting(["hooks", 0], to: value)
        #expect(edited.text == "{\n  \"hooks\": [\n    {\n      \"type\": \"command\",\n      \"args\": [\n        \"a\",\n        \"b\"\n      ]\n    }\n  ]\n}\n")
    }

    @Test("only the edited region changes: bytes before and after are identical")
    func onlyTheRegionChanges() throws {
        let source = try Fixtures.data("home/.claude/settings.json")
        let before = try OrderedJSON(data: source)
        let after = try before.appending("Bash(echo hi:*)", to: ["permissions", "allow"])
        let old = [UInt8](source), new = after.bytes
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let changed = String(decoding: new[prefix..<(new.count - suffix)], as: UTF8.self)
        #expect(changed.contains("Bash(echo hi:*)"))
        #expect(changed.count < 80)
        #expect(after.root["hooks"] == before.root["hooks"])
        #expect(after.root["env"] == before.root["env"])
        #expect(after[["permissions", "allow"]]?.arrayValue?.last == "Bash(echo hi:*)")
    }

    @Test("every edit result is valid JSON that Foundation reads the same way")
    func editedTextIsValid() throws {
        var current = try doc("{\n\t\"a\": [1],\n\t\"b\": {}\n}\n")
        current = try current.appending(.int(2), to: ["a"])
        current = try current.setting(["b", "c", "d"], to: .array([.null, true, "x\ny"]))
        current = try current.setting(["e"], to: "tab\there \"quoted\" \\ é")
        current = try current.removing(["a", 0])
        let parsed = try #require(try JSONSerialization.jsonObject(with: current.data) as? [String: Any])
        #expect((parsed["a"] as? [Int]) == [2])
        #expect(((parsed["b"] as? [String: Any])?["c"] as? [String: Any])?["d"] as? [AnyHashable] != nil)
        #expect(parsed["e"] as? String == "tab\there \"quoted\" \\ é")
        #expect(current.root["e"] == .string("tab\there \"quoted\" \\ é"))
    }

    @Test("edits on a wrong path fail without changing anything")
    func editErrors() throws {
        let d = try doc("{\"a\":[1],\"s\":\"x\"}")
        #expect(throws: OrderedJSONError.pathNotFound) { _ = try d.removing(["missing"]) }
        #expect(throws: OrderedJSONError.pathNotFound) { _ = try d.removing(["a", 5]) }
        #expect(throws: OrderedJSONError.pathNotFound) { _ = try d.removing([]) }
        #expect(throws: OrderedJSONError.pathNotFound) { _ = try d.setting(["a", 9], to: .null) }
        #expect(throws: OrderedJSONError.typeMismatch) { _ = try d.setting(["s", "deeper"], to: .null) }
        #expect(throws: OrderedJSONError.typeMismatch) { _ = try d.appending(.null, to: ["s"]) }
        #expect(throws: OrderedJSONError.typeMismatch) { _ = try d.setting(["a", "key"], to: .null) }
        #expect(throws: OrderedJSONError.invalidValue) { _ = try d.setting(["n"], to: .number("01")) }
        #expect(throws: OrderedJSONError.invalidValue) { _ = try d.setting(["n"], to: .number("")) }
        #expect(d.text == "{\"a\":[1],\"s\":\"x\"}")
    }

    @Test("with duplicate keys an edit targets the last one, as lookups do")
    func duplicateKeys() throws {
        #expect(try doc("{\"a\":1,\"a\":2}").setting(["a"], to: .int(9)).text == "{\"a\":1,\"a\":9}")
    }

    // MARK: Rejecting bad input

    @Test("invalid JSON is rejected with a position, never with file content", arguments: [
        ("", "unexpectedEnd"), ("{", "unexpectedEnd"), ("{\"a\":1,}", "expectedKey"), ("[1,]", "unexpectedCharacter"),
        ("{\"a\" 1}", "expectedColon"), ("{\"a\":1 \"b\":2}", "expectedCommaOrEnd"), ("[01]", "invalidNumber"),
        ("{\"a\":1} x", "trailingContent"), ("// c\n{}", "unexpectedCharacter"), ("{'a':1}", "expectedKey"),
        ("\"a\nb\"", "controlCharacterInString"), ("\"\\x\"", "invalidEscape"), ("\"\\u12g4\"", "invalidEscape"),
        ("[1 2]", "expectedCommaOrEnd"), ("\u{FEFF}{}", "unexpectedCharacter"), ("tru", "unexpectedCharacter"),
    ])
    func rejects(sample: (String, String)) {
        do {
            _ = try OrderedJSON(text: sample.0)
            Issue.record("accepted \(sample.0.debugDescription)")
        } catch let error as OrderedJSONError {
            guard case .syntax(let problem, let line, let column) = error else { Issue.record("wrong error \(error)"); return }
            #expect(problem.rawValue == sample.1, "for \(sample.0.debugDescription)")
            #expect(line >= 1 && column >= 1)
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test("an error never contains the text of the file")
    func errorsStayBlind() {
        let secret = "sk-this-must-never-appear"
        let broken = "{\"token\": \"\(secret)\" \"next\": 1}"
        do {
            _ = try OrderedJSON(text: broken)
            Issue.record("accepted")
        } catch {
            #expect(!String(describing: error).contains(secret))
            #expect(!String(reflecting: error).contains(secret))
            #expect(!error.localizedDescription.contains(secret))
        }
    }

    @Test("invalid UTF-8 is rejected")
    func invalidUTF8() {
        #expect(throws: OrderedJSONError.invalidUTF8) { _ = try OrderedJSON(data: Data([0x7B, 0xFF, 0x7D])) }
    }

    @Test("absurd nesting is rejected instead of overflowing the stack")
    func tooDeep() {
        let text = String(repeating: "[", count: OrderedJSON.maxDepth + 5) + String(repeating: "]", count: OrderedJSON.maxDepth + 5)
        #expect(throws: OrderedJSONError.tooDeep) { _ = try OrderedJSON(text: text) }
        let ok = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
        _ = try? OrderedJSON(text: ok)
    }

    // MARK: New documents

    @Test("pretty prints a new document in a chosen indent")
    func pretty() throws {
        let value = JSONValue.object([JSONMember("a", .array([.int(1), "x"])), JSONMember("o", .object([])), JSONMember("e", .array([]))])
        #expect(try OrderedJSON.pretty(value) == "{\n  \"a\": [\n    1,\n    \"x\"\n  ],\n  \"o\": {},\n  \"e\": []\n}\n")
        #expect(try OrderedJSON.pretty(.object([JSONMember("a", .int(1))]), indent: "\t", newline: "\r\n", trailingNewline: false) == "{\r\n\t\"a\": 1\r\n}")
    }
}
