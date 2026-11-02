import Foundation

/// What `stopSession` found out. `exited` is false when the process was still alive at the end of the wait.
public struct StopResult: Equatable, Sendable {
    public var exited: Bool
}

public struct StopOptions: Sendable {
    /// How long to wait for the process to go away after the signal.
    public var waitMs = 3000
    public var pollMs = 100

    public init(waitMs: Int = 3000, pollMs: Int = 100) {
        self.waitMs = waitMs
        self.pollMs = pollMs
    }
}

private func sameStart(_ a: String?, _ b: String?) -> Bool {
    guard let a, let b, !a.isEmpty, !b.isEmpty else { return false }
    return ActivityText.collapse(a) == ActivityText.collapse(b)
}

/// The pid of a live session, decided from the system now and never taken from the caller: pids get reused.
private func livePid(roots: Roots, cli: ActivityCLI, id: String, proc: any ProcessAdapter) async -> Int? {
    if cli == .codex {
        let threads = await proc.codexThreads()
        return threads.first { t in t.threadId != nil ? t.threadId == id : "pid:\(t.pid)" == id }?.pid
    }
    let dir = roots.claude.root.appendingPathComponent("sessions", isDirectory: true)
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
    for name in names.filter(ActivityEngine.isStatusFileName).sorted() {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)), let doc = try? OrderedJSON(data: data),
              doc.root["sessionId"]?.stringValue == id, let pidText = doc.root["pid"]?.numberText, let pid = Int(pidText),
              await proc.isAlive(pid: pid) else { continue }
        if sameStart(await proc.startTime(pid: pid), doc.root["procStart"]?.stringValue) { return pid }
    }
    return nil
}

/// Asks one running session to end (SIGTERM). It cannot be undone: the current turn stops, finished work stays.
///
/// The engine never asks the user; the UI confirms before it calls this. The pid is looked up again from the live system
/// (the Claude status file with its start time, or the Codex thread lock), so a stale row cannot signal a reused pid.
/// - Throws: `ReinsError` 404 when the session is no longer running, 403 when it belongs to another user, 500 for any other signal error.
public func stopSession(roots: Roots, cli: ActivityCLI, id: String, proc: any ProcessAdapter, options: StopOptions = StopOptions()) async throws -> StopResult {
    guard let pid = await livePid(roots: roots, cli: cli, id: id, proc: proc) else {
        throw ReinsError("That session is no longer running.", status: 404)
    }
    do {
        try await proc.terminate(pid: pid)
    } catch ProcessSignalError.noSuchProcess {
        return StopResult(exited: true)
    } catch ProcessSignalError.notPermitted {
        throw ReinsError("This session belongs to another user, so it cannot be stopped.", status: 403)
    } catch ProcessSignalError.failed(let code) {
        throw ReinsError("The session could not be stopped (error \(code)).", status: 500)
    }
    let deadline = Date().addingTimeInterval(Double(options.waitMs) / 1000)
    while Date() < deadline {
        if !(await proc.isAlive(pid: pid)) { return StopResult(exited: true) }
        try? await Task.sleep(nanoseconds: UInt64(max(1, options.pollMs)) * 1_000_000)
    }
    return StopResult(exited: !(await proc.isAlive(pid: pid)))
}
