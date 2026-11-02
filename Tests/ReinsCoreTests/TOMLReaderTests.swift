import Foundation
import Testing
@testable import ReinsCore

@Suite("TOMLReader")
struct TOMLReaderTests {
    @Test("scalars at the top level and in tables")
    func scalars() {
        let doc = TOMLReader.read("""
        approval_policy = "on-request"   # a comment
        count = 1_000
        ratio = 0.5
        hex = 0xFF
        enabled = true
        off = false
        literal = 'C:\\path\\no escapes'
        when = 1979-05-27 07:32:00

        [sandbox_workspace_write]
        network_access = false
        """)
        #expect(doc.value([], "approval_policy") == .string("on-request"))
        #expect(doc.value([], "count") == .integer(1000))
        #expect(doc.value([], "ratio") == .float(0.5))
        #expect(doc.value([], "hex") == .integer(255))
        #expect(doc.value([], "enabled") == .bool(true))
        #expect(doc.value([], "off") == .bool(false))
        #expect(doc.value([], "literal") == .string("C:\\path\\no escapes"))
        #expect(doc.value([], "when") == .raw("1979-05-27 07:32:00"))
        #expect(doc.value(["sandbox_workspace_write"], "network_access") == .bool(false))
        #expect(doc.skippedLines == 0)
    }

    @Test("quoted table names and quoted keys, as Codex writes project trust and permission profiles")
    func quotedNames() {
        let doc = TOMLReader.read("""
        [projects."/Users/someone/work/my app"]
        trust_level = "trusted"

        [projects.'/tmp/literal path']
        trust_level = "untrusted"

        [permissions.workspace.filesystem]
        ":project_roots" = "write"
        "/tmp/x.y" = "read"
        """)
        #expect(doc.value(["projects", "/Users/someone/work/my app"], "trust_level") == .string("trusted"))
        #expect(doc.value(["projects", "/tmp/literal path"], "trust_level") == .string("untrusted"))
        #expect(doc.tablePaths(under: ["projects"]) == [["projects", "/Users/someone/work/my app"], ["projects", "/tmp/literal path"]])
        let fs = doc.entries(in: ["permissions", "workspace", "filesystem"])
        #expect(fs.map(\.keyPath) == [[":project_roots"], ["/tmp/x.y"]])
        #expect(fs.map(\.value) == [.string("write"), .string("read")])
    }

    @Test("dotted keys split outside quotes")
    func dottedKeys() {
        let doc = TOMLReader.read("a.b.c = 1\n\"x.y\".z = 2\n")
        #expect(doc.entries.map(\.keyPath) == [["a", "b", "c"], ["x.y", "z"]])
        #expect(doc.value([], "a.b.c") == .integer(1))
    }

    @Test("arrays, nested arrays and arrays over several lines with comments")
    func arrays() {
        let doc = TOMLReader.read("""
        inline = ["a", "b", 3]
        nested = [[1, 2], ["x"]]
        writable_roots = [
          "/tmp/one",   # first
          "/tmp/two",
        ]
        empty = []
        after = "still read"
        """)
        #expect(doc.value([], "inline") == .array([.string("a"), .string("b"), .integer(3)]))
        #expect(doc.value([], "nested") == .array([.array([.integer(1), .integer(2)]), .array([.string("x")])]))
        #expect(doc.value([], "writable_roots")?.strings == ["/tmp/one", "/tmp/two"])
        #expect(doc.value([], "empty") == .array([]))
        #expect(doc.value([], "after") == .string("still read"))
    }

    @Test("inline tables, also nested and holding arrays")
    func inlineTables() {
        let doc = TOMLReader.read("""
        point = { x = 1, y = "two", list = [1, 2], inner = { k = true } }
        [projects]
        "/a/b" = { trust_level = "trusted" }
        """)
        let point = doc.value([], "point")
        #expect(point?["x"] == .integer(1))
        #expect(point?["y"] == .string("two"))
        #expect(point?["list"] == .array([.integer(1), .integer(2)]))
        #expect(point?["inner"]?["k"] == .bool(true))
        #expect(doc.value(["projects"], "/a/b")?["trust_level"] == .string("trusted"))
    }

