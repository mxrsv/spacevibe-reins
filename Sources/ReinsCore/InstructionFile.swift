import Foundation

/// A line `@path` in an instruction file: the file it imports, resolved against the importing file's folder or `~`.
public struct InstructionImport: Equatable, Sendable, Identifiable {
    /// As written, without the `@`.
    public let raw: String
    public let url: URL
    /// The line it sits on, from 1.
    public let line: Int
    public let exists: Bool

    public var id: String { "\(line):\(raw)" }
}

/// An instruction file of one agent (plan A6): Claude Code's `CLAUDE.md` and `CLAUDE.local.md`, Codex's `AGENTS.md`, or
/// a file one of them imports.
public struct InstructionFile: Equatable, Sendable {
    public let file: URL
    public let exists: Bool
    public let text: String
    public let imports: [InstructionImport]

    /// The instruction file of an agent at a scope (spec, Interface: Scope). Codex has no Local file.
    public static func url(cli: InventoryCLI, scope: RuleScope, roots: Roots) -> URL? {
        switch (cli, scope) {
        case (.claude, .global): return roots.claude.root.appendingPathComponent("CLAUDE.md")
        case (.claude, .project(let dir)): return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("CLAUDE.md")
        case (.claude, .local(let dir)): return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("CLAUDE.local.md")
        case (.codex, .global): return roots.codex.root.appendingPathComponent("AGENTS.md")
        case (.codex, .project(let dir)): return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("AGENTS.md")
        case (.codex, .local): return nil
        }
    }

    /// The file and its imports. A missing file reads as empty text.
    public static func read(_ file: URL, home: String) -> InstructionFile {
        let text = InventoryFileIO.readText(file)
        return InstructionFile(file: file, exists: text != nil, text: text ?? "", imports: imports(in: text ?? "", relativeTo: file, home: home))
    }

    /// Every line that is only `@path`, outside fenced code blocks.
    public static func imports(in text: String, relativeTo file: URL, home: String) -> [InstructionImport] {
        var out: [InstructionImport] = []
        var fenced = false
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { fenced.toggle(); continue }
            guard !fenced, line.hasPrefix("@"), line.count > 1, !line.contains(" ") else { continue }
            let path = String(line.dropFirst())
            let url = resolve(path, relativeTo: file, home: home)
            out.append(InstructionImport(raw: path, url: url, line: index + 1, exists: InventoryFileIO.exists(url.path)))
        }
        return out
    }

    static func resolve(_ path: String, relativeTo file: URL, home: String) -> URL {
        if path == "~" { return URL(fileURLWithPath: home) }
        if path.hasPrefix("~/") { return URL(fileURLWithPath: home).appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return file.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
    }

    /// The save of new text for a file (created when missing). Line endings and everything else are the editor's.
    public static func fileChange(_ file: URL, text: String) -> AgentFileChange {
        AgentFileChange(file: file) { current in current == text ? nil : text }
    }
}
