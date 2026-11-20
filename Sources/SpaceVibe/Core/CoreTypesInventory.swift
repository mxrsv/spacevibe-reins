import Foundation

// inventory.read: what is installed. Field names are the core's JSON exactly (docs/internals/core-protocol.md,
// "Inventory and usage"; Go: core/internal/inventory). A member the wire always writes is `@CoreNullable`; one it omits
// when absent (`cells`, `override`, a counted cell's `errors`) is a plain optional.

enum CoreKind: String, Codable, Hashable, Sendable {
    case skill, agent, hook
}

enum CoreInventoryScope: String, Codable, Hashable, Sendable {
    case global, project
}

/// The usage cell of one CLI for one row. The wire object is keyed by `state`; `errors` is written for a hook only and
/// `last` is `null` when unknown.
enum CoreUsageCell: Equatable, Sendable {
    case counted(runs: Int, last: String?, errors: Int?)
    case pending(reason: String)
    /// The CLI has the kind but does not log it.
    case unmeasurable(reason: String)
    /// The CLI has the kind; this item is not installed in it.
    case missing
    /// The CLI has no such kind (GLOSSARY "Absent"): never shown as 0, as missing or as a place to add to.
    case absent

    /// The row is installed in that CLI: the cell is neither missing nor absent.
    var isPresent: Bool {
        switch self {
        case .missing, .absent: false
        case .counted, .pending, .unmeasurable: true
        }
    }
}

extension CoreUsageCell: Codable {
    private enum Keys: String, CodingKey { case state, runs, errors, last, reason }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .state) {
        case "counted":
            self = .counted(runs: try c.decode(Int.self, forKey: .runs), last: try c.decodeIfPresent(String.self, forKey: .last), errors: try c.decodeIfPresent(Int.self, forKey: .errors))
        case "pending": self = .pending(reason: try c.decode(String.self, forKey: .reason))
        case "unmeasurable": self = .unmeasurable(reason: try c.decode(String.self, forKey: .reason))
        case "missing": self = .missing
        case "absent": self = .absent
        case let other: throw DecodingError.dataCorruptedError(forKey: .state, in: c, debugDescription: "unknown cell state \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .counted(let runs, let last, let errors):
            try c.encode("counted", forKey: .state)
            try c.encode(runs, forKey: .runs)
            try c.encodeIfPresent(errors, forKey: .errors)
            if let last { try c.encode(last, forKey: .last) } else { try c.encodeNil(forKey: .last) }
        case .pending(let reason):
            try c.encode("pending", forKey: .state)
            try c.encode(reason, forKey: .reason)
        case .unmeasurable(let reason):
            try c.encode("unmeasurable", forKey: .state)
            try c.encode(reason, forKey: .reason)
        case .missing:
            try c.encode("missing", forKey: .state)
        case .absent:
            try c.encode("absent", forKey: .state)
        }
    }
}

/// One cell per CLI with the inventory concept, in registry order (`[{cli, state, ...}]`). A CLI the list does not hold has no
/// such row kind in this snapshot, so it reads `absent`.
struct CoreCells: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var cli: CLIID
        var cell: CoreUsageCell
    }

    var entries: [Entry]

    init(entries: [Entry]) { self.entries = entries }

    /// One cell per CLI of `clis`, from `cell`, in that order.
    init(_ clis: [CLIID], _ cell: (CLIID) -> CoreUsageCell) {
        entries = clis.map { Entry(cli: $0, cell: cell($0)) }
    }

    /// One cell per CLI, in the order written: `CoreCells([.claude: .missing, .codex: .absent])`.
    init(_ cells: KeyValuePairs<CLIID, CoreUsageCell>) {
        entries = cells.map { Entry(cli: $0.key, cell: $0.value) }
    }

    /// The CLIs the cells list, in their order.
    var clis: [CLIID] { entries.map(\.cli) }

    subscript(cli: CLIID) -> CoreUsageCell {
        get { entries.first { $0.cli == cli }?.cell ?? .absent }
        set {
            if let index = entries.firstIndex(where: { $0.cli == cli }) { entries[index].cell = newValue }
            else { entries.append(Entry(cli: cli, cell: newValue)) }
        }
    }

    /// The cells of the CLIs `keep` accepts, in the same order.
    func filter(_ keep: (CLIID) -> Bool) -> CoreCells { CoreCells(entries: entries.filter { keep($0.cli) }) }
}

extension CoreCells.Entry: Codable {
    private enum Keys: String, CodingKey { case cli }

