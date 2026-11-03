import Foundation
import Testing
@testable import ReinsCore

// Activity tests. Every log, status file and lock is generated inside a TempHome (REINS_TEST=1 makes Roots refuse the real
// home); ps, lsof and kill are replaced by FakeProcess. Nothing here reads the real ~/.claude or ~/.codex.

/// A process adapter that replays a fixed process list and records what it was asked to terminate.
final class FakeProcess: ProcessAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var aliveSet: Set<Int>
    private let starts: [Int: String]
    private let threads: [CodexThread]
    private var killedPids: [Int] = []
    private let terminateError: ProcessSignalError?
    private let ignoresSignal: Bool

    init(alive: [Int] = [], starts: [Int: String] = [:], threads: [CodexThread] = [], terminateError: ProcessSignalError? = nil, ignoresSignal: Bool = false) {
        aliveSet = Set(alive)
        self.starts = starts
        self.threads = threads
        self.terminateError = terminateError
        self.ignoresSignal = ignoresSignal
    }

    /// From the JSON the golden script writes: `{ alive: [pid], starts: { "pid": "lstart" }, threads: [{ pid, threadId|null }] }`.
    convenience init(spec: [String: Any]) {
        let alive = (spec["alive"] as? [Int]) ?? []
        var starts: [Int: String] = [:]
        for (key, value) in (spec["starts"] as? [String: String]) ?? [:] { if let pid = Int(key) { starts[pid] = value } }
        let threads = ((spec["threads"] as? [[String: Any]]) ?? []).map { CodexThread(pid: $0["pid"] as? Int ?? 0, threadId: $0["threadId"] as? String) }
        self.init(alive: alive, starts: starts, threads: threads)
    }

    var killed: [Int] { lock.withLock { killedPids } }

    func isAlive(pid: Int) async -> Bool { lock.withLock { aliveSet.contains(pid) } }

    func startTime(pid: Int) async -> String? { starts[pid] }

    func codexThreads() async -> [CodexThread] { threads }

    func terminate(pid: Int) async throws {
        if let terminateError { throw terminateError }
        lock.withLock {
            killedPids.append(pid)
            if !ignoresSignal { aliveSet.remove(pid) }
        }
    }
}

// MARK: - Builders

let activityNowMs = 1_793_620_800_000.0 // 2026-11-02T12:00:00Z
let activityNow = Date(timeIntervalSince1970: activityNowMs / 1000)

func activityIso(_ ms: Double) -> String { ActivityText.isoString(ms) }
func activityMinutes(_ minutes: Double) -> Double { activityNowMs - minutes * 60_000 }
func activityUuid(_ n: Int) -> String { "00000000-0000-4000-8000-" + String(format: "%012d", n) }
func activitySid(_ n: Int) -> String { String(repeating: "a", count: max(0, 8 - String(n).count)) + String(n) + "-0000-4000-8000-000000000000" }

