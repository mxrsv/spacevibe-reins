import Foundation

// Activity tab data: running sessions of both CLIs, failed commands and file history. Port of Node activity (git b58269d).
// Read-only on logs; it never executes a recorded command or hook (AGENTS.md R4). All process access goes through
// `ProcessAdapter`. Field names in `ActivityReport.jsonObject` are the Node output's, so the golden compares directly.

public enum ActivitySessionState: String, Sendable {
    case running, waiting, idle, ended, unmeasurable
}

/// Reasons a state cannot be known. The wording is Activity's own: the plan only lists the facts.
public enum ActivityReason: String, Sendable, CaseIterable {
    case codexNoRollout = "codex-no-rollout"
    case codexToolSilent = "codex-tool-silent"
    case claudePromptVsBusy = "claude-prompt-vs-busy"
    case claudeUnknownStatus = "claude-unknown-status"
    case codexHookRuns = "codex-hook-runs"

    public var text: String {
        switch self {
        case .codexNoRollout: return "Codex writes no log until the first prompt is sent, so this session cannot be read yet."
        case .codexToolSilent: return "Codex logs nothing while a tool runs and does not record approval waits, so a long command and a wait for approval look the same."
        case .claudePromptVsBusy: return "Claude Code does not record permission prompts, so a long tool run and a wait for approval look the same."
        case .claudeUnknownStatus: return "The Claude Code status file reports a status this app does not know."
        case .codexHookRuns: return "Codex does not log hook runs, so failed hooks are not shown for Codex."
        }
    }
}

public struct ActivityTool: Equatable, Sendable {
    public var name: String
    public var target: String
}

public struct ActivityCost: Equatable, Sendable {
    public var usd: Double
    /// Always true: an API-equivalent estimate, not what a subscription charges.
    public var estimated = true
}

public struct ActivitySession: Equatable, Sendable, Identifiable {
    public var cli: InventoryCLI
    /// Claude: the session id. Codex: the thread id, or `pid:<n>:<start-ms>` before the first prompt.
    /// An unknown process start uses `pid:<n>:unknown` and cannot authorize Stop.
    public var id: String
    public var title: String
    public var project: String?
    public var pid: Int
    public var state: ActivitySessionState
    public var stateReason: String
    /// Set when `state` is `.unmeasurable`.
    public var reasonCode: ActivityReason?
    public var currentTool: ActivityTool?
    /// Since the session started, in milliseconds.
    public var ageMs: Double?
    /// Since the transcript (or a subagent transcript) was last written. This is the age to show: Claude's `statusUpdatedAt` goes stale.
    public var lastWriteAgoMs: Double?
    public var cost: ActivityCost?
    public var costNote: String?
}

/// What cannot be measured, listed even when no session is live.
public struct ActivityLimit: Equatable, Sendable {
    public var cli: InventoryCLI
    public var code: ActivityReason
    public var text: String
}

public struct ActivityStats: Equatable, Sendable {
    /// Logs folded in this read.
    public var logs: Int
    /// Logs read from their tail only, so older records are missing and their cost is not estimated.
    public var truncated: Int
}

public struct ActivityReport: Equatable, Sendable {
    public var sessions: [ActivitySession]
    public var failures: [ActivityFailure]
    public var files: [ActivityFileRow]
    public var unmeasurable: [ActivityLimit]
    public var stats: ActivityStats
}

public struct ActivityOptions: Sendable {
    public var historyDays = 14
    public var maxHistoryFiles = 200
    public var historyTailBytes = 4 * 1024 * 1024
    public var liveTailBytes = 64 * 1024 * 1024
    public var failureLimit = 200
    public var fileLimit = 300
    /// An open tool call with no log write for this long is ambiguous (running, or waiting for approval).
    public var toolQuietMs = 30_000.0
    /// A dead Claude session is listed as "ended" for this long.
    public var endedKeepMs = 15.0 * 60_000

    public init() {}
}

public enum ActivityDefaults {
    public static let toolQuietMs = ActivityOptions().toolQuietMs
    public static let endedKeepMs = ActivityOptions().endedKeepMs
}

