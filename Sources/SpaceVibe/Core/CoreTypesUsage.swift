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
    var cli: CLIID
    /// Keyed by the bare skill name.
    var skill: [String: CoreNameUsage]
    var agent: [String: CoreNameUsage]
    /// Keyed by the hook hash.
    var hook: [String: CoreHookTotals]
}

/// The span of logs scanned for one CLI. `newest` is milliseconds since 1970.
struct CoreLogWindow: Codable, Equatable, Sendable {
    var cli: CLIID
    var files: Int
    @CoreNullable var oldest: String?
    @CoreNullable var newest: Int64?
}

/// The `usage.scan` result. Each array holds one entry per CLI with the usage concept, in registry order.
struct CoreUsageResult: Codable, Equatable, Sendable {
    var totals: [CoreCLITotals]
    /// Sessions scanned per CLI.
    var sessions: [CoreCLICount]
    var windows: [CoreLogWindow]
    /// Log files found, including any that could not be read.
    var files: Int
}

extension Array where Element == CoreCLITotals {
    /// The totals of `cli`, or nil when the scan has no entry for it.
    subscript(cli cli: CLIID) -> CoreCLITotals? { first { $0.cli == cli } }
}

/// The `usage/progress` notification, without the request id the transport adds.
struct CoreUsageProgress: Codable, Equatable, Sendable {
    var done: Int
    var total: Int
}
