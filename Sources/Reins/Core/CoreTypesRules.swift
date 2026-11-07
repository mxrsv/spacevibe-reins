import Foundation

// rules.*: Claude Code permission rules and the Codex permission read. Go: core/internal/rules/{types,service,codex}.go.
// The Go-only members the doc page does not list (`notReadable`, `globalNotReadable`, `skippedLines`, `unreadable`,
// `folderNotReadable`) are here because the Go json tags are the truth.

enum CoreRuleScope: String, Codable, Hashable, Sendable {
    case global, project, local
}

enum CoreVerdict: String, Codable, CaseIterable, Hashable, Sendable {
    case allow, ask, deny
}

enum CoreCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case read, edit, run, network, push, secrets
}

/// The value of a grid cell. `mixed` means rules for specific paths or commands disagree.
enum CoreCapabilityState: String, Codable, Hashable, Sendable {
    case allow, ask, deny, mixed, none
}

/// One rule string found in a settings file.
struct CoreRule: Codable, Equatable, Sendable, Identifiable {
    /// `<scope>:<verdict>:<rule>`.
    var id: String
    var scope: CoreRuleScope
    /// The project folder; `null` for the global scope.
    @CoreNullable var dir: String?
    var file: String
    var verdict: CoreVerdict
    var rule: String
    @CoreNullable var tool: String?
    @CoreNullable var specifier: String?
}

struct CoreVerdictRule: Codable, Equatable, Hashable, Sendable {
    var verdict: CoreVerdict
    var rule: String
}

struct CoreCapabilityCell: Codable, Equatable, Sendable {
    var capability: CoreCapability
    var label: String
    var state: CoreCapabilityState
    /// False for `mixed`: the engine refuses to write it.
    var editable: Bool
    var rules: [CoreRule]
}

/// What a cell write would remove and write. It writes nothing and carries no absolute path.
struct CoreCapabilityPreview: Codable, Equatable, Sendable {
    var capability: CoreCapability
    var verdict: CoreVerdict
    var scopeLabel: String
    var current: CoreCapabilityState
    var resulting: CoreCapabilityState
    var replaces: [CoreVerdictRule]
    var writes: [CoreVerdictRule]
}

// MARK: Codex

enum CoreCodexModel: String, Codable, Sendable {
    case legacy, profiles, both
}

/// A scalar config value: Go writes a boolean, a string or a number.
enum CoreFlagValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case number(Double)
}

extension CoreFlagValue: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        }
    }
}

struct CoreFlag: Codable, Equatable, Sendable {
    var key: String
    var value: CoreFlagValue
}

/// Either `{mode}` or `{granular}`.
enum CoreApprovalPolicy: Equatable, Sendable {
    case mode(String)
    /// The `[approval_policy.granular]` switches, in file order. Only booleans are kept.
    case granular([CoreFlag])
}

extension CoreApprovalPolicy: Codable {
    private enum Keys: String, CodingKey { case mode, granular }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let mode = try c.decodeIfPresent(String.self, forKey: .mode) {
            self = .mode(mode)
        } else {
            self = .granular(try c.decode([CoreFlag].self, forKey: .granular))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .mode(let mode): try c.encode(mode, forKey: .mode)
        case .granular(let flags): try c.encode(flags, forKey: .granular)
        }
    }
}

struct CoreWorkspaceWrite: Codable, Equatable, Sendable {
    @CoreNullable var networkAccess: Bool?
    var writableRoots: [String]
}

/// A `[permissions.<name>]` profile, counts only.
struct CoreCodexProfile: Codable, Equatable, Sendable {
    var name: String
    var filesystemEntries: Int
    var networkEntries: Int
    var networkFlags: [CoreFlag]
}

struct CoreCodexProject: Codable, Equatable, Sendable {
    var path: String
    @CoreNullable var trustLevel: String?
}

struct CoreCodexRulesSummary: Codable, Equatable, Sendable {
    var files: Int
    var allow: Int
    var prompt: Int
    var forbidden: Int
    var other: Int
    /// Go only: `.rules` files that exist but could not be read, so they are not in the counts.
    var unreadable: Int
    /// Go only: the rules folder could not be listed.
    var folderNotReadable: Bool
}

struct CoreCodexPermissions: Codable, Equatable, Sendable {
    var present: Bool
    var model: CoreCodexModel
    var unrestricted: Bool
    var warnings: [String]
    @CoreNullable var approvalPolicy: CoreApprovalPolicy?
    @CoreNullable var sandboxMode: String?
    @CoreNullable var sandboxWorkspaceWrite: CoreWorkspaceWrite?
    @CoreNullable var defaultPermissions: String?
    @CoreNullable var approvalsReviewer: String?
    var profiles: [CoreCodexProfile]
    var projects: [CoreCodexProject]
    var rules: CoreCodexRulesSummary
    /// Go only: `config.toml` may exist but cannot be read, so every setting above is unknown, not the defaults.
    var notReadable: Bool
    /// Go only: `config.toml` lines the reader could not make sense of.
    var skippedLines: Int
}

// MARK: Snapshot and results

/// `rules.snapshot`: everything the Rules screen shows for one scope.
struct CoreRulesSnapshot: Codable, Equatable, Sendable {
    var projectDirs: [String]
    var globalRuleCount: Int
    /// The selection actually read: global when the asked project is not listed.
    var scope: CoreRuleScope
    @CoreNullable var dir: String?
    var fileLabel: String
    /// False when the scope's file does not exist yet.
    var exists: Bool
    /// With the settings file's absolute path replaced by `fileLabel`.
    var problems: [String]
    var rules: [CoreRule]
    var grid: [CoreCapabilityCell]
    var codex: CoreCodexPermissions
    /// Go only: the scope's file or project folder cannot be looked at, so `rules` and `grid` are unknown, not empty.
    var notReadable: Bool
    /// Go only: the same for the global file, which `globalRuleCount` counts.
    var globalNotReadable: Bool
}

/// `rules.setCapability`: `entry` is null (not an error) when the file already holds that.
struct CoreSetCapabilityResult: Codable, Equatable, Sendable {
    @CoreNullable var entry: CoreJournalEntry?
}

/// `rules.check`: `message` is the sentence a write would refuse with.
struct CoreRuleCheck: Codable, Equatable, Sendable {
    var valid: Bool
    @CoreNullable var message: String?
}
