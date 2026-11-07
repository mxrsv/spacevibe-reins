import Foundation
import ReinsCore

/// A process list replayed from a JSON file, for dev runs and screenshots against a synthetic HOME. It never starts
/// a process and never signals one: `terminate` only edits the in-memory list, so Stop works end to end without
/// touching the machine. The pids in the file are made up; nothing real answers to them.
///
/// File format (what `scripts/fixture-home.mjs` writes to `<dir>/.reins/activity-proc.json`; the golden file wraps the
/// same shape in `shared`, which is unwrapped here):
///
///     { "alive": [41001], "starts": { "52003": "Mon Nov  2 11:58:00 2026" },
///       "threads": [{ "pid": 52001, "threadId": "a000..." }, { "pid": 52003, "threadId": null }], "delayMs": 20000 }
///
/// `alive`: pids `kill(pid, 0)` finds (Claude Code status files name them). `starts`: `ps lstart` text per pid.
/// `threads`: live `codex` processes with their thread lock. `delayMs`: the first question waits this long once, so a
/// run can sit on "Reading logs…".
final class FixtureProcessAdapter: ProcessAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var aliveSet: Set<Int>
    private var starts: [Int: String]
    private var threads: [CodexThread]
    private var pendingDelayMs: Int

    init(alive: [Int] = [], starts: [Int: String] = [:], threads: [CodexThread] = [], delayMs: Int = 0) {
        aliveSet = Set(alive)
        self.starts = starts
        self.threads = threads
        pendingDelayMs = delayMs
    }

    /// A list with no process: what `SPACEVIBE_TEST=1` uses when no file is given, so test mode can never see a real process.
    static var empty: FixtureProcessAdapter { FixtureProcessAdapter() }

    static func load(path: String) throws -> FixtureProcessAdapter {
        guard let data = FileManager.default.contents(atPath: path),
              var spec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ReinsError("SPACEVIBE_PROC_FIXTURE does not point at a readable process list file.", status: 400)
        }
        if let shared = spec["shared"] as? [String: Any] { spec = shared }
        let alive = (spec["alive"] as? [Int]) ?? []
        var starts: [Int: String] = [:]
        for (key, value) in (spec["starts"] as? [String: String]) ?? [:] {
            if let pid = Int(key) { starts[pid] = value }
        }
        let threads = ((spec["threads"] as? [[String: Any]]) ?? []).compactMap { item -> CodexThread? in
            guard let pid = item["pid"] as? Int else { return nil }
            return CodexThread(pid: pid, threadId: item["threadId"] as? String)
        }
        return FixtureProcessAdapter(alive: alive, starts: starts, threads: threads, delayMs: (spec["delayMs"] as? Int) ?? 0)
    }

    private func firstQuestionDelay() async {
        let ms = lock.withLock { () -> Int in
            let value = pendingDelayMs
            pendingDelayMs = 0
            return value
        }
        if ms > 0 { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
    }

    func isAlive(pid: Int) async -> Bool {
        await firstQuestionDelay()
        return lock.withLock { aliveSet.contains(pid) }
    }

    func startTime(pid: Int) async -> String? {
        await firstQuestionDelay()
        return lock.withLock { starts[pid] }
    }

    func codexThreads() async -> [CodexThread] {
        await firstQuestionDelay()
        return lock.withLock { threads }
    }

    func terminate(pid: Int) async throws {
        let known = lock.withLock { aliveSet.contains(pid) || threads.contains { $0.pid == pid } }
        if !known { throw ProcessSignalError.noSuchProcess }
        lock.withLock {
            aliveSet.remove(pid)
            threads.removeAll { $0.pid == pid }
        }
    }
}
