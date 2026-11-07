import Foundation

// usage.scan: what the logs say. Go: core/internal/usage/types.go.

struct CoreNameUsage: Codable, Equatable, Sendable {
    var sessions: Int
    /// `YYYY-MM-DD`, sorted.
    var days: [String]
    @CoreNullable var last: String?
}

struct CoreHookTotals: Codable, Equatable, Sendable {
    var runs: Int
    /// Sum of the recorded durations (`timed` runs had one).
    var ms: Double
    var timed: Int
    var errors: Int
    @CoreNullable var last: String?
}

struct CoreCLITotals: Codable, Equatable, Sendable {
    /// Keyed by the bare skill name.
    var skill: [String: CoreNameUsage]
    var agent: [String: CoreNameUsage]
    /// Keyed by the hook hash.
    var hook: [String: CoreHookTotals]
}

struct CoreUsageTotals: Codable, Equatable, Sendable {
    var claude: CoreCLITotals
    var codex: CoreCLITotals
}

/// The span of logs scanned for one CLI. `newest` is milliseconds since 1970.
struct CoreLogWindow: Codable, Equatable, Sendable {
    var files: Int
    @CoreNullable var oldest: String?
    @CoreNullable var newest: Int64?
}

struct CoreUsageWindows: Codable, Equatable, Sendable {
    var claude: CoreLogWindow
    var codex: CoreLogWindow
}

struct CoreUsageSessions: Codable, Equatable, Sendable {
    var claude: Int
    var codex: Int
}

/// The `usage.scan` result.
struct CoreUsageResult: Codable, Equatable, Sendable {
    var totals: CoreUsageTotals
    var sessions: CoreUsageSessions
    var windows: CoreUsageWindows
    /// Log files found, including any that could not be read.
    var files: Int
}

/// The `usage/progress` notification, without the request id the transport adds.
struct CoreUsageProgress: Codable, Equatable, Sendable {
    var done: Int
    var total: Int
}
