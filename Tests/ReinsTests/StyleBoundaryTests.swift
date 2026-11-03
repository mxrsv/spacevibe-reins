import Foundation
import Testing

/// Screens compose base components; they never style themselves (spec `docs/specs/2026-11-03-reins-design-language.md`,
/// "Component base", DL3). A restyle then means editing `Sources/Reins/Tokens` or `Sources/Reins/Components` only.
///
/// This reads source text: every forbidden pattern is lexical. `allowed` was a ratchet while the screens moved onto components;
/// it is now empty, so any literal in a screen folder fails. A count that differs from an entry in either direction fails too.
@Suite("Style boundary: screens compose components")
struct StyleBoundaryTests {
    /// Folders that are screens. `Gallery/` lays out specimens and is exempt; `TokenUsage/` joins when it exists.
    static let screenFolders = ["Loadout", "Rules", "Activity", "Shell", "TokenUsage", "Limits"]

    /// What only `Tokens/` and `Components/` may contain.
    static let forbidden: [(name: String, pattern: String)] = [
        ("system font", #"Font\.system|\.system\(size"#),
        ("raw font", #"\.font\("#),
        ("palette colour", #"Palette\."#),
        ("colour literal", #"\bColor\("#),
        ("radius literal", #"cornerRadius:\s*[0-9]"#),
        // Zero is structure, not a design value, so `spacing: 0` and `.padding(.top, 0)` pass.
        ("padding literal", #"\.padding\([^)]*?\b[1-9][0-9]*(\.[0-9]+)?\s*\)"#),
        ("spacing literal", #"spacing:\s*[1-9]"#),
        ("frame literal", #"\.frame\([^)]*?\b(width|height|minWidth|minHeight|maxWidth|maxHeight):\s*[1-9]"#),
    ]

    /// Empty since 2026-11-03 (design-language plan T6): no screen file may hold a style literal. A file that truly needs an
    /// exception gets an entry here with a comment saying why, and a reviewer has to agree.
    static let allowed: [String: Int] = [:]

    static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ReinsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // checkout
            .appendingPathComponent("Sources/Reins")
    }

    /// Forbidden matches in one file. Whole-line comments are skipped; a trailing comment is skipped when the line has no
    /// string literal (so `//` inside a string never hides code).
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

    static func measured() throws -> [String: Int] {
        var result: [String: Int] = [:]
        let fileManager = FileManager.default
        for folder in screenFolders {
            let directory = appSources.appendingPathComponent(folder)
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasSuffix(".swift") {
                let source = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
                let count = violations(in: source)
                if count > 0 { result["\(folder)/\(name)"] = count }
            }
        }
        return result
    }

    @Test("no screen file gains a style literal, and every removed one is written down")
    func ratchet() throws {
        let now = try Self.measured()
        #expect(!now.isEmpty || Self.allowed.isEmpty, "found no screen sources under \(Self.appSources.path)")
        var problems: [String] = []
        for file in Set(now.keys).union(Self.allowed.keys).sorted() {
            let found = now[file] ?? 0, allowed = Self.allowed[file] ?? 0
            if found > allowed { problems.append("\(file): \(found) style literals, \(allowed) allowed. Use a component or token.") }
            if found < allowed { problems.append("\(file): \(found) style literals, the list says \(allowed). Lower its entry.") }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("the patterns catch what they name and skip comments")
    func patterns() {
        #expect(Self.violations(in: #"Text("a").font(.system(size: 13))"#) == 2)
        #expect(Self.violations(in: "x.foregroundStyle(Palette.text)") == 1)
        #expect(Self.violations(in: "x.padding(.horizontal, 10)") == 1)
        #expect(Self.violations(in: "x.padding(.horizontal, Metrics.pagePadding)") == 0)
        #expect(Self.violations(in: "HStack(spacing: 8) {") == 1)
        #expect(Self.violations(in: "HStack(spacing: Space.s8) {") == 0)
        #expect(Self.violations(in: "VStack(spacing: 0) {") == 0)
        #expect(Self.violations(in: "x.frame(width: 58, alignment: .trailing)") == 1)
        #expect(Self.violations(in: "x.frame(maxWidth: .infinity)") == 0)
        #expect(Self.violations(in: "RoundedRectangle(cornerRadius: 6)") == 1)
        #expect(Self.violations(in: "// .font(ReinsFont.body) in a comment") == 0)
        #expect(Self.violations(in: "x.reinsText(.caption, tone: .tertiary)") == 0)
    }
}
