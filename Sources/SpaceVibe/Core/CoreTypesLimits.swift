import Foundation

// limits.read. Go: core/internal/limits/limits.go. The two timestamps are seconds since 1970 as numbers (fractions
// allowed), the one place the protocol does not use ISO text.

enum CoreLimitsCLI: String, Codable, CaseIterable, Sendable {
    case claude, codex, gemini
}

enum CoreLimitsState: String, Codable, Sendable {
    case measured, notRecorded, unreadable, notMeasurable, notInstalled
}

enum CoreLimitsSource: String, Codable, Sendable {
    case claudeCache, claudeStatusline
}

struct CoreLimitWindow: Codable, Equatable, Sendable {
    var id: String
    @CoreNullable var minutes: Int?
    @CoreNullable var scope: String?
    /// Can pass 100.
    var usedPercent: Double
    /// Seconds since 1970.
    var resetsAt: Double
    /// False when the CLI marks the window as not applying now.
    var active: Bool
    /// `resetsAt` is after the core's now. A window that is not current reads as unknown, never as 0.
    var current: Bool
}

struct CoreLimitsEntry: Codable, Equatable, Sendable {
    var cli: CoreLimitsCLI
    var state: CoreLimitsState
    @CoreNullable var plan: String?
    @CoreNullable var source: CoreLimitsSource?
    /// Seconds since 1970; set only when measured.
    @CoreNullable var at: Double?
    /// Empty unless measured, never null.
    var windows: [CoreLimitWindow]
}

/// The `limits.read` result, in order claude, codex, gemini.
struct CoreLimitsResult: Codable, Equatable, Sendable {
    var limits: [CoreLimitsEntry]
}
