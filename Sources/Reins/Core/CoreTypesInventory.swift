import Foundation

// inventory.read: what is installed. Field names are the core's JSON exactly (docs/internals/core-protocol.md,
// "Inventory and usage"; Go: core/internal/inventory). A member the wire always writes is `@CoreNullable`; one it omits
// when absent (`cells`, `override`, a counted cell's `errors`) is a plain optional.

enum CoreCLI: String, Codable, CaseIterable, Hashable, Sendable {
    case claude, codex

    var other: CoreCLI { self == .claude ? .codex : .claude }
}

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
    case unmeasurable(reason: String)
    case missing
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
        }
    }
}

struct CoreCells: Codable, Equatable, Sendable {
    var claude: CoreUsageCell
    var codex: CoreUsageCell

    subscript(cli: CoreCLI) -> CoreUsageCell { cli == .claude ? claude : codex }
}

/// A skill or a subagent.
struct CoreInventoryItem: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var cli: CoreCLI
    /// `skill` or `agent`.
    var kind: CoreKind
    var name: String
    var entry: String
    var description: String
    /// `user`, `link`, or a plugin name.
    var owner: String
    var path: String
    var file: String
    var removable: Bool
    var scope: CoreInventoryScope
    @CoreNullable var project: String?
    var inOther: Bool
    /// The matrix row: `<kind>:<project or empty>:<bare name>`.
    var key: String
    /// Written on every Claude global skill (`null` when settings hold no value) and omitted on all other items, so
    /// presence is its own flag.
    var hasSkillOverride: Bool
    var skillOverride: String?
    /// Omitted until usage is attached.
    var cells: CoreCells?

    private enum Keys: String, CodingKey {
        case id, cli, kind, name, entry, description, owner, path, file, removable, scope, project, inOther, skillOverride = "override", key, cells
    }

    init(id: String, cli: CoreCLI, kind: CoreKind, name: String, entry: String, description: String, owner: String, path: String, file: String, removable: Bool, scope: CoreInventoryScope, project: String?, inOther: Bool, key: String, hasSkillOverride: Bool = false, skillOverride: String? = nil, cells: CoreCells? = nil) {
        self.id = id; self.cli = cli; self.kind = kind; self.name = name; self.entry = entry; self.description = description
        self.owner = owner; self.path = path; self.file = file; self.removable = removable; self.scope = scope
        self.project = project; self.inOther = inOther; self.key = key; self.hasSkillOverride = hasSkillOverride; self.skillOverride = skillOverride; self.cells = cells
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        cli = try c.decode(CoreCLI.self, forKey: .cli)
        kind = try c.decode(CoreKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        entry = try c.decode(String.self, forKey: .entry)
        description = try c.decode(String.self, forKey: .description)
        owner = try c.decode(String.self, forKey: .owner)
        path = try c.decode(String.self, forKey: .path)
        file = try c.decode(String.self, forKey: .file)
        removable = try c.decode(Bool.self, forKey: .removable)
        scope = try c.decode(CoreInventoryScope.self, forKey: .scope)
        project = try c.decode(CoreNullable<String>.self, forKey: .project).wrappedValue
        inOther = try c.decode(Bool.self, forKey: .inOther)
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
        try c.encode(owner, forKey: .owner)
        try c.encode(path, forKey: .path)
        try c.encode(file, forKey: .file)
        try c.encode(removable, forKey: .removable)
        try c.encode(scope, forKey: .scope)
        try c.encode(CoreNullable(wrappedValue: project), forKey: .project)
        try c.encode(inOther, forKey: .inOther)
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
    var cli: CoreCLI
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
    /// Hook events per CLI (`claude`, `codex`).
    var events: [String: [String]]
    /// Config root per CLI (`claude`, `codex`).
    var roots: [String: String]
}
