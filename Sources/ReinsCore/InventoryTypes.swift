import Foundation

/// Namespace of the Loadout inventory engine (port of Node inventory (git b58269d)). The functions live in the `Inventory*.swift` files.
public enum Inventory {
    /// Hook events each CLI documents. Claude's list comes from its docs; Codex's from observation only.
    public static let events: [String: [String]] = [
        "claude": ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart", "SubagentStop", "Elicitation", "ElicitationResult", "TeammateIdle", "PreCompact", "PostCompact", "Stop", "StopFailure", "SessionEnd"],
        "codex": ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop", "Interrupt", "Stop", "SessionEnd"],
    ]
    /// At most this many project folders are discovered, newest first.
    public static let maxProjects = 300
    /// A zero-run item that changed inside this window is "pending", not "never ran".
    public static let pendingGrace: TimeInterval = 24 * 3600
    public static let codexHooksReason = "Codex does not log hook runs"
}

public enum InventoryCLI: String, Codable, CaseIterable, Hashable, Sendable {
    case claude, codex

    public var other: InventoryCLI { self == .claude ? .codex : .claude }
}

/// Wire value of `kind`: skill, agent or hook.
public enum InventoryKind: String, Codable, Hashable, Sendable {
    case skill, agent, hook
}

public enum InventoryScope: String, Codable, Hashable, Sendable {
    case global, project
}

/// Encodes `nil` as JSON `null` instead of leaving the key out, so output matches the Node core field for field.
@propertyWrapper
public struct NullEncoded<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var wrappedValue: Value?
    public init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = c.decodeNil() ? nil : try c.decode(Value.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    /// A missing key reads as nil, like an explicit null.
    public func decode<V>(_ type: NullEncoded<V>.Type, forKey key: Key) throws -> NullEncoded<V> {
        try decodeIfPresent(type, forKey: key) ?? NullEncoded(wrappedValue: nil)
    }
}

/// The usage cell of one CLI for one row: counted, pending, unmeasurable or missing.
public enum UsageCellState: Equatable, Sendable {
    /// `runs`: hook runs, or sessions that used the skill/agent. 0 means it never ran inside the scanned logs. `errors` only for hooks.
    case counted(runs: Int, last: String?, errors: Int?)
    /// Installed, but no scanned log can have covered it yet.
    case pending(reason: String)
    /// The CLI does not log it (Codex hooks).
    case unmeasurable(reason: String)
    /// Not installed in that CLI.
    case missing

    public var isMissing: Bool { if case .missing = self { return true } else { return false } }
}

