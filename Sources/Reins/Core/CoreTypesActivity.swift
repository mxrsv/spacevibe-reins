import Foundation

// activity.read, activity.subscribe, activity.stop. Go: core/internal/activity/report.go.

enum CoreSessionState: String, Codable, Sendable {
    case running, waiting, idle, ended, unmeasurable
}

struct CoreActivityTool: Codable, Equatable, Sendable {
    var name: String
    var target: String
}

/// An API-equivalent estimate; `estimated` is always true.
struct CoreActivityCost: Codable, Equatable, Sendable {
    var usd: Double
    var estimated: Bool
}

struct CoreActivitySession: Codable, Equatable, Sendable, Identifiable {
    var cli: CoreCLI
    var id: String
    var title: String
    @CoreNullable var project: String?
    var pid: Int
    var state: CoreSessionState
    var stateReason: String
    /// An open string: the core may add codes. Known: codex-no-rollout, codex-tool-silent, claude-prompt-vs-busy,
    /// claude-unknown-status, codex-hook-runs, codex-process-unknown. Show `stateReason`, not the code.
    @CoreNullable var reasonCode: String?
    @CoreNullable var currentTool: CoreActivityTool?
    /// Milliseconds since the session started.
    @CoreNullable var ageMs: Double?
    /// Milliseconds since the transcript was last written.
    @CoreNullable var lastWriteAgoMs: Double?
    @CoreNullable var cost: CoreActivityCost?
    @CoreNullable var costNote: String?
}

enum CoreFailureKind: String, Codable, Sendable {
    case command, hook
}

struct CoreActivityHookRef: Codable, Equatable, Sendable {
    var hash: String
    var event: String
}

struct CoreActivityFailure: Codable, Equatable, Sendable {
    var kind: CoreFailureKind
    var cli: CoreCLI
    var key: String
    var title: String
    var count: Int
    @CoreNullable var exit: Int?
    var reason: String
    var projects: [String]
    var sessions: Int
    @CoreNullable var first: String?
    @CoreNullable var last: String?
    @CoreNullable var laterPass: String?
    @CoreNullable var hook: CoreActivityHookRef?
}

struct CoreActivityFile: Codable, Equatable, Sendable {
    var path: String
    var label: String
    var edits: Int
    var sessions: Int
    @CoreNullable var last: String?
    var clis: [CoreCLI]
    var projects: [String]
}

/// Something that cannot be measured, listed even when no session is live. `code` is an open string like `reasonCode`.
struct CoreActivityLimit: Codable, Equatable, Sendable {
    var cli: CoreCLI
    var code: String
    var text: String
}

struct CoreActivityStats: Codable, Equatable, Sendable {
    var logs: Int
    var truncated: Int
}

/// The `activity.read` result and every `activity/report` notification: a full report that replaces the last.
struct CoreActivityReport: Codable, Equatable, Sendable {
    var sessions: [CoreActivitySession]
    var failures: [CoreActivityFailure]
    var files: [CoreActivityFile]
    var unmeasurable: [CoreActivityLimit]
    var stats: CoreActivityStats
}

/// The `activity.stop` result. `exited` is false when the process was still alive at the end of the wait.
struct CoreStopResult: Codable, Equatable, Sendable {
    var exited: Bool
}
