import Foundation

// clis.list and the CLI id every other DTO carries. Go: core/internal/clis, core/internal/rpc/methods/clis-list.go;
// docs/internals/core-protocol.md, "Wire types" (spec MC-R2, MC27).

/// A CLI as the wire names it: an open string (`claude`, `codex`, `gemini`, and whatever the core's registry adds). Decoding
/// never fails on an id the shell has not seen; `CLICatalog` drops an id that `clis.list` did not return, so it is never shown.
struct CLIID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

/// What a CLI's registry entry implements (`clis.Concept`).
enum CoreCLIConcept: String, Codable, Hashable, Sendable {
    case inventory, mutate, usage, activity, limits
}

/// How far SpaceVibe supports one item kind in one CLI.
enum CoreKindSupport: String, Codable, Hashable, Sendable {
    /// Read and written.
    case full
    /// Read only: never a write target.
    case readOnly
    /// The CLI has no such kind: its cells read `absent`, never 0 and never an add target.
    case absent
}

/// Whether a kind's runs are counted from the CLI's logs.
enum CoreKindRuns: String, Codable, Hashable, Sendable {
    case counted, notLogged
}

/// One item kind of one CLI.
struct CoreKindInfo: Codable, Equatable, Sendable {
    var kind: CoreKind
    var support: CoreKindSupport
    /// Nil when the kind is absent.
    @CoreNullable var runs: CoreKindRuns?
    /// Set exactly when `runs` is `notLogged`.
    @CoreNullable var notLoggedReason: String?
    /// An open string (`skillFolder`, `agentFields`, `commandHook`): two CLIs with the same format can copy this kind between
    /// them; nil never copies.
    @CoreNullable var copyFormat: String?
}

/// One CLI of `clis.list`, in the core's registry order. Every per-CLI fact the shell needs comes from here; the shell keeps
/// only each CLI's look (`CLIRegistry`).
struct CoreCLIInfo: Codable, Equatable, Sendable {
    var id: CLIID
    var label: String
    /// Its root folder, or a binary its entry names on `PATH`, exists. Never a run of the CLI (MC8).
    var installed: Bool
    var concepts: [CoreCLIConcept]
    /// skill, agent, hook, in that order.
    var kinds: [CoreKindInfo]
    /// Nil without the limits concept.
    @CoreNullable var limitsReading: CLILimitsReading?
    var logsHookRuns: Bool
    var readsSessionLog: Bool
    /// The Activity limit code a waiting-or-busy session of this CLI carries.
    @CoreNullable var approvalLimitCode: String?
    var subagentWithoutToolsGetsEveryTool: Bool
}

/// The `clis.list` result.
struct CoreCLIsList: Codable, Equatable, Sendable {
    var clis: [CoreCLIInfo]
}

/// Where a CLI's usage limits are read from (`limits.ReadingKind`).
enum CLILimitsReading: String, Codable, Hashable, Sendable {
    /// A cache the CLI writes only after it has fetched usage once (`/usage`); the status line can also feed it.
    case usageCache
    /// The limits the CLI logs after each turn.
    case lastTurn
    /// The CLI keeps no usage limit on disk: it reads "not measurable".
    case notKept
}

/// A per-CLI count on the wire (`{cli, count}`): `FilterCounts.only`, `UsageResult.sessions`.
struct CoreCLICount: Codable, Equatable, Sendable {
    var cli: CLIID
    var count: Int
}

/// A CLI's hook events (`{cli, events}`), in registry order.
struct CoreCLIEvents: Codable, Equatable, Sendable {
    var cli: CLIID
    var events: [String]
}

/// A CLI's config root (`{cli, root}`), in registry order.
struct CoreCLIRoot: Codable, Equatable, Sendable {
    var cli: CLIID
    var root: String
}

extension Array where Element == CoreCLIEvents {
    /// The events of `cli`, or nil when the list has no entry for it.
    subscript(cli cli: CLIID) -> [String]? { first { $0.cli == cli }?.events }
}

extension Array where Element == CoreCLIRoot {
    subscript(cli cli: CLIID) -> String? { first { $0.cli == cli }?.root }
}
