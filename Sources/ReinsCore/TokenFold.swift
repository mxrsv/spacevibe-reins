import Foundation

// Folds one session log into token rows per UTC hour and model, for the Tokens tab's ledger. Read-only: it parses
// recorded usage and keeps no log text, only the model name and a project name derived from the working directory.
// Counting is shared with Activity (TokenCount.swift), so a session's cost there and its tokens here agree.

/// Token counts with one meaning for both CLIs. `input` is uncached input: Codex logs cached tokens inside its input,
/// so they are subtracted (spec, Tab: Tokens).
public struct TokenCounts: Codable, Equatable, Hashable, Sendable {
    public var input = 0
    public var cacheWrite = 0
    /// The part of `cacheWrite` written with a one-hour lifetime (Claude only). It is priced apart, like Activity's
    /// estimate, and never shown as a kind of its own.
    public var cacheWrite1h = 0
    public var cacheRead = 0
    public var output = 0

    public init(input: Int = 0, cacheWrite: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input; self.cacheWrite = cacheWrite; self.cacheWrite1h = cacheWrite1h; self.cacheRead = cacheRead; self.output = output
    }

    public static let zero = TokenCounts()

    /// All four kinds.
    public var total: Int { input + cacheWrite + cacheRead + output }
    /// "New only": input, cache writes and output; everything but cache reads.
    public var fresh: Int { total - cacheRead }
    public var isEmpty: Bool { total == 0 }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, cacheWrite: a.cacheWrite + b.cacheWrite, cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h,
                    cacheRead: a.cacheRead + b.cacheRead, output: a.output + b.output)
    }

    public static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }

    /// The larger of each kind: a rescan of a changed log never lowers a count it already had.
    func atLeast(_ other: TokenCounts) -> TokenCounts {
        TokenCounts(input: max(input, other.input), cacheWrite: max(cacheWrite, other.cacheWrite), cacheWrite1h: max(cacheWrite1h, other.cacheWrite1h),
                    cacheRead: max(cacheRead, other.cacheRead), output: max(output, other.output))
    }

    init(_ usage: Pricing.Usage) {
        func whole(_ d: Double) -> Int { d.isFinite && d > 0 ? Int(min(d, 9e15).rounded()) : 0 }
        self.init(input: whole(usage.input), cacheWrite: whole(usage.cacheWrite), cacheWrite1h: whole(min(usage.cacheWriteLong, usage.cacheWrite)),
                  cacheRead: whole(usage.cacheRead), output: whole(usage.output))
    }

    /// The counts in the shape `Pricing` prices.
    var usage: Pricing.Usage {
        Pricing.Usage(input: Double(input), output: Double(output), cacheWrite: Double(cacheWrite), cacheWriteLong: Double(cacheWrite1h), cacheRead: Double(cacheRead))
    }
}

/// Tokens of one model in one UTC hour of one log.
public struct TokenRow: Codable, Equatable, Hashable, Sendable {
    /// Start of the UTC hour, in whole hours since 1970.
    public var hour: Int
    public var model: String
    public var counts: TokenCounts

    public init(hour: Int, model: String, counts: TokenCounts) {
        self.hour = hour; self.model = model; self.counts = counts
    }
}

/// What one log yields: its CLI, the session it belongs to, a project name, and rows sorted by hour then model.
public struct TokenLog: Codable, Equatable, Sendable {
    public var cli: InventoryCLI
    /// A subagent log belongs to the session of the folder that holds `subagents/`; any other log is its own session.
    public var session: String
    /// The repo name from the log's working directory (a worktree slug is never used); nil when the log names none.
    public var project: String?
    public var rows: [TokenRow]

    public init(cli: InventoryCLI, session: String, project: String?, rows: [TokenRow]) {
        self.cli = cli; self.session = session; self.project = project; self.rows = rows
    }
}

struct TokenFold {
    static let msPerHour = 3_600_000.0
    static let unknownModel = "unknown"

    let cli: InventoryCLI
    /// Used when no line of the log carries a timestamp: the log's modification time, in ms since 1970.
    let fallbackMs: Double
    private var claude = ClaudeUsageCounter()
    private var codex = CodexUsageCounter()
    private var model = TokenFold.unknownModel
    private var cwd: String?
    private var worktreeOriginal: String?
    private var lastHour: Int?
    /// Usage seen before any timestamp: it goes to the first timestamped hour, or to `fallbackMs` when none follows.
    private var untimed = OrderedMap<Pricing.Usage>()
    private var buckets: [Bucket: Pricing.Usage] = [:]

    private struct Bucket: Hashable {
        var hour: Int
        var model: String
    }

    init(cli: InventoryCLI, fallbackMs: Double) {
        self.cli = cli
        self.fallbackMs = fallbackMs
    }