func activityJSON(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

struct ClaudeRecords {
    let cwd: String
    let session: String

    func user(_ text: String, _ at: Double) -> [String: Any] {
        ["type": "user", "timestamp": activityIso(at), "cwd": cwd, "sessionId": session, "message": ["role": "user", "content": text]]
    }

    func tool(_ id: String, _ name: String, _ input: [String: Any], _ at: Double, model: String = "claude-sonnet-4-6", usage: [String: Any]? = nil, messageId: String? = nil) -> [String: Any] {
        var message: [String: Any] = ["id": messageId ?? "msg-\(id)", "model": model, "content": [["type": "tool_use", "id": id, "name": name, "input": input]]]
        if let usage { message["usage"] = usage }
        return ["type": "assistant", "timestamp": activityIso(at), "cwd": cwd, "sessionId": session, "message": message]
    }

    func result(_ id: String, _ text: String, isError: Bool, _ at: Double) -> [String: Any] {
        ["type": "user", "timestamp": activityIso(at), "cwd": cwd, "sessionId": session,
         "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "is_error": isError, "content": text]]]]
    }

    func hookFail(_ n: Int, _ event: String, _ command: String, _ at: Double) -> [String: Any] {
        ["type": "attachment", "uuid": activityUuid(n), "timestamp": activityIso(at), "cwd": cwd, "sessionId": session,
         "attachment": ["type": "hook_non_blocking_error", "hookEvent": event, "hookName": event, "command": command, "exitCode": 1, "stderr": "check failed\nsecond line", "toolUseID": "tu-\(n)"]]
    }
}

struct CodexRecords {
    let id: String

    private func rec(_ at: Double, _ type: String, _ payload: [String: Any]) -> [String: Any] {
        ["timestamp": activityIso(at), "type": type, "payload": payload]
    }

    func meta(_ at: Double, _ cwd: String, extra: [String: Any] = [:]) -> [String: Any] {
        rec(at, "session_meta", ["id": id, "cwd": cwd, "timestamp": activityIso(at), "source": "cli"].merging(extra) { $1 })
    }
    func model(_ at: Double, _ model: String) -> [String: Any] { rec(at, "turn_context", ["model": model]) }
    func started(_ at: Double) -> [String: Any] { rec(at, "event_msg", ["type": "task_started", "turn_id": "t"]) }
    func done(_ at: Double) -> [String: Any] { rec(at, "event_msg", ["type": "task_complete", "turn_id": "t"]) }
    func aborted(_ at: Double) -> [String: Any] { rec(at, "event_msg", ["type": "turn_aborted", "turn_id": "t"]) }
    func say(_ at: Double, _ text: String) -> [String: Any] {
        rec(at, "event_msg", ["type": "item_completed", "item": ["type": "UserMessage", "id": "u\(Int(at))", "content": [["type": "text", "text": text]]]])
    }
    func call(_ at: Double, _ callId: String, _ name: String, _ args: [String: Any]) -> [String: Any] {
        rec(at, "response_item", ["type": "function_call", "call_id": callId, "name": name, "arguments": activityJSON(args)])
    }
    func exec(_ at: Double, _ n: Int, _ command: String, _ exit: Int, _ output: String = "") -> [String: Any] {
        rec(at, "event_msg", ["type": "item_completed", "item": ["type": "CommandExecution", "id": "ce\(n)", "command": ["/bin/zsh", "-lc", command], "cwd": "/work", "exit_code": exit, "aggregated_output": output]])
    }
    func patch(_ at: Double, _ n: Int, _ paths: [String], status: String = "completed") -> [String: Any] {
        var changes: [String: Any] = [:]
        for p in paths { changes[p] = ["type": "update", "unified_diff": ""] }
        return rec(at, "event_msg", ["type": "item_completed", "item": ["type": "FileChange", "id": "fc\(n)", "status": status, "changes": changes]])
    }
    func tokens(_ at: Double, _ input: Int, _ cached: Int, _ output: Int) -> [String: Any] {
        rec(at, "event_msg", ["type": "token_count", "info": ["total_token_usage": ["input_tokens": input, "cached_input_tokens": cached, "output_tokens": output]]])
    }
}

/// A temporary HOME with helpers that write logs and status files whose mtimes are `now - ageMs`.
struct ActivitySandbox {
    let home: TempHome

    init() throws { home = try TempHome() }

    var roots: Roots { get throws { try Roots.resolve(env: home.env) } }

    @discardableResult
    func put(_ relative: String, _ text: String, ageMs: Double = 0) throws -> URL {
        let url = try home.write(relative, text)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: (activityNowMs - ageMs) / 1000)], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    func claudeLog(cwd: String = "/work/app", session: String, _ records: [[String: Any]], ageMs: Double = 0) throws -> URL {
        let folder = "-" + cwd.map { $0 == "/" || $0 == "." ? "-" : String($0) }.joined().dropFirst()
        return try put(".claude/projects/\(folder)/\(session).jsonl", records.map(activityJSON).joined(separator: "\n") + "\n", ageMs: ageMs)
    }

    func status(_ pid: Int, session: String? = nil, _ over: [String: Any] = [:]) throws {
        var s: [String: Any] = [
            "pid": pid, "sessionId": session ?? activitySid(pid), "cwd": "/work/app", "startedAt": activityNowMs - 3_600_000,
            "procStart": "Mon Nov  2 11:00:00 2026", "status": "idle", "name": "app-1", "nameSource": "derived", "statusUpdatedAt": activityNowMs - 3_000_000,
        ]
        for (k, v) in over { s[k] = v }
        try put(".claude/sessions/\(pid).json", activityJSON(s))
    }

    @discardableResult
    func codexLog(id: String, _ records: [[String: Any]], ageMs: Double = 0) throws -> URL {
        try put(".codex/sessions/2026/11/02/rollout-2026-11-02T01-00-00-\(id).jsonl", records.map(activityJSON).joined(separator: "\n") + "\n", ageMs: ageMs)
    }

    func read(_ proc: FakeProcess = FakeProcess(), options: ActivityOptions = ActivityOptions()) async throws -> ActivityReport {
        await readActivity(roots: try roots, now: activityNow, proc: proc, options: options)
    }
}

func session(_ report: ActivityReport, _ id: String) -> ActivitySession? { report.sessions.first { $0.id == id } }

// MARK: - Suite

@Suite("Activity")
struct ActivityTests {
    private func open(_ n: Int, usage: [String: Any]? = nil) -> [[String: Any]] {
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(n))
        return [c.user("Build the thing", activityNowMs - 60_000), c.tool("b\(n)", "Bash", ["command": "sleep 1"], activityNowMs - 50_000, usage: usage)]
    }

    @Test("Claude: each state comes from the status file and the transcript tail")
    func claudeStates() async throws {
        let sb = try ActivitySandbox()
        try sb.status(1, ["status": "busy"]); try sb.claudeLog(session: activitySid(1), open(1), ageMs: 1000)
        try sb.status(2, ["status": "busy"]); try sb.claudeLog(session: activitySid(2), open(2), ageMs: ActivityDefaults.toolQuietMs + 60_000)
        let q = ClaudeRecords(cwd: "/work/app", session: activitySid(3))
        try sb.status(3, ["status": "busy"])
        try sb.claudeLog(session: activitySid(3), [q.user("Plan it", activityNowMs - 9000), q.tool("q3", "AskUserQuestion", ["question": "Which one?"], activityNowMs - 8000)], ageMs: 5000)
        try sb.status(4, ["status": "idle"]); try sb.claudeLog(session: activitySid(4), open(4), ageMs: 400_000)
        try sb.status(5, ["status": "shell"]); try sb.claudeLog(session: activitySid(5), open(5), ageMs: 2000)
        try sb.status(6, ["status": "busy"]); try sb.claudeLog(session: activitySid(6), open(6), ageMs: 60_000)
        try sb.status(7, ["status": "busy"]); try sb.claudeLog(session: activitySid(7), open(7), ageMs: ActivityDefaults.endedKeepMs + 60_000)
        try sb.status(8, ["status": "busy"]); try sb.claudeLog(session: activitySid(8), open(8), ageMs: 2000)
        try sb.status(9, ["status": "mystery"]); try sb.claudeLog(session: activitySid(9), open(9), ageMs: 2000)
        let proc = FakeProcess(alive: [1, 2, 3, 4, 5, 8, 9], starts: [8: "Tue Nov  3 01:00:00 2026", 1: "Mon Nov  2  11:00:00  2026"])
        let report = try await sb.read(proc)

        #expect(session(report, activitySid(1))?.state == .running)
        #expect(session(report, activitySid(1))?.currentTool?.name == "Bash")
        let quiet = try #require(session(report, activitySid(2)))
        #expect(quiet.state == .unmeasurable)
        #expect(quiet.reasonCode == .claudePromptVsBusy)
        #expect(quiet.stateReason == ActivityReason.claudePromptVsBusy.text)
        #expect(quiet.currentTool?.name == "Bash")
        #expect(session(report, activitySid(3))?.state == .waiting)
        #expect(session(report, activitySid(4))?.state == .idle)
        #expect(session(report, activitySid(4))?.currentTool == nil)
        #expect(session(report, activitySid(5))?.state == .running)
        #expect(session(report, activitySid(6))?.state == .ended)
        #expect(session(report, activitySid(7)) == nil)
        #expect(session(report, activitySid(8))?.state == .ended, "a reused pid has another start time")
        #expect(session(report, activitySid(9))?.reasonCode == .claudeUnknownStatus)
        // age comes from the transcript's last write, not from the stale statusUpdatedAt
        #expect(session(report, activitySid(1))?.lastWriteAgoMs == 1000)
        #expect(session(report, activitySid(1))?.ageMs == 3_600_000)
    }

    @Test("Claude: a session with no transcript yet is listed from its status file")
    func claudeWithoutTranscript() async throws {
        let sb = try ActivitySandbox()
        try sb.status(9, ["status": "idle", "statusUpdatedAt": activityNowMs - 5000])
        let s = try #require(session(try await sb.read(FakeProcess(alive: [9])), activitySid(9)))
        #expect(s.state == .idle)
        #expect(s.cost == nil)
        #expect(s.costNote == "No transcript found for this session.")
        #expect(s.title == "2026-11-02 · \(activitySid(9).prefix(8))")
        #expect(s.lastWriteAgoMs == 5000)
    }

    @Test("junk titles fall back to the first meaningful request, then to date and short id")
    func titles() async throws {
        for junk in ["", "  ", "/clear", "/model opus", "<command-name>/clear</command-name>", "Caveat: The messages below were generated by the user", "<local-command-stdout></local-command-stdout>", "[Request interrupted by user]", "# AGENTS.md instructions for /x", "Warmup", "?!"] {
            #expect(SessionTitles.isJunk(junk), "\(junk)")
        }
        #expect(!SessionTitles.isJunk("/Users/me/app/file.ts is broken"))
        #expect(!SessionTitles.isJunk("Fix the login redirect"))
        #expect(SessionTitles.pick([nil, "Caveat: x"], startedAt: 1_793_440_800_000, id: "abcdef1234") == "2026-10-31 · abcdef12")
        #expect(SessionTitles.pick([], startedAt: nil, id: "pid 52003") == "unknown date · pid 5200")
        #expect(SessionTitles.clean(String(repeating: "x", count: 100)).utf16.count == 80)

        let sb = try ActivitySandbox()
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(21))
        try sb.status(21, ["name": "work-app-3"])
        try sb.claudeLog(session: activitySid(21), [
            ["type": "ai-title", "aiTitle": "Caveat: The messages below were generated by the user while running local commands", "sessionId": activitySid(21)],
            c.user("<command-name>/clear</command-name><command-args></command-args>", activityNowMs - 9000), c.user("Fix the login redirect", activityNowMs - 8000),
        ])
        try sb.status(22)
        try sb.claudeLog(session: activitySid(22), [
            ["type": "custom-title", "customTitle": "My renamed session", "sessionId": activitySid(22)], ["type": "ai-title", "aiTitle": "Generated one", "sessionId": activitySid(22)],
            ClaudeRecords(cwd: "/work/app", session: activitySid(22)).user("hello there", activityNowMs - 8000),
        ])
        try sb.status(23, ["startedAt": 1_793_440_800_000.0])
        try sb.claudeLog(session: activitySid(23), [ClaudeRecords(cwd: "/work/app", session: activitySid(23)).user("/review", activityNowMs - 8000)])
        try sb.status(24, ["name": "Named by the user", "nameSource": "user"])
        let report = try await sb.read(FakeProcess(alive: [21, 22, 23, 24]))
        #expect(session(report, activitySid(21))?.title == "Fix the login redirect")
        #expect(session(report, activitySid(22))?.title == "My renamed session")
        #expect(session(report, activitySid(23))?.title == "2026-10-31 · \(activitySid(23).prefix(8))")
        #expect(session(report, activitySid(24))?.title == "Named by the user")
    }

    @Test("a worktree slug is never the project name")
    func worktreeProjects() async throws {
        let sb = try ActivitySandbox()
        let home = sb.home.root.path
        #expect(projectName("\(home)/proj/.claude/worktrees/lucky-fox") == "proj")
        #expect(projectName("\(home)/proj/.claude/worktrees/lucky-fox/src") == "proj")
        #expect(projectName("\(home)/.codex/worktrees/a1b2/my-repo") == "my-repo")
        // a real linked worktree: `.git` is a file that points into the main repo
        try sb.home.write("wt-checkout/.git", "gitdir: \(home)/mainrepo/.git/worktrees/wt1\n")
        try FileManager.default.createDirectory(atPath: "\(home)/wt-checkout/sub/dir", withIntermediateDirectories: true)
        #expect(projectName("\(home)/wt-checkout") == "mainrepo")
        #expect(projectName("\(home)/wt-checkout/sub/dir") == "mainrepo")
        // a normal checkout keeps its own name
        try FileManager.default.createDirectory(atPath: "\(home)/plain/.git", withIntermediateDirectories: true)
        #expect(projectName("\(home)/plain") == "plain")
        // the original cwd that Claude records beats a path that tells nothing
        #expect(projectName("/x/odd-slug", hint: "/home/me/realrepo") == "realrepo")
        #expect(projectName(nil) == nil)

        let wt = "\(home)/proj/.claude/worktrees/lucky-fox"
        try sb.status(31, ["cwd": wt])
        try sb.claudeLog(cwd: wt, session: activitySid(31), [ClaudeRecords(cwd: wt, session: activitySid(31)).user("Work", activityNowMs - 5000)])
        let x = CodexRecords(id: activityUuid(32))
        try sb.codexLog(id: activityUuid(32), [x.meta(activityNowMs - 5000, "\(home)/.codex/worktrees/a1b2/my-repo"), x.done(activityNowMs - 4000)])
        let report = try await sb.read(FakeProcess(alive: [31], threads: [CodexThread(pid: 3200, threadId: activityUuid(32))]))
        #expect(session(report, activitySid(31))?.project == "proj")
        #expect(session(report, activityUuid(32))?.project == "my-repo")
    }

    // MARK: Codex

    @Test("Codex: a process maps to its rollout by thread lock; state comes from the rollout tail")
    func codexStates() async throws {
        let sb = try ActivitySandbox()
        var threads: [CodexThread] = []
        func mk(_ n: Int, _ records: [[String: Any]], _ ageMs: Double) throws {
            try sb.codexLog(id: activityUuid(n), records, ageMs: ageMs)
            threads.append(CodexThread(pid: 4000 + n, threadId: activityUuid(n)))
        }
        let t = activityNowMs
        func c(_ n: Int) -> CodexRecords { CodexRecords(id: activityUuid(n)) }
        try mk(41, [c(41).meta(t - 90_000, "/work/a"), c(41).started(t - 80_000), c(41).say(t - 79_000, "Run the suite"), c(41).call(t - 70_000, "k1", "exec_command", ["cmd": "npm test"])], 2000)
        try mk(42, [c(42).meta(t - 90_000, "/work/b"), c(42).started(t - 80_000), c(42).call(t - 70_000, "k2", "exec_command", ["cmd": "npm test"])], ActivityDefaults.toolQuietMs + 90_000)
        try mk(43, [c(43).meta(t - 90_000, "/work/c"), c(43).started(t - 80_000), c(43).say(t - 79_000, "Hi"), c(43).done(t - 70_000)], 70_000)
        try mk(44, [c(44).meta(t - 90_000, "/work/d"), c(44).started(t - 80_000), c(44).call(t - 70_000, "k4", "exec_command", ["cmd": "x"]), c(44).aborted(t - 60_000)], 60_000)
        try mk(45, [c(45).meta(t - 90_000, "/work/e"), c(45).started(t - 80_000), c(45).call(t - 79_000, "k5", "request_user_input", ["q": "which?"])], 5000)
        try mk(46, [c(46).meta(t - 90_000, "/work/f", extra: ["parent_thread_id": activityUuid(41), "source": ["subagent": ["thread_spawn": ["parent_thread_id": activityUuid(41)]]]]), c(46).started(t - 80_000)], 1000)
        threads.append(CodexThread(pid: 4047, threadId: activityUuid(47)))
        threads.append(CodexThread(pid: 4048, threadId: nil))
        let report = try await sb.read(FakeProcess(starts: [4047: "Mon Nov  2 11:00:00 2026"], threads: threads))

        #expect(session(report, activityUuid(41))?.state == .running)
        #expect(session(report, activityUuid(41))?.currentTool?.name == "exec_command")
        #expect(session(report, activityUuid(41))?.title == "Run the suite")
        let silent = try #require(session(report, activityUuid(42)))
        #expect(silent.state == .unmeasurable)
        #expect(silent.reasonCode == .codexToolSilent)
        #expect(silent.stateReason == ActivityReason.codexToolSilent.text)
        #expect(session(report, activityUuid(43))?.state == .idle)
        #expect(session(report, activityUuid(44))?.state == .idle)
        #expect(session(report, activityUuid(44))?.currentTool == nil, "an aborted turn drops the open tool")
        #expect(session(report, activityUuid(45))?.state == .waiting)
        #expect(session(report, activityUuid(46)) == nil, "a child thread is not a session")
        let missing = try #require(session(report, activityUuid(47)))
        #expect(missing.reasonCode == .codexNoRollout)
        #expect(missing.ageMs == 3_600_000, "no rollout exists yet, so the process start is the clock")
        #expect(missing.title == "2026-11-02 · \(activityUuid(47).prefix(8))")
        let bare = try #require(session(report, "pid:4048:unknown"))
        #expect(bare.reasonCode == .codexNoRollout)
        #expect(bare.lastWriteAgoMs == nil)
        #expect(session(report, activityUuid(41))?.lastWriteAgoMs == 2000)
        #expect(session(report, activityUuid(41))?.ageMs == 90_000)
    }

    @Test("Codex: thread name from the session index, junk names fall back to the first request")
    func codexTitles() async throws {
        let sb = try ActivitySandbox()
        try sb.put(".codex/session_index.jsonl", [["id": activityUuid(51), "thread_name": "Greet user"], ["id": activityUuid(52), "thread_name": "/review"]].map(activityJSON).joined(separator: "\n") + "\n")
        let t = activityNowMs
        for n in [51, 52] {
            let c = CodexRecords(id: activityUuid(n))
            try sb.codexLog(id: activityUuid(n), [c.meta(t - 9000, "/work/x"), c.started(t - 8000), c.say(t - 7000, "Explain the build"), c.done(t - 6000)])
        }
        let report = try await sb.read(FakeProcess(threads: [CodexThread(pid: 1, threadId: activityUuid(51)), CodexThread(pid: 2, threadId: activityUuid(52))]))
        #expect(session(report, activityUuid(51))?.title == "Greet user")
        #expect(session(report, activityUuid(52))?.title == "Explain the build")
    }

    // MARK: Cost

    @Test("cost: estimated from logged tokens, deduplicated, and nil when the model has no price")
    func costs() async throws {
        let sb = try ActivitySandbox()
        let t = activityNowMs
        let usage: [String: Any] = ["input_tokens": 1000, "output_tokens": 2000, "cache_creation_input_tokens": 4000, "cache_read_input_tokens": 10_000]
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(61))
        try sb.status(61)
        try sb.claudeLog(session: activitySid(61), [
            c.user("go", t - 9000), c.tool("a", "Read", ["file_path": "/x"], t - 8000, usage: usage),
            c.tool("a2", "Read", ["file_path": "/y"], t - 7900, usage: usage, messageId: "msg-a"), // the same message streamed again
            c.tool("b", "Read", ["file_path": "/z"], t - 7000, usage: ["input_tokens": 500, "output_tokens": 100]),
        ])
        try sb.status(62)
        try sb.claudeLog(session: activitySid(62), [ClaudeRecords(cwd: "/work/app", session: activitySid(62)).tool("a", "Read", ["file_path": "/x"], t - 8000, model: "claude-mystery-9", usage: usage)])
        let x = CodexRecords(id: activityUuid(63))
        try sb.codexLog(id: activityUuid(63), [x.meta(t - 9000, "/work/x"), x.model(t - 8900, "gpt-6.1-sol"), x.started(t - 8000), x.tokens(t - 7000, 10_000, 4000, 500), x.tokens(t - 6000, 12_000, 5000, 800), x.done(t - 5000)])
        let report = try await sb.read(FakeProcess(alive: [61, 62], threads: [CodexThread(pid: 63, threadId: activityUuid(63))]))

        let claude = try #require(session(report, activitySid(61)))
        #expect(claude.cost?.estimated == true)
        // (1000*3 + 2000*15 + 4000*3.75 + 10000*0.3 + 500*3 + 100*15) per million at claude-sonnet-4-6 prices
        #expect(abs((claude.cost?.usd ?? 0) - 0.054) < 1e-9)
        let unpriced = try #require(session(report, activitySid(62)))
        #expect(unpriced.cost == nil)
        #expect(unpriced.costNote == "No price for model \"claude-mystery-9\", so no estimate.")
        // gpt-6.1-sol: uncached input 7000*2 + cached 5000*0.1 + output 800*10 per million
        #expect(abs((session(report, activityUuid(63))?.cost?.usd ?? 0) - 0.0225) < 1e-9)
        #expect(Pricing.price(for: "claude-sonnet-4-6[1m]")?.input == 3)
        #expect(Pricing.price(for: "claude-haiku-4-5-20251001")?.output == 5)
        #expect(Pricing.price(for: "claude-mystery-9") == nil)
    }

    @Test("cost: a log too large to read in full gives no estimate rather than a partial sum")
    func truncatedCost() async throws {
        let sb = try ActivitySandbox()
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(71))
        try sb.status(71)
        let filler = (0..<40).map { c.tool("f\($0)", "Read", ["file_path": "/f/\($0)"], activityNowMs - 100_000 + Double($0), usage: ["input_tokens": 5, "output_tokens": 5]) }
        try sb.claudeLog(session: activitySid(71), filler)
        var options = ActivityOptions()
        options.liveTailBytes = 1500
        let report = try await sb.read(FakeProcess(alive: [71]), options: options)
        let s = try #require(session(report, activitySid(71)))
        #expect(s.cost == nil)
        #expect(s.costNote?.contains("too large") == true)
        #expect(report.stats.truncated == 1)
    }

    @Test("cost: subagent transcripts count toward the session cost")
    func subagentCost() async throws {
        let sb = try ActivitySandbox()
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(72))
        try sb.status(72)
        try sb.claudeLog(session: activitySid(72), [c.user("go", activityNowMs - 9000), c.tool("m1", "Read", ["file_path": "/x"], activityNowMs - 8000, usage: ["input_tokens": 1_000_000])])
        var sub = c.tool("s1", "Read", ["file_path": "/y"], activityNowMs - 7000, usage: ["output_tokens": 1_000_000])
        sub["isSidechain"] = true
        try sb.put(".claude/projects/-work-app/\(activitySid(72))/subagents/agent-1.jsonl", activityJSON(sub) + "\n", ageMs: 7000)
        let s = try #require(session(try await sb.read(FakeProcess(alive: [72])), activitySid(72)))
        #expect(abs((s.cost?.usd ?? 0) - 18) < 1e-9, "1M input + 1M output at claude-sonnet-4-6 prices")
    }

    @Test("many subagent transcripts: the newest write decides liveness, not directory order")
    func subagentLiveness() async throws {
        let sb = try ActivitySandbox()
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(73))
        try sb.status(73, ["status": "busy"])
        try sb.claudeLog(session: activitySid(73), [c.user("go", activityNowMs - 900_000), c.tool("t1", "Agent", ["description": "delegate"], activityNowMs - 800_000)], ageMs: 800_000)
        for i in 0..<60 {
            try sb.put(".claude/projects/-work-app/\(activitySid(73))/subagents/agent-\(String(format: "%02d", i)).jsonl", activityJSON(["type": "user", "isSidechain": true, "message": ["role": "user", "content": "x"]]) + "\n", ageMs: i == 59 ? 2000 : 600_000)
        }
        let s = try #require(session(try await sb.read(FakeProcess(alive: [73])), activitySid(73)))
        #expect(s.lastWriteAgoMs == 2000)
        #expect(s.state == .running, "an open tool, but a subagent wrote 2 s ago")
    }

    // MARK: Failures

    @Test("failed commands group by command with a count, one title form, and a neutral laterPass")
    func failureGroups() async throws {
        let sb = try ActivitySandbox()
        let marker = sb.home.url("must-not-exist").path
        let a = ClaudeRecords(cwd: "/work/app-a", session: activitySid(81))
        let b = ClaudeRecords(cwd: "/work/app-b", session: activitySid(82))
        let t = activityMinutes
        try sb.claudeLog(cwd: "/work/app-a", session: activitySid(81), [
            a.user("run it", t(60)),
            a.tool("a1", "Bash", ["command": "npm test"], t(50)), a.result("a1", "Exit code 1\nTAP\nError: boom in suite", isError: true, t(49)),
            a.tool("a2", "Bash", ["command": "cd /work/app-a && npm  test"], t(40)), a.result("a2", "Exit code 1\nError: boom in suite", isError: true, t(39)),
            a.tool("a3", "Bash", ["command": "npm test"], t(10)), a.result("a3", "all green", isError: false, t(9)),
            a.tool("a4", "Bash", ["command": "make deploy"], t(70)), a.result("a4", "done", isError: false, t(69)),
            a.tool("a5", "Bash", ["command": "make deploy"], t(30)), a.result("a5", "Exit code 2\nmake: *** Error 2", isError: true, t(29)),
            a.tool("a6", "Bash", ["command": "grep nothing file.txt"], t(20)), a.result("a6", "Exit code 1", isError: true, t(19)),
            a.tool("a7", "Bash", ["command": "rm -rf build"], t(18)), a.result("a7", "The user doesn't want to proceed with this tool use.", isError: true, t(17)),
            a.tool("a8", "Bash", ["command": "touch \(marker) && false"], t(15)), a.result("a8", "Exit code 1", isError: true, t(14)),
            a.hookFail(1, "Stop", "sh /h/check.sh", t(45)), a.hookFail(2, "Stop", "sh /h/check.sh", t(25)),
        ])
        try sb.claudeLog(cwd: "/work/app-b", session: activitySid(82), [
            b.user("again", t(55)),
            b.tool("b1", "Bash", ["command": "npm test"], t(5)), b.result("b1", "Exit code 1\nError: boom in suite", isError: true, t(4)),
        ])
        let x = CodexRecords(id: activityUuid(83))
        try sb.codexLog(id: activityUuid(83), [x.meta(t(60), "/work/app-a"), x.exec(t(35), 1, "npm test", 1, "running\nerror: codex side")])
        let report = try await sb.read()

        let npm = try #require(report.failures.first { $0.cli == .claude && $0.title == "npm test" })
        #expect(npm.count == 3)
        #expect(npm.sessions == 2)
        #expect(npm.projects == ["app-a", "app-b"])
        #expect(npm.exit == 1)
        #expect(npm.first == activityIso(t(49)))
        #expect(npm.last == activityIso(t(4)))
        #expect(npm.laterPass == nil, "the pass at t(9) is before the last failure at t(4)")
        let deploy = try #require(report.failures.first { $0.title == "make deploy" })
        #expect(deploy.count == 1)
        #expect(deploy.reason == "make: *** Error 2")
        #expect(deploy.laterPass == nil, "the pass came before the failure")
        let codex = try #require(report.failures.first { $0.cli == .codex })
        #expect(codex.title == "npm test")
        #expect(codex.reason == "error: codex side")
        #expect(!report.failures.contains { $0.title.hasPrefix("grep") }, "exploratory commands are not failures")
        #expect(!report.failures.contains { $0.title.hasPrefix("rm -rf") }, "a rejected tool call is not a failed command")
        let hook = try #require(report.failures.first { $0.kind == .hook })
        #expect(hook.count == 2)
        #expect(hook.title == "sh /h/check.sh")
        #expect(hook.hook == ActivityFailure.Hook(hash: Inventory.hookHash(event: "Stop", command: "sh /h/check.sh"), event: "Stop"))
        #expect(hook.reason == "check failed")
        // R4: the recorded command was parsed and listed, never run
        #expect(report.failures.contains { $0.title.contains("touch") })
        #expect(!FileManager.default.fileExists(atPath: marker))
        // "later pass" is a timestamp, not a claim that the failure was fixed
        #expect(!npm.jsonObject.keys.contains { $0.lowercased().contains("fix") || $0.lowercased().contains("resolved") })
    }

    @Test("laterPass is the first passing run after the last failure of the same command")
    func laterPass() async throws {
        let sb = try ActivitySandbox()
        let a = ClaudeRecords(cwd: "/work/app-a", session: activitySid(91))
        let t = activityMinutes
        try sb.claudeLog(cwd: "/work/app-a", session: activitySid(91), [
            a.user("go", t(60)),
            a.tool("a1", "Bash", ["command": "pnpm lint"], t(50)), a.result("a1", "Exit code 1\nerror: bad", isError: true, t(49)),
            a.tool("a2", "Bash", ["command": "pnpm lint"], t(30)), a.result("a2", "clean", isError: false, t(29)),
            a.tool("a3", "Bash", ["command": "pnpm lint"], t(20)), a.result("a3", "clean", isError: false, t(19)),
        ])
        let row = try #require(try await sb.read().failures.first { $0.title == "pnpm lint" })
        #expect(row.laterPass == activityIso(t(29)))
    }

    // MARK: Files

    @Test("file history: edits across sessions and CLIs, with labels that keep two rank.ts apart")
    func fileHistory() async throws {
        let sb = try ActivitySandbox()
        let a = ClaudeRecords(cwd: "/work/app-a", session: activitySid(101))
        let b = ClaudeRecords(cwd: "/work/app-b", session: activitySid(102))
        let t = activityMinutes
        try sb.claudeLog(cwd: "/work/app-a", session: activitySid(101), [
            a.user("edit", t(60)),
            a.tool("e1", "Edit", ["file_path": "/work/app-a/src/rank.ts"], t(50)), a.result("e1", "ok", isError: false, t(49)),
            a.tool("e2", "Edit", ["file_path": "/work/app-a/src/rank.ts"], t(40)), a.result("e2", "ok", isError: false, t(39)),
            a.tool("e3", "Write", ["file_path": "/work/app-a/README.md"], t(30)), a.result("e3", "ok", isError: false, t(29)),
            a.tool("e4", "Edit", ["file_path": "/work/app-a/nope.ts"], t(20)), a.result("e4", "String not found", isError: true, t(19)),
        ])
        try sb.claudeLog(cwd: "/work/app-b", session: activitySid(102), [b.user("edit", t(60)), b.tool("e5", "Edit", ["file_path": "/work/app-b/src/rank.ts"], t(10)), b.result("e5", "ok", isError: false, t(9))])
        let x = CodexRecords(id: activityUuid(103))
        try sb.codexLog(id: activityUuid(103), [x.meta(t(60), "/work/app-a"), x.patch(t(5), 1, ["/work/app-a/src/rank.ts"]), x.patch(t(4), 2, ["/work/app-a/failed.ts"], status: "failed")])
        let report = try await sb.read()

        let rankA = try #require(report.files.first { $0.path == "/work/app-a/src/rank.ts" })
        #expect(rankA.edits == 3)
        #expect(rankA.sessions == 2)
        #expect(rankA.clis == [.claude, .codex])
        #expect(rankA.last == activityIso(t(5)))
        #expect(rankA.label == "app-a/src/rank.ts")
        #expect(report.files.first { $0.path == "/work/app-b/src/rank.ts" }?.label == "app-b/src/rank.ts")
        #expect(report.files.first { $0.path == "/work/app-a/README.md" }?.label == "README.md")
        #expect(!report.files.contains { $0.path.contains("nope") || $0.path.contains("failed") }, "failed edits are not history")
        #expect(Set(report.files.map(\.label)).count == report.files.count)
    }

    @Test("older Codex rollouts that record patches only as tool text still give file history")
    func legacyPatches() async throws {
        let sb = try ActivitySandbox()
        let x = CodexRecords(id: activityUuid(111))
        let patch = "*** Begin Patch\n*** Update File: src/old.ts\n@@\n*** Add File: /abs/new.ts\n*** End Patch"
        let call: [String: Any] = ["timestamp": activityIso(activityNowMs - 8000), "type": "response_item", "payload": ["type": "custom_tool_call", "name": "exec", "call_id": "p1", "input": patch]]
        try sb.codexLog(id: activityUuid(111), [x.meta(activityNowMs - 9000, "/work/app-a"), call])
        let paths = try await sb.read().files.map(\.path).sorted()
        #expect(paths == ["/abs/new.ts", "/work/app-a/src/old.ts"])
    }

    @Test("shortestLabels: shortest unique suffix; a path that is a suffix of another keeps its whole path")
    func labels() {
        #expect(ActivityGroups.shortestLabels(["/a/x/rank.ts", "/b/x/rank.ts", "/a/y/other.ts"]) == ["a/x/rank.ts", "b/x/rank.ts", "other.ts"])
        #expect(ActivityGroups.shortestLabels(["/p/q/c.ts", "q/c.ts"]) == ["p/q/c.ts", "q/c.ts"])
        #expect(ActivityGroups.shortestLabels(["/only/one.ts"]) == ["one.ts"])
        #expect(ActivityGroups.shortestLabels([""]) == [""])
    }

    // MARK: Limits, incremental reads, parsers

    @Test("unmeasurable limits are listed even when nothing is running")
    func limits() async throws {
        let report = try await ActivitySandbox().read()
        #expect(report.sessions.isEmpty)
        #expect(Set(report.unmeasurable.map(\.code)) == [.claudePromptVsBusy, .codexToolSilent, .codexNoRollout, .codexHookRuns])
        #expect(report.unmeasurable.allSatisfy { $0.text == $0.code.text })
    }

    @Test("a second read with the same engine folds only appended bytes and sees the new state")
    func incremental() async throws {
        let sb = try ActivitySandbox()
        let c = ClaudeRecords(cwd: "/work/app", session: activitySid(121))
        try sb.status(121, ["status": "busy"])
        let first = [c.user("start", activityNowMs - 9000), c.tool("i1", "Bash", ["command": "make"], activityNowMs - 8000)]
        let url = try sb.claudeLog(session: activitySid(121), first, ageMs: 1000)
        let engine = ActivityEngine()
        let proc = FakeProcess(alive: [121])
        let a1 = await engine.readActivity(roots: try sb.roots, now: activityNow, proc: proc)
        #expect(session(a1, activitySid(121))?.currentTool?.name == "Bash")
        // the same file read again without a change must not fold its lines a second time
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((activityJSON(c.result("i1", "Exit code 1\nError: nope", isError: true, activityNowMs - 500)) + "\n").utf8))
        try handle.close()
        let a2 = await engine.readActivity(roots: try sb.roots, now: activityNow, proc: proc)
        #expect(session(a2, activitySid(121))?.currentTool == nil)
        #expect(a2.failures.map(\.title) == ["make"])
        #expect(a2.failures.first?.count == 1)
        let a3 = await engine.readActivity(roots: try sb.roots, now: activityNow, proc: proc)
        #expect(a3.failures.first?.count == 1, "an unchanged log is not folded again")
        #expect(a3 == a2)
    }

    @Test("process adapter parsers read ps and lsof output")
    func parsers() {
        let ps = [
            "  100 /Users/me/.local/bin/codex --no-daemon -c tui.animations=false",
            "  101 /Applications/Codex.app/codex app-server --listen stdio",
            "  104 /Applications/Codex.app/codex mcp-server",
            "  102 /usr/bin/node /x/not-codex.js",
            "  103 codex",
        ].joined(separator: "\n")
        #expect(ProcessOutputParser.codexPids(fromPS: ps) == [100, 103])
        let lsof = ["p100", "n/Users/me/.codex/.sqlite-maintenance.lock", "n/Users/me/.codex/thread-writer-locks/\(activityUuid(1)).lock", "p103", "n/etc/hosts"].joined(separator: "\n")
        #expect(ProcessOutputParser.lockFds(fromLsof: lsof) == [CodexThread(pid: 100, threadId: activityUuid(1))])
    }

    @Test("Codex tokens: interleaved streams, repeated totals and an inherited first total do not inflate the count")
    func codexTokenTotals() {
        func event(_ total: (Int, Int), _ last: (Int, Int)? = nil) -> Data {
            var info: [String: Any] = ["total_token_usage": ["input_tokens": total.0, "cached_input_tokens": 0, "output_tokens": total.1]]
            if let last { info["last_token_usage"] = ["input_tokens": last.0, "cached_input_tokens": 0, "output_tokens": last.1] }
            return Data(activityJSON(["timestamp": activityIso(activityNowMs), "type": "event_msg", "payload": ["type": "token_count", "info": info]]).utf8)
        }
        func metrics(_ lines: [Data]) -> Pricing.Usage? {
            let st = ActivityLogState(cli: .codex)
            for line in lines { ActivityFold.foldCodex(st, line) }
            return st.metrics["unknown"]
        }
        // A parent at 1000, an embedded reviewer's own total at 50, the parent again at 1100, and a repeat of that total.
        let m = metrics([event((1000, 100), (1000, 100)), event((50, 5), (50, 5)), event((1100, 110), (100, 10)), event((1100, 110), (100, 10))])
        #expect(m?.input == 1150 && m?.output == 115)
        // A forked rollout starts from the parent's total: only the turn's own usage belongs to it.
        let fork = metrics([event((90_000, 9000), (200, 20))])
        #expect(fork?.input == 200 && fork?.output == 20)
        // Rollouts with no per-turn usage still work from the difference, and a lower total is a restart.
        let old = metrics([event((1000, 100)), event((1500, 150)), event((40, 4))])
        #expect(old?.input == 1540 && old?.output == 154)
    }

    @Test("text helpers behave like the JavaScript they replace")
    func textHelpers() {
        #expect(Inventory.sha("Stop|sh /h/check.sh").count == 12)
        #expect(ActivityText.isoString(1_793_620_800_123) == "2026-11-02T12:00:00.123Z")
        #expect(ActivityText.parseTimestamp("2026-11-02T12:00:00.123Z") == 1_793_620_800_123)
        #expect(ActivityText.parseTimestamp("2026-11-02T14:00:00+02:00") == 1_793_620_800_000)
        #expect(ActivityText.parseProcessStart("Mon Nov  2 11:58:00 2026") == 1_793_620_680_000)
        #expect(ActivityText.parseProcessStart("garbage") == nil)
        #expect(ActivityText.squash("  a \t\n b\u{00A0}c  ") == "a b c")
        #expect(ActivityText.prefix("héllo", 2) == "hé")
        #expect(ActivityText.basename("/a/b/") == "b")
        #expect(ActivityText.basename("/") == "")
    }

    @Test("a real home is refused: Activity tests only run on a TempHome")
    func refusesRealHome() throws {
        let real = Roots.realHomeDirectory()
        #expect(throws: RootsError.self) {
            _ = try Roots.resolve(env: ["HOME": real, "REINS_TEST": "1"], realHome: real)
        }
    }
}
