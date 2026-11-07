import Foundation

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

    var scope: RulesScope {
        guard let dir else { return .global }
        return file == .shared ? .project(dir) : .local(dir)
    }
}

/// The scope a call to the core names: its kind and, for a project, the absolute folder.
struct RulesScope: Equatable, Hashable, Sendable {
    let kind: CoreRuleScope
    let dir: String?

    static let global = RulesScope(kind: .global, dir: nil)
    static func project(_ dir: String) -> RulesScope { RulesScope(kind: .project, dir: dir) }
    static func local(_ dir: String) -> RulesScope { RulesScope(kind: .local, dir: dir) }
}

/// A project SpaceVibe discovered, with a name that tells it apart from the others.
struct RulesProject: Equatable, Hashable {
    let dir: String
    let name: String
}

/// Pure helpers for the scope list and the scope title. Covered by `RulesScopesTests`. The core keeps settings-file paths out of
/// its messages and checks a rule's shape (`rules.check`).
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

    /// "Global", "spacevibe-api (shared)" or "spacevibe-api (local)".
    static func title(for selection: RulesSelection, projects: [RulesProject]) -> String {
        guard let dir = selection.dir else { return "Global" }
        let name = projects.first { $0.dir == dir }?.name ?? (dir as NSString).lastPathComponent
        return selection.file == .local ? "\(name) (local)" : "\(name) (shared)"
    }
}