extension UsageCellState: Codable {
    private enum Keys: String, CodingKey { case state, runs, errors, last, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .state) {
        case "counted":
            self = .counted(runs: try c.decode(Int.self, forKey: .runs), last: try c.decodeIfPresent(String.self, forKey: .last), errors: try c.decodeIfPresent(Int.self, forKey: .errors))
        case "pending": self = .pending(reason: try c.decode(String.self, forKey: .reason))
        case "unmeasurable": self = .unmeasurable(reason: try c.decode(String.self, forKey: .reason))
        case "missing": self = .missing
        case let other: throw DecodingError.dataCorruptedError(forKey: .state, in: c, debugDescription: "unknown state \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .counted(let runs, let last, let errors):
            try c.encode("counted", forKey: .state)
            try c.encode(runs, forKey: .runs)
            if let errors { try c.encode(errors, forKey: .errors) }
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

/// One cell per CLI.
public struct InventoryCells: Codable, Equatable, Sendable {
    public var claude: UsageCellState
    public var codex: UsageCellState

    public init(claude: UsageCellState, codex: UsageCellState) {
        self.claude = claude
        self.codex = codex
    }

    public subscript(cli: InventoryCLI) -> UsageCellState { cli == .claude ? claude : codex }
}

/// A skill or an agent. Same JSON field names as the Node output.
public struct InventoryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var cli: InventoryCLI
    /// `.skill` or `.agent`.
    public var kind: InventoryKind
    public var name: String
    /// Folder name (skill) or file name (agent).
    public var entry: String
    public var description: String
    /// `user`, `link` (a symlink), or the plugin name.
    public var owner: String
    public var path: String
    public var file: String
    /// The user can remove it: a user-level item, not one owned by a plugin and not one inside a project.
    public var removable: Bool
    public var scope: InventoryScope
    /// Absolute path of the owning project, or nil for user-level config.
    @NullEncoded public var project: String?
    /// The same row exists in the other CLI.
    public var inOther: Bool
    /// Claude global skills only: the `skillOverrides` value from settings (nil when none). Absent for other items.
    public var skillOverride: String?
    public var hasSkillOverride: Bool
    /// Set by `Inventory.attachUsage`.
    public var cells: InventoryCells?

    /// The matrix row this item belongs to: the same name (or hook) in the same project, whichever CLI holds it.
    public var key: String { "\(kind.rawValue):\(project ?? ""):\(Inventory.bare(name))" }

    public init(id: String, cli: InventoryCLI, kind: InventoryKind, name: String, entry: String, description: String, owner: String, path: String, file: String, removable: Bool, scope: InventoryScope, project: String?, inOther: Bool = false, skillOverride: String? = nil, hasSkillOverride: Bool = false, cells: InventoryCells? = nil) {
        self.id = id; self.cli = cli; self.kind = kind; self.name = name; self.entry = entry; self.description = description
        self.owner = owner; self.path = path; self.file = file; self.removable = removable; self.scope = scope
        self.project = project; self.inOther = inOther; self.skillOverride = skillOverride; self.hasSkillOverride = hasSkillOverride; self.cells = cells
    }

    private enum Keys: String, CodingKey {
        case id, cli, kind, name, entry, description, owner, path, file, removable, scope, project, inOther, skillOverride = "override", key, cells
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        cli = try c.decode(InventoryCLI.self, forKey: .cli)
        kind = try c.decode(InventoryKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        entry = try c.decode(String.self, forKey: .entry)
        description = try c.decode(String.self, forKey: .description)
        owner = try c.decode(String.self, forKey: .owner)
        path = try c.decode(String.self, forKey: .path)
        file = try c.decode(String.self, forKey: .file)
        removable = try c.decode(Bool.self, forKey: .removable)
        scope = try c.decode(InventoryScope.self, forKey: .scope)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        inOther = try c.decodeIfPresent(Bool.self, forKey: .inOther) ?? false
        hasSkillOverride = c.contains(.skillOverride)
        skillOverride = try c.decodeIfPresent(String.self, forKey: .skillOverride)
        cells = try c.decodeIfPresent(InventoryCells.self, forKey: .cells)
    }

    public func encode(to encoder: Encoder) throws {
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
        if let project { try c.encode(project, forKey: .project) } else { try c.encodeNil(forKey: .project) }
        try c.encode(inOther, forKey: .inOther)
        if hasSkillOverride {
            if let skillOverride { try c.encode(skillOverride, forKey: .skillOverride) } else { try c.encodeNil(forKey: .skillOverride) }
        }
        try c.encode(key, forKey: .key)
        try c.encodeIfPresent(cells, forKey: .cells)
    }
}

/// What the logs say about one hook (Claude only). `runs` counts every record of the hook; `avgMs` is over timed runs.
public struct HookUsage: Codable, Equatable, Sendable {
    public var runs: Int
    @NullEncoded public var avgMs: Int?
    public var totalMs: Double
    public var errors: Int
    @NullEncoded public var last: String?

    public init(runs: Int, avgMs: Int?, totalMs: Double, errors: Int, last: String?) {
        self.runs = runs; self.avgMs = avgMs; self.totalMs = totalMs; self.errors = errors; self.last = last
    }
}

/// One hook command in a settings file (Claude `settings.json`, Codex `hooks.json`, a plugin's `hooks.json`).
public struct InventoryHook: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var cli: InventoryCLI
    public var kind: InventoryKind = .hook
    public var event: String
    @NullEncoded public var matcher: String?
    public var command: String
    @NullEncoded public var timeout: Double?
    public var async: Bool
    /// `user` or the plugin name.
    public var owner: String
    public var removable: Bool
    /// The command names script paths and none of them exists.
    public var dead: Bool
    /// Absolute script paths the command names.
    public var paths: [String]
    /// sha1 of `event|command`, first 12 hex: the identity the logs use.
    public var hash: String
    public var file: String
    public var scope: InventoryScope
    @NullEncoded public var project: String?
    public var cells: InventoryCells?
    /// Nil when unknown (scan not finished) or not logged (Codex).
    @NullEncoded public var usage: HookUsage?

    public var key: String { "hook:\(project ?? ""):\(hash)" }

    public init(id: String, cli: InventoryCLI, event: String, matcher: String?, command: String, timeout: Double?, async: Bool, owner: String, removable: Bool, dead: Bool, paths: [String], hash: String, file: String, scope: InventoryScope, project: String?, cells: InventoryCells? = nil, usage: HookUsage? = nil) {
        self.id = id; self.cli = cli; self.event = event; self.matcher = matcher; self.command = command; self.timeout = timeout
        self.async = async; self.owner = owner; self.removable = removable; self.dead = dead; self.paths = paths; self.hash = hash
        self.file = file; self.scope = scope; self.project = project; self.cells = cells; self.usage = usage
    }

    private enum Keys: String, CodingKey {
        case id, cli, kind, event, matcher, command, timeout, async, owner, removable, dead, paths, hash, file, scope, project, key, cells, usage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        cli = try c.decode(InventoryCLI.self, forKey: .cli)
        event = try c.decode(String.self, forKey: .event)
        matcher = try c.decodeIfPresent(String.self, forKey: .matcher)
        command = try c.decode(String.self, forKey: .command)
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout)
        async = try c.decode(Bool.self, forKey: .async)
        owner = try c.decode(String.self, forKey: .owner)
        removable = try c.decode(Bool.self, forKey: .removable)
        dead = try c.decode(Bool.self, forKey: .dead)
        paths = try c.decode([String].self, forKey: .paths)
        hash = try c.decode(String.self, forKey: .hash)
        file = try c.decode(String.self, forKey: .file)
        scope = try c.decode(InventoryScope.self, forKey: .scope)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        cells = try c.decodeIfPresent(InventoryCells.self, forKey: .cells)
        usage = try c.decodeIfPresent(HookUsage.self, forKey: .usage)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(cli, forKey: .cli)
        try c.encode(kind, forKey: .kind)
        try c.encode(event, forKey: .event)
        try c.encode(matcher, forKey: .matcher)
        try c.encode(command, forKey: .command)
        try c.encode(timeout, forKey: .timeout)
        try c.encode(async, forKey: .async)
        try c.encode(owner, forKey: .owner)
        try c.encode(removable, forKey: .removable)
        try c.encode(dead, forKey: .dead)
        try c.encode(paths, forKey: .paths)
        try c.encode(hash, forKey: .hash)
        try c.encode(file, forKey: .file)
        try c.encode(scope, forKey: .scope)
        try c.encode(project, forKey: .project)
        try c.encode(key, forKey: .key)
        try c.encodeIfPresent(cells, forKey: .cells)
        try c.encode(usage, forKey: .usage)
    }
}

/// Everything installed, read from disk. `problems` are plain sentences for the UI ("... is not valid JSON ...").
public struct InventorySnapshot: Codable, Equatable, Sendable {
    public var items: [InventoryItem]
    public var hooks: [InventoryHook]
    public var problems: [String]
    public var events: [String: [String]]
    /// Config root of each CLI, keyed `claude` and `codex`.
    public var roots: [String: String]

    public init(items: [InventoryItem], hooks: [InventoryHook], problems: [String], events: [String: [String]] = Inventory.events, roots: [String: String]) {
        self.items = items; self.hooks = hooks; self.problems = problems; self.events = events; self.roots = roots
    }
}

/// Counts for the filter chips, deduplicated by row key.
public struct FilterCounts: Codable, Equatable, Sendable {
    public struct Only: Codable, Equatable, Sendable {
        public var claude: Int
        public var codex: Int
    }
    public var all: Int
    public var only: Only
    /// Ran in no CLI that logs it, and at least one CLI counted it. A dead hook is counted only under `dead`.
    public var neverRan: Int
    public var dead: Int
}

/// The text of a skill or agent file for the detail view, capped.
public struct InventoryItemFile: Equatable, Sendable {
    public var size: Int
    public var text: String
    public var truncated: Bool
}
