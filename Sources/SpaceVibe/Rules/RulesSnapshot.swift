import Foundation

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
    let rules: [CoreRule]
    let grid: [CoreCapabilityCell]
    let codex: CoreCodexPermissions
    /// The scope's file or folder could not be looked at: its rules are unknown, not empty. The core says so in `problems`.
    let notReadable: Bool
    /// The same for the global file, which `globalRuleCount` counts.
    let globalNotReadable: Bool

    var title: String { RulesScopes.title(for: selection, projects: projects) }

    /// A grid is editable only when the file parses and can be read; a `mixed` cell never is.
    func isEditable(_ cell: CoreCapabilityCell) -> Bool { cell.editable && problems.isEmpty && !notReadable }

    func rules(_ verdict: CoreVerdict) -> [CoreRule] { rules.filter { $0.verdict == verdict } }

    /// What `rules.snapshot` read. The selection is the scope the core actually read: global when the asked project is not listed.
    init(_ dto: CoreRulesSnapshot) {
        projectDirs = dto.projectDirs
        projects = RulesScopes.projects(from: dto.projectDirs)
        globalRuleCount = dto.globalRuleCount
        selection = RulesSelection(dir: dto.dir, file: dto.scope == .local ? .local : .shared)
        fileLabel = dto.fileLabel
        exists = dto.exists
        problems = dto.problems
        rules = dto.rules
        grid = dto.grid
        codex = dto.codex
        notReadable = dto.notReadable
        globalNotReadable = dto.globalNotReadable
    }
}
