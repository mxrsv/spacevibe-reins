import Foundation
import Testing

/// Every control that takes a click shows the pointing hand, and the block that draws it says so (V5-R8: a screen composes
/// blocks and sets no cursor of its own). This reads source text, as `StyleBoundaryTests` does, because the cursor cannot be
/// seen in a headless shot. Two rules:
///
/// 1. In `Components/`, each file applies `pointerCursor(` (or `pointerStyle(`) at least once per click-taking construct it
///    declares: a `ButtonStyle`, a `.buttonStyle(.plain)` button, a `Menu`, a click on a row (`RowActivation`) or a menu line.
/// 2. In a screen folder, a button uses `.spaceVibe(...)` or `ActionButtonStyle(...)`, which carry the cursor; a bare
///    `.buttonStyle(.plain)`, `.onTapGesture` or `Menu` is a hand-made control and fails unless `allowed` lists it.
@Suite("Pointer cursor: clickable blocks set it, screens compose them")
struct PointerCursorPolicyTests {
    /// A construct in a block that takes a click and so needs the cursor.
    static let blockConstructs = [
        #"\bButtonStyle\s*\{"#,
        #"\.buttonStyle\(\.plain\)"#,
        #"\bMenu\s*\{"#,
        #"\.onTapGesture\b"#,
    ]

    /// What carries the cursor.
    static let cursorCalls = #"\.pointer(Cursor|Style)\("#

    /// `.onTapGesture` calls that need no `pointerCursor(` of their own: a click on the dimmed layer or outside an open overlay
    /// takes the arrow, and a tap on a `MenuLine` rides the cursor `MenuLine` sets. Counted per file; a count that differs in
    /// either direction fails.
    static let notControls: [String: Int] = [
        "Components/ConfirmationDialog.swift": 2, // the scrim around the dialog
        "Components/OverlayHost.swift": 1,        // a click outside an open overlay
        "Components/PaletteParts.swift": 1,       // `Scrim`
        "Components/ToolbarMenu.swift": 3,        // taps on a `MenuLine`
    ]

    /// Screen files that still hold a hand-made control. Both are old-screen code that the cut-over (X1) deletes.
    static let allowed: [String: Int] = [
        "Limits/LimitsSidebarBlock.swift": 1, // old sidebar tile; the v5 sidebar uses `SidebarBlocks`
        "Rules/RulesList.swift": 1,           // old Rules list: a `Menu` whose label takes `.spaceVibe(.icon)`
    ]

    /// Constructs declared in a screen folder that a screen may not hand-make.
    static let screenConstructs = [
        #"\.buttonStyle\(\.plain\)"#,
        #"\bMenu\s*\{"#,
        #"\.onTapGesture\b"#,
    ]

    static func count(_ patterns: [String], in source: String) -> Int {
        let expressions = patterns.map { try! NSRegularExpression(pattern: $0) }
        var total = 0
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            for expression in expressions { total += expression.numberOfMatches(in: line, range: range) }
        }
        return total
    }

    static func sources(in folder: String) throws -> [(file: String, text: String)] {
        let directory = StyleBoundaryTests.appSources.appendingPathComponent(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return try names.filter { $0.hasSuffix(".swift") }.sorted().map {
            ("\(folder)/\($0)", try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8))
        }
    }

    @Test("every click-taking construct in a block sets the cursor")
    func blocksSetTheCursor() throws {
        let files = try Self.sources(in: "Components")
        #expect(!files.isEmpty, "found no component sources")
        var problems: [String] = []
        for (file, text) in files {
            let needed = Self.count(Self.blockConstructs, in: text) - (Self.notControls[file] ?? 0)
            let set = Self.count([Self.cursorCalls], in: text)
            if needed > set { problems.append("\(file): \(needed) click-taking constructs, \(set) pointer calls. Add `.pointerCursor()`.") }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("a tap without a cursor of its own is listed, and the list is exact")
    func notControlsAreExact() throws {
        for (file, expected) in Self.notControls {
            let folder = String(file.prefix { $0 != "/" })
            let name = String(file.drop { $0 != "/" }.dropFirst())
            let text = try #require(Self.sources(in: folder).first { $0.file == "\(folder)/\(name)" }?.text, "\(file) is gone: drop its entry")
            #expect(Self.count([#"\.onTapGesture\b"#], in: text) == expected, "\(file): the number of taps changed; is the new one a control?")
        }
    }

    @Test("a screen composes buttons that carry the cursor and hand-makes none")
    func screensComposeBlocks() throws {
        var problems: [String] = []
        for folder in StyleBoundaryTests.screenFolders {
            for (file, text) in try Self.sources(in: folder) {
                let found = Self.count(Self.screenConstructs, in: text)
                let allowed = Self.allowed[file] ?? 0
                if found > allowed { problems.append("\(file): \(found) hand-made controls, \(allowed) allowed. Use a block that sets the cursor.") }
                if found < allowed { problems.append("\(file): \(found) hand-made controls, the list says \(allowed). Lower its entry.") }
                // A button style a screen names must be one that sets the cursor.
                let styled = text.components(separatedBy: "\n").filter {
                    $0.contains(".buttonStyle(") && !$0.contains(".buttonStyle(.spaceVibe(") && !$0.contains(".buttonStyle(ActionButtonStyle(")
                        && !$0.contains(".buttonStyle(.plain)") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                }
                if !styled.isEmpty { problems.append("\(file): a button style that sets no cursor: \(styled)") }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("the patterns catch a block or a screen that forgets")
    func patterns() {
        #expect(Self.count(Self.blockConstructs, in: "private struct X: ButtonStyle {") == 1)
        #expect(Self.count(Self.blockConstructs, in: "        .buttonStyle(.plain)") == 1)
        #expect(Self.count(Self.blockConstructs, in: "x.onTapGesture { go() }") == 1)
        #expect(Self.count(Self.blockConstructs, in: "// .buttonStyle(.plain) in a comment") == 0)
        #expect(Self.count(Self.blockConstructs, in: "x.buttonStyle(.spaceVibe(.normal))") == 0)
        #expect(Self.count([Self.cursorCalls], in: "x.pointerCursor()") == 1)
        #expect(Self.count([Self.cursorCalls], in: "x.pointerStyle(.link)") == 1)
            }
}