    static func hour(ofMs ms: Double) -> Int { Int((ms / msPerHour).rounded(.down)) }

    mutating func fold(_ line: Data) {
        if cli == .claude { foldClaude(line) } else { foldCodex(line) }
    }

    /// Only assistant records with usage and the worktree record are parsed; every other line is skipped by a byte search.
    private mutating func foldClaude(_ line: Data) {
        let assistant = ActivityText.contains(line, "\"type\":\"assistant\"") && ActivityText.contains(line, "\"usage\"")
        let worktree = !assistant && ActivityText.contains(line, "\"type\":\"worktree-state\"")
        guard assistant || worktree, let doc = try? OrderedJSON(data: line), doc.root.objectValue != nil else { return }
        let r = doc.root
        noteCwd(r.field("cwd")?.stringValue)
        switch r.field("type")?.stringValue {
        case "worktree-state":
            if let original = r.field("worktreeSession").field("originalCwd")?.stringValue { worktreeOriginal = original }
        case "assistant":
            noteTime(r)
            let m = r.field("message")
            if let name = m.field("model")?.stringValue, name != "<synthetic>" { model = name }
            guard let u = m.field("usage"), u.truthy else { return }
            let messageId = m.field("id")?.stringValue ?? r.field("uuid")?.stringValue ?? "undefined"
            record(claude.add(u, key: "\(model):\(messageId)"))
        default: break
        }
    }

    private mutating func foldCodex(_ line: Data) {
        let wanted = ActivityText.contains(line, "\"type\":\"token_count\"") || ActivityText.contains(line, "\"type\":\"turn_context\"")
            || ActivityText.contains(line, "\"type\":\"session_meta\"")
        guard wanted, let doc = try? OrderedJSON(data: line), doc.root.objectValue != nil else { return }
        let r = doc.root
        let p = r.field("payload") ?? .object([])
        switch r.field("type")?.stringValue {
        case "session_meta":
            noteCwd(p.field("cwd")?.stringValue)
        case "turn_context":
            if let name = p.field("model")?.stringValue, !name.isEmpty { model = name }
            noteCwd(p.field("cwd")?.stringValue)
        case "event_msg":
            guard p.field("type")?.stringValue == "token_count" else { return }
            noteTime(r)
            if let delta = codex.add(p.field("info")) { record(delta) }
        default: break
        }
    }

    private mutating func noteCwd(_ value: String?) {
        if let value, !value.isEmpty, cwd == nil { cwd = value }
    }

    /// A line without a timestamp keeps the hour of the last one that had it.
    private mutating func noteTime(_ r: JSONValue) {
        guard let ms = r.field("timestamp")?.stringValue.flatMap(ActivityText.parseTimestamp), ms > 0 else { return }
        let hour = Self.hour(ofMs: ms)
        if lastHour == nil { flushUntimed(into: hour) }
        lastHour = hour
    }

    private mutating func record(_ usage: Pricing.Usage) {
        guard let hour = lastHour else {
            var pending = untimed[model] ?? Pricing.Usage()
            pending.add(usage)
            untimed[model] = pending
            return
        }
        buckets[Bucket(hour: hour, model: model), default: Pricing.Usage()].add(usage)
    }

    private mutating func flushUntimed(into hour: Int) {
        for (name, usage) in untimed.entries { buckets[Bucket(hour: hour, model: name), default: Pricing.Usage()].add(usage) }
        untimed.removeAll()
    }

    /// The rows of the log; buckets that hold no token are dropped.
    mutating func finish(session: String, memo: ProjectNameMemo? = nil) -> TokenLog {
        if !untimed.isEmpty { flushUntimed(into: Self.hour(ofMs: fallbackMs)) }
        let rows = buckets.map { TokenRow(hour: $0.key.hour, model: $0.key.model, counts: TokenCounts($0.value)) }
            .filter { !$0.counts.isEmpty }
            .sorted { ($0.hour, $0.model) < ($1.hour, $1.model) }
        return TokenLog(cli: cli, session: session, project: projectName(cwd, hint: worktreeOriginal, memo: memo), rows: rows)
    }

    /// Folds the log at `url` (`.jsonl` or `.jsonl.zst`, through `LogFiles`). Nil when it cannot be read to the end.
    static func read(_ url: URL, cli: InventoryCLI, fallbackMs: Double, maxLineBytes: Int, memo: ProjectNameMemo? = nil) -> TokenLog? {
        var fold = TokenFold(cli: cli, fallbackMs: fallbackMs)
        do {
            try LogFiles.forEachLine(at: url, maxLineBytes: maxLineBytes) { fold.fold($0) }
        } catch {
            return nil
        }
        return fold.finish(session: UsageScanner.sessionId(url), memo: memo)
    }
}
