import Foundation
import Testing
@testable import ReinsCore

/// Agents plan A2 (AG5): edits to `config.toml` keep every untouched line byte-identical and read back with `TOMLReader`.
@Suite("TOMLEdit")
struct TOMLEditTests {
    static let config = """
    # Codex settings, by hand
    model = "gpt-5-codex"   # the default
    approval_policy = "on-request"
    sandbox_workspace_write.network_access = false

    [sandbox_workspace_write]
    writable_roots = [
      "/w/cache", # build output
      "/w/tmp",
    ]

    [projects."/w/my app"]
    trust_level = "untrusted"

    [mcp_servers.docs]
    command = "docs-mcp"
    env = { DOCS_HOST = "docs.internal", RETRIES = 3 }

    [permissions.review]
    extends = ":read-only"

    [permissions.review.filesystem]
    ":workspace_roots" = "read"

    [features]
    network_proxy = true

    """

    func edited(_ change: (TOMLEdit) throws -> TOMLEdit) throws -> String {
        try change(TOMLEdit(Self.config)).text
    }

    @Test("a value is replaced where it is, with its comment and every other byte kept")
    func replaceInPlace() throws {
        let out = try edited { try $0.setting(["model"], to: .string("o4-mini")) }
        #expect(out == Self.config.replacingOccurrences(of: #"model = "gpt-5-codex"   # the default"#, with: #"model = "o4-mini"   # the default"#))
        #expect(TOMLReader.read(out).value([], "model") == .string("o4-mini"))
    }

    @Test("a dotted key and a quoted table name are found by their full path")
    func dottedAndQuoted() throws {
        let dotted = try edited { try $0.setting(["sandbox_workspace_write", "network_access"], to: .bool(true)) }
        #expect(dotted == Self.config.replacingOccurrences(of: "network_access = false", with: "network_access = true"))
        let quoted = try edited { try $0.setting(["projects", "/w/my app", "trust_level"], to: .string("trusted")) }
        #expect(quoted == Self.config.replacingOccurrences(of: #"trust_level = "untrusted""#, with: #"trust_level = "trusted""#))
        #expect(TOMLReader.read(quoted).value(["projects", "/w/my app"], "trust_level") == .string("trusted"))
    }

    @Test("a multi-line array is replaced as one value, and the lines around it stay")
    func multiLineArray() throws {
        let out = try edited { try $0.setting(["sandbox_workspace_write", "writable_roots"], to: .strings(["/w/cache"])) }
        let old = """
        writable_roots = [
          "/w/cache", # build output
          "/w/tmp",
        ]
        """
        #expect(out == Self.config.replacingOccurrences(of: old, with: #"writable_roots = ["/w/cache"]"#))
        #expect(TOMLEdit(out).value(["sandbox_workspace_write", "writable_roots"]) == .array([.string("/w/cache")]))
    }

    @Test("a key inside an inline table rewrites that inline table only")
    func inlineTable() throws {
        let out = try edited { try $0.setting(["mcp_servers", "docs", "env", "RETRIES"], to: .integer(5)) }
        #expect(out == Self.config.replacingOccurrences(of: "env = { DOCS_HOST = \"docs.internal\", RETRIES = 3 }", with: "env = { DOCS_HOST = \"docs.internal\", RETRIES = 5 }"))
        let removed = try edited { try $0.removing(["mcp_servers", "docs", "env", "RETRIES"]) }
        #expect(removed == Self.config.replacingOccurrences(of: ", RETRIES = 3 }", with: " }"))
    }

    @Test("a new key goes after the last line of its table, and a new table at the end")
    func appends() throws {
        let key = try edited { try $0.setting(["mcp_servers", "docs", "url"], to: .string("https://docs.example.test")) }
        #expect(key == Self.config.replacingOccurrences(of: "env = { DOCS_HOST = \"docs.internal\", RETRIES = 3 }\n", with: "env = { DOCS_HOST = \"docs.internal\", RETRIES = 3 }\nurl = \"https://docs.example.test\"\n"))
        let top = try edited { try $0.setting(["model_reasoning_effort"], to: .string("high")) }
        #expect(top == Self.config.replacingOccurrences(of: "network_access = false\n", with: "network_access = false\nmodel_reasoning_effort = \"high\"\n"))
        let table = try edited { try $0.setting(["projects", "/w/other", "trust_level"], to: .string("trusted")) }
        #expect(table == Self.config + "\n[projects.\"/w/other\"]\ntrust_level = \"trusted\"\n")
        #expect(TOMLReader.read(table).value(["projects", "/w/other"], "trust_level") == .string("trusted"))
    }

    @Test("removing a key drops its line; removing a table drops it and its sub-tables")
    func removals() throws {
        let key = try edited { try $0.removing(["approval_policy"]) }
        #expect(key == Self.config.replacingOccurrences(of: "approval_policy = \"on-request\"\n", with: ""))
        #expect(try TOMLEdit(Self.config).removing(["nothing"]).text == Self.config)
        let table = try edited { try $0.removingTable(["permissions", "review"]) }
        let gone = """
        [permissions.review]
        extends = ":read-only"

        [permissions.review.filesystem]
        ":workspace_roots" = "read"


        """
        #expect(table == Self.config.replacingOccurrences(of: gone, with: ""))
        #expect(TOMLReader.read(table).tablePaths(under: ["permissions"]).isEmpty)
    }

    @Test("strings are escaped, and keys that are not bare are quoted")
    func rendering() throws {
        #expect(TOMLWrite.string("a \"b\"\\\n").rendered == #""a \"b\"\\\n""#)
        #expect(TOMLEdit.keyText(["projects", "/w/a b", "trust_level"]) == #"projects."/w/a b".trust_level"#)
        #expect(TOMLWrite.table([("A", .string("x")), ("n", .integer(1))]).rendered == #"{ A = "x", n = 1 }"#)
        let out = try edited { try $0.setting(["mcp_servers", "docs", "args"], to: .strings(["--root", "/w/a \"quoted\""])) }
        #expect(TOMLEdit(out).value(["mcp_servers", "docs", "args"]) == .array([.string("--root"), .string("/w/a \"quoted\"")]))
    }

    @Test("the layout finds headers, statements, values and the leaves of inline tables and arrays")
    func layout() {
        let layout = TOMLLayout(text: Self.config)
        #expect(layout.headers.map(\.path).contains(["projects", "/w/my app"]))
        let roots = layout.statement(["sandbox_workspace_write", "writable_roots"])
        #expect(roots != nil)
        if let roots {
            #expect(layout.leaves(in: roots.value).map(\.path) == [["[0]"], ["[1]"]])
        }
        let env = layout.statement(["mcp_servers", "docs", "env"])
        #expect(env.map { layout.leaves(in: $0.value).map(\.path) } == [["DOCS_HOST"], ["RETRIES"]])
        #expect(layout.statement(["sandbox_workspace_write", "network_access"])?.table == [])
    }
}
