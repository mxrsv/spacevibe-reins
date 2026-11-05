import Foundation

/// The CLIs Limits reports on. Gemini CLI appears on this surface only (spec, Limits), so it is not a case of `InventoryCLI`.
public enum LimitsCLI: String, CaseIterable, Sendable {
    case claude, codex, gemini
}

/// One usage-limit window as the CLI last recorded it.
public struct LimitWindow: Equatable, Sendable {
    /// Stable within one CLI: Claude `kind` plus scope, Codex `primary` or `secondary`.
    public let id: String
    /// Length of the window in minutes (300 for five hours, 10080 for a week); nil when the record does not say.
    public let minutes: Int?
    /// What the window is limited to, such as a model name; nil for the whole plan.
    public let scope: String?
    /// Share of the window used, from 0. Can pass 100 when the CLI lets usage run over.
    public let usedPercent: Double
    public let resetsAt: Date
    /// False when the CLI marks the window as not applying right now (Claude `is_active`).
    public let active: Bool

    public init(id: String, minutes: Int?, scope: String?, usedPercent: Double, resetsAt: Date, active: Bool) {
        self.id = id
        self.minutes = minutes
        self.scope = scope
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.active = active
    }

    /// After its reset the recorded share no longer describes the window: it reads as unknown, never as 0 (spec, Limits).
    public func isCurrent(at now: Date) -> Bool { resetsAt > now }
}

/// What one CLI's files say about its usage limits.
public struct CLILimits: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case claudeCache, claudeStatusline }
    public enum State: Equatable, Sendable {
        /// Windows from the newest record, taken at `at`.
        case measured(at: Date, windows: [LimitWindow])
        /// Installed, but no limit record on disk yet: no Codex turn that logged one, no Claude Code usage fetch, an API-key login.
        case notRecorded
        /// A record exists in a shape the app does not know, or could not be read. Carries no file content (S-R3).
        case unreadable
        /// The CLI keeps no limit on disk at all (Gemini CLI).
        case notMeasurable
        case notInstalled
    }

    public let cli: LimitsCLI
    public let state: State
    /// The plan the record names (Codex `plan_type`), nil when it names none.
    public let plan: String?
    public let source: Source?

    public init(cli: LimitsCLI, state: State, plan: String? = nil, source: Source? = nil) {
        self.cli = cli
        self.state = state
        self.plan = plan
        self.source = source
    }
}

/// Usage limits read from local files only: no request, no credential, no CLI started (spec, Limits; S-R4, S-R5).
public enum Limits {
    /// Claude Code, Codex and Gemini CLI, in that order. Blocking file reads; call it off the main thread.
    public static func read(_ roots: Roots, now: Date = Date()) -> [CLILimits] {
        [LimitsClaudeStatusline.read(roots, now: now), LimitsCodexLogs.read(roots), gemini(roots)]
    }

    static func gemini(_ roots: Roots) -> CLILimits {
        CLILimits(cli: .gemini, state: isDirectory(roots.gemini) ? .notMeasurable : .notInstalled)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}

extension JSONValue {
    /// The member, or nil for a missing key or JSON null. Named apart from Activity's file-private `field`.
    func limitsMember(_ key: String) -> JSONValue? {
        guard let value = self[key], value != .null else { return nil }
        return value
    }

    var limitsNumber: Double? { numberText.flatMap { Double($0) }.flatMap { $0.isFinite ? $0 : nil } }
}