    @Test("strings: escapes, triple-quoted basic and literal, line-ending backslash")
    func strings() {
        let doc = TOMLReader.read("""
        escaped = "tab\\there \\"q\\" \\u00e9 \\\\"
        basic = \"\"\"
        first line
        second "quoted" line\"\"\"
        literal = '''
        raw \\n stays
        '''
        folded = \"\"\"one \\
                   two\"\"\"
        same_line = \"\"\"inline\"\"\"
        after = 1
        """)
        #expect(doc.value([], "escaped") == .string("tab\there \"q\" é \\"))
        #expect(doc.value([], "basic") == .string("first line\nsecond \"quoted\" line"))
        #expect(doc.value([], "literal") == .string("raw \\n stays\n"))
        #expect(doc.value([], "folded") == .string("one two"))
        #expect(doc.value([], "same_line") == .string("inline"))
        #expect(doc.value([], "after") == .integer(1))
    }

    @Test("an agent file's developer_instructions block reads whole")
    func agentFile() {
        let doc = TOMLReader.read("""
        name = "reviewer"
        description = "Reviews code"
        developer_instructions = \"\"\"
        Be careful.
        # not a comment, inside the string
        [not_a_table]
        \"\"\"
        """)
        #expect(doc.value([], "name") == .string("reviewer"))
        #expect(doc.value([], "developer_instructions")?.stringValue == "Be careful.\n# not a comment, inside the string\n[not_a_table]\n")
        #expect(doc.tables.isEmpty)
    }

    @Test("a hash inside a string is not a comment")
    func hashInString() {
        let doc = TOMLReader.read("url = \"https://example.com/#frag\" # real comment\nsingle = 'a # b'\n")
        #expect(doc.value([], "url") == .string("https://example.com/#frag"))
        #expect(doc.value([], "single") == .string("a # b"))
    }

    @Test("array tables are marked and keep their path")
    func arrayTables() {
        let doc = TOMLReader.read("[[servers]]\nname = \"a\"\n[[servers]]\nname = \"b\"\n")
        #expect(doc.tables == [TOMLTableHeader(path: ["servers"], isArray: true), TOMLTableHeader(path: ["servers"], isArray: true)])
        #expect(doc.entries.map(\.inArrayTable) == [true, true])
        #expect(doc.entries(in: ["servers"]).count == 2)
    }

    @Test("the last assignment wins and CRLF files read the same")
    func lastWinsAndCRLF() {
        let doc = TOMLReader.read("a = 1\r\na = 2\r\n[t]\r\nb = \"x\"\r\nlist = [\r\n  1,\r\n  2\r\n]\r\n")
        #expect(doc.value([], "a") == .integer(2))
        #expect(doc.value(["t"], "b") == .string("x"))
        #expect(doc.value(["t"], "list") == .array([.integer(1), .integer(2)]))
    }

    @Test("a broken line is skipped and counted; the rest still reads")
    func tolerant() {
        let doc = TOMLReader.read("good = 1\nthis is not toml\nbad = \"unterminated\nalso_good = 2\n[ok]\nx = 3\n")
        #expect(doc.value([], "good") == .integer(1))
        #expect(doc.value([], "also_good") == .integer(2))
        #expect(doc.value(["ok"], "x") == .integer(3))
        #expect(doc.skippedLines >= 2)
        #expect(doc.entries.first(where: { $0.key == "bad" })?.value == nil)
        #expect(doc.entries.contains(where: { $0.key == "bad" }))
    }

    @Test("entries carry their line numbers")
    func lines() {
        let doc = TOMLReader.read("# header comment\n\na = 1\n[t]\nb = 2\n")
        #expect(doc.entries.map(\.line) == [3, 5])
    }

    @Test("reads the Codex config of the synthetic fixture")
    func fixture() throws {
        let doc = try #require(TOMLReader.read(contentsOf: Fixtures.url("home/.codex/config.toml")))
        #expect(doc.value([], "approval_policy") == .string("on-request"))
        #expect(doc.value([], "sandbox_mode") == .string("workspace-write"))
        #expect(doc.value(["sandbox_workspace_write"], "network_access") == .bool(false))
        #expect(doc.tablePaths(under: ["projects"]).count == 3)
        #expect(doc.skippedLines == 0)
        #expect(TOMLReader.read(contentsOf: Fixtures.url("home/.codex/missing.toml")) == nil)
    }
}
