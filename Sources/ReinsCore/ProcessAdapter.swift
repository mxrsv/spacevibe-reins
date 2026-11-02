import Foundation

/// A live `codex` process and the thread it holds a writer lock on (`threadId` is nil before the first prompt).
public struct CodexThread: Equatable, Sendable {
    public var pid: Int
    public var threadId: String?

    public init(pid: Int, threadId: String?) {
        self.pid = pid
        self.threadId = threadId
    }
}

/// Why `terminate` failed. `noSuchProcess` is ESRCH, `notPermitted` is EPERM.
public enum ProcessSignalError: Error, Equatable, Sendable {
    case noSuchProcess
    case notPermitted
    case failed(errno: Int32)
}

/// The only place Activity touches the operating system: `ps`, `lsof`, `kill(pid, 0)` and SIGTERM for Stop.
/// Only `terminate` changes anything, and `stopSession` is its one caller. Tests pass a fake with the same shape.
public protocol ProcessAdapter: Sendable {
    func isAlive(pid: Int) async -> Bool
    /// UTC `ps lstart` text, the same format as a Claude status file's `procStart`. Nil when unknown.
    func startTime(pid: Int) async -> String?
    /// Live `codex` processes with the thread each one holds a lock on.
    func codexThreads() async -> [CodexThread]
    func terminate(pid: Int) async throws
}

/// Parsers for the `ps` and `lsof` output, separate from the process spawning so tests can feed them text.
public enum ProcessOutputParser {
    private static let psLine = try! NSRegularExpression(pattern: #"^\s*(\d+)\s+(?:\S*/)?codex(?:\s+(.*))?$"#)
    private static let helperWords: Set<String> = ["app-server", "mcp-server"]
    private static let lockPath = try! NSRegularExpression(
        pattern: #"[\\/]thread-writer-locks[\\/]([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.lock$"#
    )

    /// `ps -axo pid=,args=` output to the pids of interactive-looking codex processes (`app-server` and `mcp-server` are helpers).
    public static func codexPids(fromPS output: String) -> [Int] {
        var pids: [Int] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = psLine.firstMatch(in: text, range: range),
                  let pidRange = Range(match.range(at: 1), in: text), let pid = Int(text[pidRange]) else { continue }
            var args = ""
            if match.range(at: 2).location != NSNotFound, let r = Range(match.range(at: 2), in: text) { args = String(text[r]) }
            let words = args.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if words.contains(where: helperWords.contains) { continue }
            pids.append(pid)
        }
        return pids
    }

    /// `lsof -Fpn` output to one entry per (pid, thread lock).
    public static func lockFds(fromLsof output: String) -> [CodexThread] {
        var out: [CodexThread] = []
        var pid: Int?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("p") {
                pid = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid {
                let path = String(line.dropFirst())
                let range = NSRange(path.startIndex..., in: path)
                if let match = lockPath.firstMatch(in: path, range: range), let r = Range(match.range(at: 1), in: path) {
                    out.append(CodexThread(pid: pid, threadId: String(path[r])))
                }
            }
        }
        return out
    }
}

/// The real adapter: `ps` and `lsof` through `Process`, `kill(2)` for the signals. Reads only, except `terminate`.
public struct SystemProcessAdapter: ProcessAdapter {
    public init() {}

    public func isAlive(pid: Int) async -> Bool {
        guard pid > 0, pid <= Int(Int32.max) else { return false }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    public func startTime(pid: Int) async -> String? {
        guard pid > 0 else { return nil }
        let result = await Self.run("/bin/ps", ["-o", "lstart=", "-p", String(pid)], timeout: 3)
        guard let result, result.status == 0 else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public func codexThreads() async -> [CodexThread] {
        guard let ps = await Self.run("/bin/ps", ["-axo", "pid=,args="], timeout: 5), ps.status == 0 else { return [] }
        let pids = ProcessOutputParser.codexPids(fromPS: ps.stdout)
        if pids.isEmpty { return [] }
        // lsof exits 1 when some of the pids are already gone but still prints the others, so its status is not checked.
        let lsof = await Self.run("/usr/sbin/lsof", ["-nP", "-Fpn", "-p", pids.map(String.init).joined(separator: ",")], timeout: 5)
        let locks = ProcessOutputParser.lockFds(fromLsof: lsof?.stdout ?? "")
        let held = Set(locks.map(\.pid))
        return locks + pids.filter { !held.contains($0) }.map { CodexThread(pid: $0, threadId: nil) }
    }

    public func terminate(pid: Int) async throws {
        guard pid > 0, pid <= Int(Int32.max) else { throw ProcessSignalError.noSuchProcess }
        if kill(pid_t(pid), SIGTERM) == 0 { return }
        switch errno {
        case ESRCH: throw ProcessSignalError.noSuchProcess
        case EPERM: throw ProcessSignalError.notPermitted
        default: throw ProcessSignalError.failed(errno: errno)
        }
    }

    private struct Output {
        var stdout: String
        var status: Int32
    }

    /// Runs a tool with `TZ=UTC` and `LC_ALL=C` (ps prints its start time in UTC, which is how Claude writes `procStart`).
    /// Returns nil when it cannot start. A tool that outlives `timeout` seconds is terminated and its output so far is returned.
    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async -> Output? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                environment["TZ"] = "UTC"
                environment["LC_ALL"] = "C"
                process.environment = environment
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: Output(stdout: String(decoding: data, as: UTF8.self), status: process.terminationStatus))
            }
        }
    }
}
