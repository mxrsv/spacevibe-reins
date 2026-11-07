import Foundation

enum LoadoutKind: CaseIterable {
    case skill, agent, hook

    init(_ kind: CoreKind) {
        switch kind {
        case .skill: self = .skill
        case .agent: self = .agent
        case .hook: self = .hook
        }
    }

    var sectionTitle: String {
        switch self {
        case .skill: "Skills"
        case .agent: "Agents"
        case .hook: "Hooks"
        }
    }

    var noun: String {
        switch self {
        case .skill: "skill"
        case .agent: "agent"
        case .hook: "hook"
        }
    }

    var icon: ReinsGlyph {
        switch self {
        case .skill: .skill
        case .agent: .agent
        case .hook: .hook
        }
    }
}

/// One installed thing in one CLI: a skill or agent folder/file, or one hook command.
enum LoadoutMember: Equatable, Sendable {
    case item(CoreInventoryItem)
    case hook(CoreInventoryHook)

    var id: String {
        switch self {
        case .item(let item): item.id
        case .hook(let hook): hook.id
        }
    }

    var cli: CoreCLI {
        switch self {
        case .item(let item): item.cli
        case .hook(let hook): hook.cli
        }
    }

    var removable: Bool {
        switch self {
        case .item(let item): item.removable
        case .hook(let hook): hook.removable
        }
    }

    var owner: String {
        switch self {
        case .item(let item): item.owner
        case .hook(let hook): hook.owner
        }
    }

    var cells: CoreCells? {
        switch self {
        case .item(let item): item.cells
        case .hook(let hook): hook.cells
        }
    }
}

enum LoadoutFilter: CaseIterable, Hashable {
    case all, one, never, dead

    var title: String {
        switch self {
        case .all: "All"
        case .one: "In one CLI only"
        case .never: "Never ran"
        case .dead: "Dead"
        }
    }

    func matches(_ flags: CoreRowFlags) -> Bool {
        switch self {
        case .all: true
        case .one: flags.one
        case .never: flags.neverRan
        case .dead: flags.dead
        }
    }

    func count(in counts: CoreFilterCounts) -> Int {
        switch self {
        case .all: counts.all
        case .one: counts.only.claude + counts.only.codex
        case .never: counts.neverRan
        case .dead: counts.dead
        }
    }
}

/// One row of the matrix: the same skill, agent or hook seen across both CLIs.
struct LoadoutRow: Identifiable, Equatable, Sendable {
    var id: String { key }
    var key: String
    var kind: LoadoutKind
    /// Absolute project path, or nil for user-level config.
    var project: String?
    var members: [CoreCLI: LoadoutMember]
    var cells: CoreCells
    /// Which chip the row answers to: the core's `rowFlags`, decided with the function that counts the chips, so a chip's
    /// number and the rows it shows cannot disagree.
    var flags: CoreRowFlags
    var name: String
    /// A description for skills and agents; the command for hooks.
    var detail: String
    /// The plugin name when every member belongs to a plugin.
    var plugin: String?
    var errors: Int
    /// Total counted runs across the CLIs, for sorting.
    var runs: Int
    var addedNote: String?

    var removableMembers: [LoadoutMember] {
        CoreCLI.allCases.compactMap { members[$0] }.filter(\.removable)
    }
}

struct LoadoutScope: Equatable, Hashable, Sendable {
    var value: String
    var label: String
}