/// Reads session logs incrementally. One engine keeps the read offsets and folded state of every log between calls, so a
/// repeated `readActivity` reads only the bytes appended since. It is an actor: reads run off the main thread and never overlap.
public actor ActivityEngine {
    private final class CacheEntry {
        let reader: any LogReader
        var state: ActivityLogState
        var truncated = false

        init(reader: any LogReader, state: ActivityLogState) {
            self.reader = reader
            self.state = state
        }
    }

    private struct LogFile {
        var url: URL
        var cli: InventoryCLI
        var session: String
        var sub: Bool
        var mtimeMs: Double
        var path: String { url.path }
    }

    private struct LogIndex {
        var files: [LogFile] = []
        var claudeMain: [String: LogFile] = [:]
        var claudeSubs: [String: [LogFile]] = [:]
        var codexById: [String: LogFile] = [:]
    }

    private struct ClaudeLive {
        var status: JSONValue
        var pid: Int
        var sessionId: String
        var alive: Bool
        var main: LogFile?
        var subs: [LogFile]
    }

    /// What the Codex builder reads from one `readActivity` call. Nested because `LogIndex` and `CacheEntry` are private to the actor.
    private struct ReadContext {
        var roots: Roots
        var nowMs: Double
        var options: ActivityOptions
        var proc: any ProcessAdapter
        var memo: ProjectNameMemo
        var index: LogIndex
        var foldedByPath: [String: CacheEntry]
    }

    private var cache: [String: CacheEntry] = [:]
    private static let maxSubagentLogs = 50
    private static let childHeadBytes = 64 * 1024
    private static let indexTailBytes = 1024 * 1024
    private static let dayMs = 86_400_000.0

    public init() {}

    // MARK: Log discovery

    private func listLogs(_ roots: Roots) -> LogIndex {
        var index = LogIndex()
        let claudeBase = roots.claude.logs.pathComponents.count
        for url in LogFiles.walk(roots.claude.logs) {
            let rel = Array(url.pathComponents.dropFirst(claudeBase))
            let sub = rel.count >= 4 && rel[2] == "subagents"
            let session = sub ? rel[1] : LogFiles.baseName(url)
            guard let mtime = Self.mtimeMs(url.path) else { continue }
            let file = LogFile(url: url, cli: .claude, session: session, sub: sub, mtimeMs: mtime)
            index.files.append(file)
            if sub { index.claudeSubs[session, default: []].append(file) } else if rel.count == 2 { index.claudeMain[session] = file }
        }
        for url in LogFiles.walk(roots.codex.logs) {
            guard url.lastPathComponent.hasPrefix("rollout-"), let id = Self.threadId(in: url), let mtime = Self.mtimeMs(url.path) else { continue }
            let file = LogFile(url: url, cli: .codex, session: id, sub: false, mtimeMs: mtime)
            index.files.append(file)
            index.codexById[id] = file
        }
        return index
    }

    /// The uuid that ends a rollout's name: `rollout-2026-11-02T09-00-01-<uuid>.jsonl[.zst]`.
    private static func threadId(in url: URL) -> String? {
        let base = LogFiles.baseName(url)
        guard base.utf8.count >= 36 else { return nil }
        let tail = String(base.suffix(36))
        let groups = tail.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
        let hex = Set("0123456789abcdef")
        return tail.allSatisfy { $0 == "-" || hex.contains($0) } ? tail : nil
    }

    static func mtimeMs(_ path: String) -> Double? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let t = modificationTime(info)
        return ActivityText.boundedTimestamp(Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6)
    }

    private static func readJSON(_ url: URL) -> JSONValue? {
        guard let data = try? Data(contentsOf: url), let doc = try? OrderedJSON(data: data), doc.root.objectValue != nil else { return nil }
        return doc.root
    }

    private static func readHead(_ path: String, bytes: Int) -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)) ?? Data()
    }

    /// Codex subagent rollouts name their parent thread in session_meta (the first 64 KB is enough).
    private static func isChildRollout(_ path: String) -> Bool {
        let head = readHead(path, bytes: childHeadBytes)
        if ActivityText.contains(head, "\"source\":{\"subagent\"") { return true }
        let key = Array("\"parent_thread_id\":\"".utf8)
        let bytes = [UInt8](head)
        var i = 0
        while i + key.count < bytes.count {
            if bytes[i] == key[0], bytes[i..<(i + key.count)].elementsEqual(key) {
                let c = bytes[i + key.count]
                if (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66) { return true }
            }
            i += 1
        }
        return false
    }

    private static func codexThreadNames(_ roots: Roots) -> [String: String] {
        let path = roots.codex.root.appendingPathComponent("session_index.jsonl").path
        var names: [String: String] = [:]
        guard let handle = FileHandle(forReadingAtPath: path) else { return names }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return names }
        let start = size > UInt64(indexTailBytes) ? size - UInt64(indexTailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return names }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines {
            guard let doc = try? OrderedJSON(data: Data(line)), let id = doc.root["id"]?.stringValue, !id.isEmpty,
                  let name = doc.root["thread_name"]?.stringValue else { continue }
            names[id] = name
        }
        return names
    }

    // MARK: Incremental folding

    private func advance(_ f: LogFile, maxBytes: Int) throws -> CacheEntry? {
        let entry: CacheEntry
        if let existing = cache[f.path] {
            entry = existing
        } else {
            let reader: any LogReader = LogFiles.isCompressed(f.url)
                ? CompressedLogReader(url: f.url, maxBytes: maxBytes)
                : TailReader(url: f.url, maxBytes: maxBytes, requireObjectShape: false)
            entry = CacheEntry(reader: reader, state: ActivityLogState(cli: f.cli))
            cache[f.path] = entry
        }
        let result = try entry.reader.read({ line in ActivityFold.fold(entry.state, line) }, onReset: { entry.state = ActivityLogState(cli: f.cli) })
        if result.missing {
            cache[f.path] = nil
            return nil
        }
        entry.truncated = result.truncated
        return entry
    }

    // MARK: Cost

    private static func costFor(_ entries: [CacheEntry]) -> (cost: ActivityCost?, note: String?) {
        if entries.contains(where: { $0.truncated }) { return (nil, "The log is too large to read in full, so no estimate.") }
        var merged = OrderedMap<Pricing.Usage>()
        for entry in entries {
            for (model, m) in entry.state.metrics.entries {
                var o = merged[model] ?? Pricing.Usage()
                o.input += m.input
                o.output += m.output
                o.cacheWrite += m.cacheWrite
                o.cacheWriteLong += m.cacheWriteLong
                o.cacheRead += m.cacheRead
                merged[model] = o
            }
        }
        switch Pricing.estimate(merged.entries.map { ($0.key, $0.value) }) {
        case .usd(let usd): return (ActivityCost(usd: usd), nil)
        case .note(let note): return (nil, note)
        }
    }

    // MARK: States

    private struct StateInfo {
        var state: ActivitySessionState
        var reason: ActivityReason?
        var text: String
        var tool: ActivityTool?

        static func unmeasurable(_ code: ActivityReason, tool: ActivityTool? = nil) -> StateInfo {
            StateInfo(state: .unmeasurable, reason: code, text: code.text, tool: tool)
        }
    }

    private static func lastPending(_ st: ActivityLogState?) -> ActivityTool? {
        st?.pending.last.map { ActivityTool(name: $0.name, target: $0.target) }
    }

    private static func claudeState(alive: Bool, status: String?, st: ActivityLogState?, lastWriteAgoMs: Double, toolQuietMs: Double) -> StateInfo {
        if !alive { return StateInfo(state: .ended, reason: nil, text: "The process has exited.", tool: nil) }
        let tool = lastPending(st)
        if status == "idle" { return StateInfo(state: .idle, reason: nil, text: "Turn finished, waiting for the next prompt.", tool: nil) }
        if status == "shell" { return StateInfo(state: .running, reason: nil, text: "Running a shell command.", tool: tool) }
        if status != "busy" { return .unmeasurable(.claudeUnknownStatus) }
        if let st, !st.questions.isEmpty { return StateInfo(state: .waiting, reason: nil, text: "Waiting for your answer to a question.", tool: tool) }
        if tool != nil, lastWriteAgoMs > toolQuietMs { return .unmeasurable(.claudePromptVsBusy, tool: tool) }
        return StateInfo(state: .running, reason: nil, text: tool != nil ? "A tool call is open." : "Turn in progress.", tool: tool)
    }

    private static func codexState(st: ActivityLogState, lastWriteAgoMs: Double, toolQuietMs: Double) -> StateInfo {
        let tool = lastPending(st)
        if st.status == "busy" {
            if !st.questions.isEmpty { return StateInfo(state: .waiting, reason: nil, text: "Waiting for your answer to a question.", tool: tool) }
            if tool != nil, lastWriteAgoMs > toolQuietMs { return .unmeasurable(.codexToolSilent, tool: tool) }
            return StateInfo(state: .running, reason: nil, text: tool != nil ? "A tool call is open." : "Turn in progress.", tool: tool)
        }
        let text = st.status == "idle" ? "Turn finished or aborted, waiting for the next prompt." : "No turn recorded yet."
        return StateInfo(state: .idle, reason: nil, text: text, tool: nil)
    }

    static let limitCodes: [(InventoryCLI, ActivityReason)] = [
        (.claude, .claudePromptVsBusy), (.codex, .codexToolSilent), (.codex, .codexNoRollout), (.codex, .codexHookRuns),
    ]

    // MARK: readActivity

    /// - Parameters:
    ///   - roots: from `Roots.resolve()`.
    ///   - now: every age is computed against it.
    ///   - proc: the process adapter; tests pass a fake.
    public func readActivity(roots: Roots, now: Date = Date(), proc: any ProcessAdapter, options: ActivityOptions = ActivityOptions()) async -> ActivityReport {
        let nowMs = now.timeIntervalSince1970 * 1000
        let index = listLogs(roots)
        let memo = ProjectNameMemo()

        // 1. Live processes.
        let (claudeLive, threads) = await liveProcesses(roots: roots, index: index, proc: proc)
        let codexPids = Set(threads.filter { $0.threadId != nil }.map(\.pid))

        // 2. Which logs to fold: live ones in full, the rest only if recent.
        var live = Set<String>()
        for c in claudeLive {
            if let main = c.main { live.insert(main.path) }
            for f in c.subs.prefix(Self.maxSubagentLogs) { live.insert(f.path) }
        }
        for t in threads {
            if let id = t.threadId, let f = index.codexById[id] { live.insert(f.path) }
        }
        let cutoff = nowMs - Double(options.historyDays) * Self.dayMs
        let recent = index.files.enumerated().filter { $0.element.mtimeMs >= cutoff && !live.contains($0.element.path) }
            .sorted { $0.element.mtimeMs != $1.element.mtimeMs ? $0.element.mtimeMs > $1.element.mtimeMs : $0.offset < $1.offset }
            .prefix(options.maxHistoryFiles).map(\.element)
        let targets = index.files.filter { live.contains($0.path) } + recent
        var folded: [(file: LogFile, entry: CacheEntry)] = []
        var foldedByPath: [String: CacheEntry] = [:]
        for f in targets {
            // An unreadable log stays out of the lists.
            if let entry = try? advance(f, maxBytes: live.contains(f.path) ? options.liveTailBytes : options.historyTailBytes) {
                folded.append((f, entry))
                foldedByPath[f.path] = entry
            }
        }
        let wanted = Set(targets.map(\.path))
        for path in cache.keys where !wanted.contains(path) { cache[path] = nil }

        // 3. Sessions.
        let ctx = ReadContext(roots: roots, nowMs: nowMs, options: options, proc: proc, memo: memo, index: index, foldedByPath: foldedByPath)
        var sessions = claudeSessions(claudeLive, foldedByPath: foldedByPath, nowMs: nowMs, options: options, memo: memo)
            + (await codexSessions(threads, codexPids: codexPids, ctx))
        sessions = sessions.enumerated().sorted { a, b in
            if a.element.cli != b.element.cli { return a.element.cli.rawValue < b.element.cli.rawValue }
            let ka = a.element.lastWriteAgoMs ?? .infinity, kb = b.element.lastWriteAgoMs ?? .infinity
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)

        // 4. Cross-session lists.
        let sessionByPath = Dictionary(index.files.map { ($0.path, $0.session) }, uniquingKeysWith: { first, _ in first })
        let logs = folded.map { item -> ActivityLogEntry in
            let st = item.entry.state
            return ActivityLogEntry(state: st, session: "\(st.cli.rawValue):\(sessionByPath[item.file.path] ?? item.file.path)", project: projectName(st.cwd, hint: st.worktreeOriginal, memo: memo))
        }
        return ActivityReport(
            sessions: sessions,
            failures: ActivityGroups.groupFailures(logs, limit: options.failureLimit),
            files: ActivityGroups.groupFiles(logs, limit: options.fileLimit),
            unmeasurable: Self.limitCodes.map { ActivityLimit(cli: $0.0, code: $0.1, text: $0.1.text) },
            stats: ActivityStats(logs: folded.count, truncated: folded.filter { $0.entry.truncated }.count)
        )
    }

    /// Claude status files checked against the process table, and the Codex threads that live processes hold.
    private func liveProcesses(roots: Roots, index: LogIndex, proc: any ProcessAdapter) async -> (claudeLive: [ClaudeLive], threads: [CodexThread]) {
        var claudeLive: [ClaudeLive] = []
        let sessionsDir = roots.claude.root.appendingPathComponent("sessions", isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: sessionsDir.path)) ?? []).filter(Self.isStatusFileName).sorted()
        for name in names {
            guard let s = Self.readJSON(sessionsDir.appendingPathComponent(name)), let pid = s["pid"]?.integerValue,
                  let sessionId = s["sessionId"]?.stringValue else { continue }
            var alive = await proc.isAlive(pid: pid)
            if alive, let procStart = s["procStart"]?.stringValue, !procStart.isEmpty, let started = await proc.startTime(pid: pid), !started.isEmpty {
                // A reused pid has a different start time; two readings that disagree mean another process.
                if ActivityText.collapse(started) != ActivityText.collapse(procStart) { alive = false }
            }
            let subs = (index.claudeSubs[sessionId] ?? []).enumerated().sorted { a, b in
                a.element.mtimeMs != b.element.mtimeMs ? a.element.mtimeMs > b.element.mtimeMs : a.offset < b.offset
            }.map(\.element)
            claudeLive.append(ClaudeLive(status: s, pid: pid, sessionId: sessionId, alive: alive, main: index.claudeMain[sessionId], subs: subs))
        }
        let threads = await proc.codexThreads()
        return (claudeLive, threads)
    }

    /// One row per Claude status file, ended sessions older than `endedKeepMs` dropped.
    private func claudeSessions(_ claudeLive: [ClaudeLive], foldedByPath: [String: CacheEntry], nowMs: Double, options: ActivityOptions, memo: ProjectNameMemo) -> [ActivitySession] {
        var sessions: [ActivitySession] = []
        for c in claudeLive {
            let entry = c.main.flatMap { foldedByPath[$0.path] }
            let st = entry?.state
            let newestWrite = ([c.main].compactMap { $0 } + c.subs).map(\.mtimeMs).max() ?? 0
            let written = newestWrite != 0 ? newestWrite : (Self.truthyNumber(c.status["statusUpdatedAt"]) ?? Self.truthyNumber(c.status["startedAt"]) ?? nowMs)
            let lastWriteAgoMs = max(0, nowMs - written)
            if !c.alive, lastWriteAgoMs > options.endedKeepMs { continue }
            let startedAt = ActivityText.boundedTimestamp(c.status.nonNull("startedAt")?.doubleValue) ?? ActivityText.boundedTimestamp(st?.startedAt)
            let subEntries = c.subs.prefix(Self.maxSubagentLogs).compactMap { foldedByPath[$0.path] }
            let nameSource = c.status["nameSource"]?.stringValue
            let state = Self.claudeState(alive: c.alive, status: c.status["status"]?.stringValue, st: st, lastWriteAgoMs: lastWriteAgoMs, toolQuietMs: options.toolQuietMs)
            var cost: ActivityCost?
            var costNote: String?
            if let entry {
                (cost, costNote) = Self.costFor([entry] + subEntries)
            } else {
                costNote = "No transcript found for this session."
            }
            sessions.append(ActivitySession(
                cli: .claude, id: c.sessionId, title: SessionTitles.pick(
                    [st?.customTitle, st?.aiTitle, nameSource == "derived" ? nil : c.status["name"]?.stringValue, st?.firstPrompt], startedAt: startedAt, id: c.sessionId
                ),
                project: projectName(c.status["cwd"]?.stringValue ?? st?.cwd, hint: st?.worktreeOriginal, memo: memo), pid: c.pid,
                state: state.state, stateReason: state.text, reasonCode: state.reason, currentTool: state.tool,
                ageMs: Self.truthy(startedAt).map { max(0, nowMs - $0) }, lastWriteAgoMs: lastWriteAgoMs, cost: cost, costNote: costNote
            ))
        }
        return sessions
    }

    /// One row per live `codex` process; a child rollout, or a thread-less row whose pid already holds a thread, gets none.
    private func codexSessions(_ threads: [CodexThread], codexPids: Set<Int>, _ ctx: ReadContext) async -> [ActivitySession] {
        let (roots, index, foldedByPath, nowMs, options, proc, memo) = (ctx.roots, ctx.index, ctx.foldedByPath, ctx.nowMs, ctx.options, ctx.proc, ctx.memo)
        var sessions: [ActivitySession] = []
        let threadNames = Self.codexThreadNames(roots)
        for t in threads {
            let f = t.threadId.flatMap { index.codexById[$0] }
            let entry = f.flatMap { foldedByPath[$0.path] }
            if t.threadId != nil, let f {
                let child = LogFiles.isCompressed(f.url) ? (entry?.state.parent ?? false) : Self.isChildRollout(f.path)
                if child { continue }
            }
            if t.threadId == nil, codexPids.contains(t.pid) { continue }
            guard let f, let entry else {
                // The rollout does not exist yet, so the process start is the only clock.
                let processStart = await proc.startTime(pid: t.pid)
                let startedAt = ActivityText.parseProcessStart(processStart)
                sessions.append(ActivitySession(
                    cli: .codex, id: t.threadId ?? codexProcessID(pid: t.pid, start: processStart) ?? "pid:\(t.pid):unknown", title: SessionTitles.pick(
                        [t.threadId.flatMap { threadNames[$0] }], startedAt: startedAt, id: t.threadId ?? "pid \(t.pid)"
                    ),
                    project: nil, pid: t.pid, state: .unmeasurable, stateReason: ActivityReason.codexNoRollout.text, reasonCode: .codexNoRollout, currentTool: nil,
                    ageMs: startedAt.map { max(0, nowMs - $0) }, lastWriteAgoMs: nil, cost: nil, costNote: ActivityReason.codexNoRollout.text
                ))
                continue
            }
            let lastWriteAgoMs = max(0, nowMs - f.mtimeMs)
            let st = entry.state
            let state = Self.codexState(st: st, lastWriteAgoMs: lastWriteAgoMs, toolQuietMs: options.toolQuietMs)
            let (cost, costNote) = Self.costFor([entry])
            sessions.append(ActivitySession(
                cli: .codex, id: t.threadId ?? "pid:\(t.pid)", title: SessionTitles.pick([t.threadId.flatMap { threadNames[$0] }, st.firstPrompt], startedAt: st.startedAt, id: t.threadId),
                project: projectName(st.cwd, memo: memo), pid: t.pid, state: state.state, stateReason: state.text, reasonCode: state.reason, currentTool: state.tool,
                ageMs: Self.truthy(st.startedAt).map { max(0, nowMs - $0) }, lastWriteAgoMs: lastWriteAgoMs, cost: cost, costNote: costNote
            ))
        }
        return sessions
    }

    static func isStatusFileName(_ name: String) -> Bool {
        name.hasSuffix(".json") && name.count > 5 && name.dropLast(5).allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// A JSON number that is non-zero (JavaScript `||` chain).
    private static func truthyNumber(_ v: JSONValue?) -> Double? {
        guard let d = ActivityText.boundedTimestamp(v?.doubleValue), d != 0 else { return nil }
        return d
    }

    private static func truthy(_ d: Double?) -> Double? {
        guard let d = ActivityText.boundedTimestamp(d), d != 0 else { return nil }
        return d
    }
}

