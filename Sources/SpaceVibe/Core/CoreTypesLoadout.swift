import Foundation

// loadout.rows and the writes that return a journal entry. Go: core/internal/inventory/loadout-rows.go,
// core/internal/mutate/{service,ops}.go.

/// Counts for the filter chips, deduplicated by row key.
struct CoreFilterCounts: Codable, Equatable, Sendable {
    struct Only: Codable, Equatable, Sendable {
        var claude: Int
        var codex: Int
    }

    var all: Int
    var only: Only
    var neverRan: Int
    var dead: Int
}

/// The chips one matrix row sets: each is the filter count over the row's members, above zero.
struct CoreRowFlags: Codable, Equatable, Sendable {
    var one: Bool
    var neverRan: Bool
    var dead: Bool
}

/// `loadout.rows`: one inventory read with usage attached. Grouping rows by `key`, sorting and labels stay in Swift.
/// `problems` are the raw sentences with absolute paths; the shell shortens the home folder before showing them.
struct CoreLoadoutRows: Codable, Equatable, Sendable {
    enum UsageState: String, Codable, Sendable {
        case scanning, ready
    }

    var usage: UsageState
    var items: [CoreInventoryItem]
    var hooks: [CoreInventoryHook]
    var problems: [String]
    var events: [String: [String]]
    var roots: [String: String]
    /// Keyed `global` or an absolute project folder.
    var countsByScope: [String: CoreFilterCounts]
    /// Keyed by row key.
    var rowFlags: [String: CoreRowFlags]
}

/// What a write returns for the entry it recorded. The ops hold absolute paths and trash names, so only their count
/// leaves the core.
struct CoreJournalEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// ISO 8601 UTC with milliseconds.
    var at: String
    var label: String
    var undone: Bool
    var count: Int
}

/// The result of `loadout.copyToOther`, `loadout.removeItem`, `loadout.removeDeadHooks`, `rules.add`, `rules.remove`
/// and `rules.changeVerdict`.
struct CoreEntryResult: Codable, Equatable, Sendable {
    var entry: CoreJournalEntry
}

struct CoreUndoResult: Codable, Equatable, Sendable {
    var label: String
}

/// Newest first, at most 200 entries.
struct CoreJournalHistory: Codable, Equatable, Sendable {
    var entries: [CoreJournalEntry]
}
