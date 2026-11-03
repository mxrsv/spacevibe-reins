import Foundation
import ReinsCore

/// Which of a project's two settings files a scope means.
enum RulesFileKind: Hashable {
    case shared, local
}

/// What the scope picker has chosen: Global, or a discovered project and one of its two files. Each choice is exactly
/// one settings file, so a grid, a list and a write always talk about the same file.
struct RulesSelection: Equatable, Hashable {
    var dir: String?
    var file = RulesFileKind.shared

    static let global = RulesSelection(dir: nil)

    var scope: RuleScope {
        guard let dir else { return .global }
        return file == .shared ? .project(dir) : .local(dir)
    }
}

/// A project Reins discovered, with a name that tells it apart from the others.
struct RulesProject: Equatable, Hashable {
    let dir: String
    let name: String
}

/// Pure helpers for the scope list and for keeping paths out of the UI. Covered by `RulesScopesTests`.
enum RulesScopes {
    /// The folder name; two projects with the same folder name also show their parent folder.
    static func projects(from dirs: [String]) -> [RulesProject] {
        dirs.map { dir in
            let name = (dir as NSString).lastPathComponent
            let same = dirs.filter { ($0 as NSString).lastPathComponent == name }.count
            guard same > 1 else { return RulesProject(dir: dir, name: name) }
            let parent = ((dir as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return RulesProject(dir: dir, name: "\(parent)/\(name)")
        }
    }

    /// "Global", "spacevibe-api" or "spacevibe-api (local)".
    static func title(for selection: RulesSelection, projects: [RulesProject]) -> String {
        guard let dir = selection.dir else { return "Global" }
        let name = projects.first { $0.dir == dir }?.name ?? (dir as NSString).lastPathComponent
        return selection.file == .local ? "\(name) (local)" : "\(name) (shared)"
    }

    /// The core's messages name the absolute settings file; the screen only shows the scope's short label.
    static func scrub(_ text: String, path: String, label: String) -> String {
        var out = text.replacingOccurrences(of: path, with: label)
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path { out = out.replacingOccurrences(of: resolved, with: label) }
        return out
    }

    /// Runs `work` and rethrows a `ReinsError` with the settings file's absolute path replaced by its label (status kept).
    /// Every read and write of this screen goes through it, because the engine's 409 messages name the file.
    static func scrubbed<T>(store: RulesStore, scope: RuleScope, _ work: () throws -> T) throws -> T {
        do { return try work() } catch let error as ReinsError {
            guard let path = try? store.file(for: scope).path else { throw error }
            throw ReinsError(scrub(error.message, path: path, label: scope.fileLabel), status: error.status)
        }
    }

    /// The instant check before a write: the engine stays the authority (it also refuses a duplicate with a 409).
    static func shapeError(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a rule such as Bash(npm test *)." }
        guard trimmed.utf16.count <= Rules.maxRuleLength, !trimmed.contains(where: \.isNewline), Rules.parseRule(trimmed) != nil else {
            return "That is not a valid rule. Use Tool or Tool(pattern) on one line."
        }
        return nil
    }
}
