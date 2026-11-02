import Foundation
import ReinsCore

/// Everything the Rules screen shows for one scope, read in one pass off the main actor.
struct RulesSnapshot {
    /// Absolute folders of the discovered projects. Discovery is expensive, so one refresh does it once and every list,
    /// preview and write until the next refresh reuses this list.
    let projectDirs: [String]
    let projects: [RulesProject]
    /// Rule count of the global file: the sidebar badge.
    let globalRuleCount: Int
    /// The selection that was actually read (Global when the chosen project is gone).
    let selection: RulesSelection
    let fileLabel: String
    /// False when the scope's file does not exist yet: the first rule creates it.
    let exists: Bool
    /// Sentences about files that are not valid settings, with absolute paths replaced by `fileLabel`.
    let problems: [String]
    let rules: [RuleItem]
    let grid: [CapabilityCell]
    let codex: CodexPermissions

    var title: String { RulesScopes.title(for: selection, projects: projects) }

    /// A grid is editable only when the file parses; a `mixed` cell never is.
    func isEditable(_ cell: CapabilityCell) -> Bool { cell.editable && problems.isEmpty }

    func rules(_ verdict: RuleVerdict) -> [RuleItem] { rules.filter { $0.verdict == verdict } }

    func store(roots: Roots) -> RulesStore {
        let dirs = projectDirs
        return RulesStore(roots: roots, projects: { dirs })
    }
}

enum RulesReader {
    /// Reads the scope, the global rule count and the Codex permissions. Pass `projects` to skip discovery (a scope switch);
    /// nil discovers once. Throws a `ReinsError` whose message is safe to show.
    static func read(roots: Roots, selection: RulesSelection, projects cached: [String]?) throws -> RulesSnapshot {
        let dirs = cached ?? Inventory.discoverProjects(roots: roots)
        let store = RulesStore(roots: roots, projects: { dirs })
        let effective = selection.dir.map { dirs.contains($0) } ?? true ? selection : .global
        let scope = effective.scope
        return try RulesScopes.scrubbed(store: store, scope: scope) {
            let global = try store.listRules([.global])
            let listing = effective == .global ? global : try store.listRules([scope])
            let file = try store.file(for: scope)
            let problems = listing.problems.map { RulesScopes.scrub($0, path: file.path, label: scope.fileLabel) }
            return RulesSnapshot(
                projectDirs: dirs,
                projects: RulesScopes.projects(from: dirs),
                globalRuleCount: global.rules.count,
                selection: effective,
                fileLabel: scope.fileLabel,
                exists: FileManager.default.fileExists(atPath: file.path),
                problems: problems,
                rules: listing.rules,
                grid: Rules.capabilityGrid(listing.rules),
                codex: CodexPermissions.read(roots: roots)
            )
        }
    }
}