// MARK: - Entry points

/// One read with a fresh engine (no cache). Keep an `ActivityEngine` and call its `readActivity` to read incrementally.
public func readActivity(roots: Roots, now: Date = Date(), proc: any ProcessAdapter, options: ActivityOptions = ActivityOptions()) async -> ActivityReport {
    await ActivityEngine().readActivity(roots: roots, now: now, proc: proc, options: options)
}

extension JSONValue {
    fileprivate var integerValue: Int? {
        guard let d = doubleValue, d.isFinite, d == d.rounded(), abs(d) < 9e15 else { return nil }
        return Int(d)
    }

    fileprivate var doubleValue: Double? { numberText.flatMap { Double($0) } }

    /// The member, or nil when it is missing or null.
    fileprivate func nonNull(_ key: String) -> JSONValue? {
        guard let v = self[key], v != .null else { return nil }
        return v
    }
}

// MARK: - JSON shape of the Node output

private func orNull(_ value: Any?) -> Any { value ?? NSNull() }

extension ActivityReport {
    /// The report in the exact shape `readActivity` returns in Node (`null` for a missing value), for golden comparison and tooling.
    public var jsonObject: [String: Any] {
        [
            "sessions": sessions.map(\.jsonObject),
            "failures": failures.map(\.jsonObject),
            "files": files.map(\.jsonObject),
            "unmeasurable": unmeasurable.map { ["cli": $0.cli.rawValue, "code": $0.code.rawValue, "text": $0.text] as [String: Any] },
            "stats": ["logs": stats.logs, "truncated": stats.truncated],
        ]
    }
}

