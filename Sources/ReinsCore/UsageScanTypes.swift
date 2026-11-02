import Foundation

/// What the logs say about one skill or agent name: in how many sessions it was used, and on which days.
public struct NameUsage: Codable, Equatable, Sendable {
    public var sessions: Int
    /// `YYYY-MM-DD`, sorted.
    public var days: [String]
    @NullEncoded public var last: String?

    public init(sessions: Int, days: [String], last: String?) {
        self.sessions = sessions; self.days = days; self.last = last
    }
}

/// Totals of one hook, keyed by `Inventory.hookHash(event:command:)`.
public struct HookTotals: Codable, Equatable, Sendable {
    public var runs: Int
    /// Sum of the durations that were recorded (`timed` runs had one).
    public var ms: Double
    public var timed: Int
    public var errors: Int
    @NullEncoded public var last: String?

    public init(runs: Int = 0, ms: Double = 0, timed: Int = 0, errors: Int = 0, last: String? = nil) {
        self.runs = runs; self.ms = ms; self.timed = timed; self.errors = errors; self.last = last
    }
}

public struct CLIUsageTotals: Codable, Equatable, Sendable {
    /// Keyed by the bare skill name.
    public var skill: [String: NameUsage] = [:]
    public var agent: [String: NameUsage] = [:]
    public var hook: [String: HookTotals] = [:]

    public init(skill: [String: NameUsage] = [:], agent: [String: NameUsage] = [:], hook: [String: HookTotals] = [:]) {
        self.skill = skill; self.agent = agent; self.hook = hook
    }
}

public struct UsageTotals: Codable, Equatable, Sendable {
    public var claude: CLIUsageTotals
    public var codex: CLIUsageTotals

    public init(claude: CLIUsageTotals = CLIUsageTotals(), codex: CLIUsageTotals = CLIUsageTotals()) {
        self.claude = claude; self.codex = codex
    }

    public subscript(cli: InventoryCLI) -> CLIUsageTotals { cli == .claude ? claude : codex }
}

/// The span of logs scanned for one CLI. `oldest` is the first timestamp's day; `newest` is the newest log's mtime in ms since 1970.
public struct LogWindow: Codable, Equatable, Sendable {
    public var files: Int
    @NullEncoded public var oldest: String?
    @NullEncoded public var newest: Int64?

    public init(files: Int = 0, oldest: String? = nil, newest: Int64? = nil) {
        self.files = files; self.oldest = oldest; self.newest = newest
    }
}

public struct UsageWindows: Codable, Equatable, Sendable {
    public var claude: LogWindow
    public var codex: LogWindow

    public init(claude: LogWindow = LogWindow(), codex: LogWindow = LogWindow()) {
        self.claude = claude; self.codex = codex
    }

    public subscript(cli: InventoryCLI) -> LogWindow { cli == .claude ? claude : codex }
}

public struct UsageSessions: Codable, Equatable, Sendable {
    public var claude: Int
    public var codex: Int
}

/// The result of one scan: the shape `scan()` returns in core/usage.mjs.
public struct UsageResult: Codable, Equatable, Sendable {
    public var totals: UsageTotals
    /// Distinct sessions per CLI.
    public var sessions: UsageSessions
    public var windows: UsageWindows
    /// Log files found (including any that could not be read).
    public var files: Int
}

/// The usage state `Inventory.attachUsage` reads: `state` is "ready" once `totals` and `windows` exist.
/// While scanning, totals are nil and every zero-run cell shows "pending".
public struct UsageInput: Codable, Equatable, Sendable {
    public var state: String
    @NullEncoded public var totals: UsageTotals?
    @NullEncoded public var windows: UsageWindows?

    public init(state: String, totals: UsageTotals?, windows: UsageWindows?) {
        self.state = state; self.totals = totals; self.windows = windows
    }

    public static let scanning = UsageInput(state: "scanning", totals: nil, windows: nil)

    public static func ready(_ result: UsageResult) -> UsageInput {
        UsageInput(state: "ready", totals: result.totals, windows: result.windows)
    }
}

/// Progress of a running scan.
public struct UsageProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
}
