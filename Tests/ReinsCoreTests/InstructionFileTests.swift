import Foundation
import Testing
@testable import ReinsCore

/// Agents plan A6 (AG2): instruction files per agent and scope, their `@path` imports, and one journal entry for a save
/// that edits a file and the file it imports.
@Suite("InstructionFile")
struct InstructionFileTests {
    @Test("each agent and scope has its file; Codex has no Local file")
    func locations() throws {
        let home = try TempHome()
        let roots = try home.roots
        #expect(InstructionFile.url(cli: .claude, scope: .global, roots: roots)?.path == home.claude.appendingPathComponent("CLAUDE.md").path)
        #expect(InstructionFile.url(cli: .claude, scope: .local("/w/app"), roots: roots)?.path == "/w/app/CLAUDE.local.md")
        #expect(InstructionFile.url(cli: .codex, scope: .global, roots: roots)?.path == home.codex.appendingPathComponent("AGENTS.md").path)
        #expect(InstructionFile.url(cli: .codex, scope: .project("/w/app"), roots: roots)?.path == "/w/app/AGENTS.md")
        #expect(InstructionFile.url(cli: .codex, scope: .local("/w/app"), roots: roots) == nil)
    }

    @Test("a line that is only @path is an import, resolved against the file and ~, never inside a code block")
    func imports() throws {
        let home = try TempHome()
        let main = try home.write(".claude/CLAUDE.md", """
        # Rules
        @rules/style.md
        Read @this inline, which is prose.
        @~/notes/team.md
        ```
        @not/an/import.md
        ```
        """)
        try home.write(".claude/rules/style.md", "Use tabs.\n")
        let file = InstructionFile.read(main, home: home.root.path)
        #expect(file.exists)
        #expect(file.imports.map(\.raw) == ["rules/style.md", "~/notes/team.md"])
        #expect(file.imports.map(\.line) == [2, 4])
        #expect(file.imports[0].url.path == home.claude.appendingPathComponent("rules/style.md").path && file.imports[0].exists)
        #expect(file.imports[1].url.path == home.url("notes/team.md").path && !file.imports[1].exists)
        #expect(!InstructionFile.read(home.url("missing.md"), home: home.root.path).exists)
    }

    @Test("one save edits a file and its import in one entry, and Undo restores both")
    func saveAcrossFiles() throws {
        let home = try TempHome()
        let roots = try home.roots
        let main = try home.write(".claude/CLAUDE.md", "# Rules\n@rules/style.md\n")
        let style = try home.write(".claude/rules/style.md", "Use tabs.\n")
        let entry = try #require(try AgentSave.save(roots, label: "Rules", changes: [
            InstructionFile.fileChange(main, text: "# Rules\n@rules/style.md\nKeep commits small.\n"),
            InstructionFile.fileChange(style, text: "Use spaces.\n"),
        ]))
        #expect(entry.ops.count == 2)
        #expect(try String(contentsOf: style, encoding: .utf8) == "Use spaces.\n")
        _ = try Journal.undo(roots, id: entry.id)
        #expect(try String(contentsOf: main, encoding: .utf8) == "# Rules\n@rules/style.md\n")
        #expect(try String(contentsOf: style, encoding: .utf8) == "Use tabs.\n")
        // Saving the same text writes nothing.
        #expect(try AgentSave.save(roots, label: "Rules", changes: [InstructionFile.fileChange(style, text: "Use tabs.\n")]) == nil)
    }

    @Test("a new instruction file is created, and Undo moves it away")
    func create() throws {
        let home = try TempHome()
        let roots = try home.roots
        let url = try #require(InstructionFile.url(cli: .codex, scope: .global, roots: roots))
        let entry = try #require(try AgentSave.save(roots, label: "Rules", changes: [InstructionFile.fileChange(url, text: "Be brief.\n")]))
        #expect(try String(contentsOf: url, encoding: .utf8) == "Be brief.\n")
        _ = try Journal.undo(roots, id: entry.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