extension ActivitySession {
    public var jsonObject: [String: Any] {
        let tool: [String: Any]? = currentTool.map { ["name": $0.name, "target": $0.target] }
        let costObject: [String: Any]? = cost.map { ["usd": $0.usd, "estimated": $0.estimated] }
        return [
            "cli": cli.rawValue, "id": id, "title": title, "project": orNull(project), "pid": pid,
            "state": state.rawValue, "stateReason": stateReason, "reasonCode": orNull(reasonCode?.rawValue),
            "currentTool": orNull(tool), "ageMs": orNull(ageMs), "lastWriteAgoMs": orNull(lastWriteAgoMs),
            "cost": orNull(costObject), "costNote": orNull(costNote),
        ]
    }
}

extension ActivityFailure {
    public var jsonObject: [String: Any] {
        let hookObject: [String: Any]? = hook.map { ["hash": $0.hash, "event": $0.event] }
        return [
            "kind": kind.rawValue, "cli": cli.rawValue, "key": key, "title": title, "count": count, "exit": orNull(exit), "reason": reason,
            "projects": projects, "sessions": sessions, "first": orNull(first), "last": orNull(last), "laterPass": orNull(laterPass),
            "hook": orNull(hookObject),
        ]
    }
}

extension ActivityFileRow {
    public var jsonObject: [String: Any] {
        [
            "path": path, "label": label, "edits": edits, "sessions": sessions, "last": orNull(last),
            "clis": clis.map(\.rawValue), "projects": projects,
        ]
    }
}
