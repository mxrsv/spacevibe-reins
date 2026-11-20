import Foundation
import Testing

/// Per-CLI facts come from the core's `clis.list` through `CLICatalog`, and each CLI's look from `CLIRegistry` (MC-R1, MC27):
/// code outside the look table asks `cli.identity`, `cli.label` or the catalog's lists, and never names a CLI (`.claude`,
/// `CLIID.codex`, `cells[.codex]`, `"codex-tool-silent"`). A `switch` over a CLI
/// or a `== .codex` is caught by the same patterns, since each names a case; a string that starts with a CLI's id (the id
/// itself or a reason code the core prefixes with it) is caught by the string pattern.
///
/// Reads source text, like `StyleBoundaryTests`. Exempt: the look table, `Core/` (the wire DTOs, which carry the open `CLIID`
/// and name no CLI), `Gallery/` and the `*Shots.swift` / `*Synthetic.swift` files, which draw fixed synthetic CLIs on purpose. `allowed` is a ratchet: each entry is a two-CLI flow that only the owner's multi-CLI design can
/// open, and a count that differs from its entry in either direction fails.
@Suite("CLI branch policy: only the registry names a CLI", .fixtureCLIs)
struct CLIBranchPolicyTests {
    static var appSources: URL { StyleBoundaryTests.appSources }

    static let registryFile = "Components/CLIRegistry.swift"
    static let exemptFolders = ["Core/", "Gallery/"]
    static let exemptSuffixes = ["Shots.swift", "Synthetic.swift"]

    static let forbidden: [(name: String, pattern: String)] = [
        // A bare case: `.claude`, `== .codex`, `case .gemini:`. Not a member of a value (`cells.claude`, `x?.codex`), not a path
        // inside a string (`~/.claude`).
        ("CLI case", #"(?<![\w)\]?!/"])\.(claude|codex|gemini)\b"#),
        // A qualified id, or a loop over every id instead of the catalog's list.
        ("qualified CLI", #"\b(CLIID|CLIRegistry)\.(claude|codex|gemini|allCases)\b"#),
        // A string that starts with a CLI's id: the id itself or a code the core prefixes with it (`"claude-prompt-vs-busy"`).
        // Not a path (`"~/.claude"`).
        ("CLI string", #""(claude|codex|gemini)\b"#),
    ]

    /// Files that still name a CLI, with how many times and why. Lower an entry when a site moves to the registry; never raise
    /// one without the owner's multi-CLI design behind it.
    static let allowed: [String: Int] = [
        // SpaceVibe copies Claude Code hooks into Codex only, and writes none yet (`LoadoutRows.codexTakesHooks`, go-core
        // G-fix.16): the "Missing in Codex" card, `Copy M to Codex` and their checks are a Claude-to-Codex flow.
        "Agents/LoadoutRows.swift": 2, // also `home(roots:)`, which reads `~` off Claude Code's default folder.
        "Hooks/HooksModel.swift": 3,
        "Hooks/HooksQuery.swift": 6,
        "Hooks/HooksTab.swift": 1,
        // The status line capture is Claude Code's, so its palette actions answer to the keyword "claude".
        "Limits/LimitsCanvas.swift": 1,
        // The Rules page edits Claude Code's permission rules and reads one fact from Codex's `config.toml` beside them.
        "Rules/RulesCanvas.swift": 7,
        "Rules/RulesModel.swift": 1,
    ]

    /// Matches in one file. Whole-line comments are skipped; a trailing comment is skipped when the line has no string literal.
    static func violations(in source: String) -> Int {
        let expressions = forbidden.map { try! NSRegularExpression(pattern: $0.pattern) }
        var count = 0
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { continue }
            var code = line
            if !line.contains("\""), let comment = line.range(of: "//") { code = String(line[..<comment.lowerBound]) }
            let range = NSRange(code.startIndex..., in: code)
            for expression in expressions { count += expression.numberOfMatches(in: code, range: range) }
        }
        return count
    }

    static func isChecked(_ relative: String) -> Bool {
        relative.hasSuffix(".swift") && relative != registryFile
            && !exemptFolders.contains { relative.hasPrefix($0) } && !exemptSuffixes.contains { relative.hasSuffix($0) }
    }

    static func measured() throws -> [String: Int] {
        var result: [String: Int] = [:]
        guard let walker = FileManager.default.enumerator(atPath: appSources.path) else { return result }
        for case let relative as String in walker where isChecked(relative) {
            let source = try String(contentsOf: appSources.appendingPathComponent(relative), encoding: .utf8)
            let count = violations(in: source)
            if count > 0 { result[relative] = count }
        }
        return result
    }

    @Test("no file outside the registry gains a CLI name, and every removed one is written down")
    func ratchet() throws {
        let registry = try String(contentsOf: Self.appSources.appendingPathComponent(Self.registryFile), encoding: .utf8)
        #expect(Self.violations(in: registry) > 0, "the registry names no CLI: is \(Self.registryFile) still the registry?")
        let now = try Self.measured()
        var problems: [String] = []
        for file in Set(now.keys).union(Self.allowed.keys).sorted() {
            let found = now[file] ?? 0, allowed = Self.allowed[file] ?? 0
            if found > allowed { problems.append("\(file): names a CLI \(found) times, \(allowed) allowed. Ask `cli.identity` or `CLIRegistry`.") }
            if found < allowed { problems.append("\(file): names a CLI \(found) times, the list says \(allowed). Lower its entry.") }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("the patterns catch a CLI picked by name and skip values, paths and comments")
    func patterns() {
        #expect(Self.violations(in: "if cli == .claude { return }") == 1)
        #expect(Self.violations(in: "case .codex: Palette.codex") == 1)
        #expect(Self.violations(in: "let order = [.claude, .codex]") == 2)
        #expect(Self.violations(in: "CLIMark(CLIID.claude, size: .glyph)") == 1)
        #expect(Self.violations(in: "for cli in CLIID.allCases {") == 1)
        #expect(Self.violations(in: "ForEach(CLIID.allCases, id: \\.self)") == 1)
        #expect(Self.violations(in: "let tone = CLIRegistry.codex.tone") == 1)
        #expect(Self.violations(in: "for cli in CLICatalog.current.inventoryCLIs {") == 0)
        #expect(Self.violations(in: "let name = cli.identity.label") == 0)
        #expect(Self.violations(in: "row.cells.claude = cell") == 0)
        #expect(Self.violations(in: "row.cells[.claude] = cell") == 1)
        #expect(Self.violations(in: "let old = reading?.codex") == 0)
        #expect(Self.violations(in: #"static let file = "~/.claude/settings.json""#) == 0)
        #expect(Self.violations(in: #"filter { $0.code == "claude-prompt-vs-busy" || $0.code == "codex-tool-silent" }"#) == 2)
        #expect(Self.violations(in: #"keywords: ["claude", "limits"]"#) == 1)
        #expect(Self.violations(in: #"let page = "limits", tab = "claudeless""#) == 0)
        #expect(Self.violations(in: "// a comment about .claude") == 0)
        #expect(Self.violations(in: "x = y // falls back to .codex") == 0)
    }

    @Test("the allowlist names only files that exist and are checked")
    func allowlistIsCurrent() {
        for file in Self.allowed.keys.sorted() {
            #expect(Self.isChecked(file), "\(file) is exempt, so it needs no entry")
            #expect(FileManager.default.fileExists(atPath: Self.appSources.appendingPathComponent(file).path), "\(file) does not exist")
        }
    }
}