    init(from decoder: Decoder) throws {
        cli = try decoder.container(keyedBy: Keys.self).decode(CLIID.self, forKey: .cli)
        cell = try CoreUsageCell(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try cell.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(cli, forKey: .cli)
    }
}

extension CoreCells: Codable {
    init(from decoder: Decoder) throws {
        entries = try [Entry](from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try entries.encode(to: encoder)
    }
}

/// A skill or a subagent.
struct CoreInventoryItem: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var cli: CLIID
    /// `skill` or `agent`.
    var kind: CoreKind
    var name: String
    var entry: String
    var description: String
    /// The CLIs that read this file (MC-R7); today always `[cli]`.
    var readBy: [CLIID]
    /// `user`, `link`, or a plugin name.
    var owner: String
    var path: String
    var file: String
    var removable: Bool
    var scope: CoreInventoryScope
    @CoreNullable var project: String?
    /// The matrix row: `<kind>:<project or empty>:<bare name>`.
    var key: String
    /// Written on every Claude global skill (`null` when settings hold no value) and omitted on all other items, so
    /// presence is its own flag.
    var hasSkillOverride: Bool
    var skillOverride: String?
    /// Omitted until usage is attached.
    var cells: CoreCells?

    private enum Keys: String, CodingKey {
        case id, cli, kind, name, entry, description, readBy, owner, path, file, removable, scope, project, skillOverride = "override", key, cells
    }

    /// `readBy` defaults to the item's own CLI, as the core writes it today.
    init(id: String, cli: CLIID, kind: CoreKind, name: String, entry: String, description: String, readBy: [CLIID]? = nil, owner: String, path: String, file: String, removable: Bool, scope: CoreInventoryScope, project: String?, key: String, hasSkillOverride: Bool = false, skillOverride: String? = nil, cells: CoreCells? = nil) {
        self.id = id; self.cli = cli; self.kind = kind; self.name = name; self.entry = entry; self.description = description
        self.readBy = readBy ?? [cli]
        self.owner = owner; self.path = path; self.file = file; self.removable = removable; self.scope = scope
        self.project = project; self.key = key; self.hasSkillOverride = hasSkillOverride; self.skillOverride = skillOverride; self.cells = cells
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        cli = try c.decode(CLIID.self, forKey: .cli)
        kind = try c.decode(CoreKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        entry = try c.decode(String.self, forKey: .entry)
        description = try c.decode(String.self, forKey: .description)
        readBy = try c.decode([CLIID].self, forKey: .readBy)
        owner = try c.decode(String.self, forKey: .owner)
        path = try c.decode(String.self, forKey: .path)
        file = try c.decode(String.self, forKey: .file)
        removable = try c.decode(Bool.self, forKey: .removable)
        scope = try c.decode(CoreInventoryScope.self, forKey: .scope)
        project = try c.decode(CoreNullable<String>.self, forKey: .project).wrappedValue
        key = try c.decode(String.self, forKey: .key)
        hasSkillOverride = c.contains(.skillOverride)
        skillOverride = try c.decodeIfPresent(String.self, forKey: .skillOverride)
        cells = try c.decodeIfPresent(CoreCells.self, forKey: .cells)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(cli, forKey: .cli)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(entry, forKey: .entry)
        try c.encode(description, forKey: .description)
        try c.encode(readBy, forKey: .readBy)
        try c.encode(owner, forKey: .owner)
        try c.encode(path, forKey: .path)
        try c.encode(file, forKey: .file)
        try c.encode(removable, forKey: .removable)
        try c.encode(scope, forKey: .scope)
        try c.encode(CoreNullable(wrappedValue: project), forKey: .project)
        if hasSkillOverride { try c.encode(CoreNullable(wrappedValue: skillOverride), forKey: .skillOverride) }
        try c.encode(key, forKey: .key)
        try c.encodeIfPresent(cells, forKey: .cells)
    }
}

/// What the logs say about one hook (Claude only).
struct CoreHookUsage: Codable, Equatable, Sendable {
    var runs: Int
    /// Over timed runs; Go writes an integer.
    @CoreNullable var avgMs: Int?
    var totalMs: Double
    var errors: Int
    @CoreNullable var last: String?
}

struct CoreInventoryHook: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var cli: CLIID
    /// Always `hook`.
    var kind: CoreKind
    var event: String
    @CoreNullable var matcher: String?
    var command: String
    @CoreNullable var timeout: Double?
    var async: Bool
    var owner: String
    var removable: Bool
    var dead: Bool
    var paths: [String]
    var hash: String
    var file: String
    var scope: CoreInventoryScope
    @CoreNullable var project: String?
    /// `hook:<project or empty>:<hash>`.
    var key: String
    var cells: CoreCells?
    /// Always written; `null` when unknown or not logged.
    @CoreNullable var usage: CoreHookUsage?
}

/// The `inventory.read` result: no `cells`, hook `usage` null.
struct CoreInventorySnapshot: Codable, Equatable, Sendable {
    var items: [CoreInventoryItem]
    var hooks: [CoreInventoryHook]
    var problems: [String]
    /// Hook events per CLI with the inventory concept, in registry order.
    var events: [CoreCLIEvents]
    /// Config root per CLI with the inventory concept, in registry order.
    var roots: [CoreCLIRoot]
}
