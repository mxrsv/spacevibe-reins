import Foundation
import os

/// One running core process and the pipe to it: requests out, a dedicated reader thread for the lines that come back.
/// A session never restarts; when its process dies every pending request fails with `Lost` and `CoreConnection` starts a
/// new session. All state sits behind `lock`; the reader thread is the only caller of `handle` and `end`.
final class CoreSession: @unchecked Sendable {
    /// The process is gone. `sent` is false when the request never left this side (a dead pipe), true when the core may
    /// have received it. Only an unsent request, or a read, is ever sent again.
    struct Lost: Error {
        let sent: Bool
    }

    private struct Pending {
        let isRead: Bool
        let continuation: CheckedContinuation<Data, Error>
        let progress: (@Sendable (CoreUsageProgress) -> Void)?
    }

    private static let logger = Logger(subsystem: "dev.spacevibe.reins", category: "core")
    private static let readSize = 64 * 1024

    let process: Process
    var processIdentifier: Int32 { process.processIdentifier }

    private let stdin: FileHandle
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var dead = false
    private var onActivity: (@Sendable (CoreActivityReport) -> Void)?
    private var onEnd: (@Sendable (CoreSession) -> Void)?
    private let onWritten: @Sendable (String) -> Void

    var isAlive: Bool { lock.withLock { !dead } }

    /// Starts the process with `["rpc"]` as argv (no shell). `environment` nil inherits ours.
    /// `onWritten` is told the method of every line that left this side (a test counts what reached the pipe).
    init(
        binary: URL, environment: [String: String]?,
        onActivity: @escaping @Sendable (CoreActivityReport) -> Void, onEnd: @escaping @Sendable (CoreSession) -> Void,
        onWritten: @escaping @Sendable (String) -> Void
    ) throws {
        // A write to a pipe whose reader died must fail with EPIPE, not kill the app with SIGPIPE.
        let input = Pipe(), output = Pipe(), errors = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process = Process()
        process.executableURL = binary
        process.arguments = ["rpc"]
        // Assigning nil leaves the child with an empty environment (macOS 27), so "inherit ours" is spelled out.
        process.environment = environment ?? ProcessInfo.processInfo.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { finished in
            Self.logger.debug("core exited with status \(finished.terminationStatus)")
        }
        // The core's log: fixed reasons only (docs/internals/core-protocol.md). Drained so a full pipe never blocks it.
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else if let text = String(data: chunk, encoding: .utf8) {
                Self.logger.debug("core: \(text, privacy: .public)")
            }
        }
        stdin = input.fileHandleForWriting
        self.onActivity = onActivity
        self.onEnd = onEnd
        self.onWritten = onWritten
        try process.run()
        // The parent's copies of the child's ends must close, or EOF never reaches the reader.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let reading = output.fileHandleForReading
        let thread = Thread { [self] in readLoop(reading) }
        thread.name = "spacevibe-core-reader"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // MARK: Requests

    /// Sends one request line and waits for its answer: the whole response line, for the caller to decode. A read is
    /// answered with `CancellationError` as soon as the task is cancelled; a write keeps waiting, because once the core
    /// has started it the real result (and its Undo entry) must not be hidden.
    func request(id: Int, method: String, line: Data, isRead: Bool, progress: (@Sendable (CoreUsageProgress) -> Void)? = nil) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                lock.lock()
                if dead {
                    lock.unlock()
                    continuation.resume(throwing: Lost(sent: false))
                    return
                }
                pending[id] = Pending(isRead: isRead, continuation: continuation, progress: progress)
                lock.unlock()
                do {
                    try write(line, method: method)
                } catch {
                    // Unsent: the pipe is dead. Whoever removes the entry resumes it, so the reader's `end` cannot double-resume.
                    if let entry = take(id) { entry.continuation.resume(throwing: Lost(sent: false)) }
                    return
                }
                // The cancel handler may have run before the entry existed.
                if Task.isCancelled { cancel(id) }
            }
        } onCancel: {
            cancel(id)
        }
    }

    private func take(_ id: Int) -> Pending? {
        lock.withLock { pending.removeValue(forKey: id) }
    }

    private func cancel(_ id: Int) {
        let entry: Pending? = lock.withLock {
            guard let entry = pending[id] else { return nil }
            if entry.isRead { pending[id] = nil }
            return entry
        }
        guard let entry else { return }
        struct Cancel: Encodable { let id: Int }
        let method = "$/cancelRequest"
        if let line = try? CoreWire.line(id: nil, method: method, params: Cancel(id: id)) { try? write(line, method: method) }
        if entry.isRead { entry.continuation.resume(throwing: CancellationError()) }
    }

    private func write(_ line: Data, method: String) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard isAlive else { throw Lost(sent: false) }
        try stdin.write(contentsOf: line)
        onWritten(method)
    }

    /// Ends the process: the reader sees EOF and fails whatever is pending. Safe before `initialize`, when nothing can have
    /// been written yet.
    func abort() {
        if process.isRunning { process.terminate() }
    }

    /// Returns when the process has died, or at once when the calling task is cancelled.
    func waitUntilDead() async {
        let token = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if dead || Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters[token] = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.withLock { waiters.removeValue(forKey: token) }?.resume()
        }
    }

    /// Closes the core's stdin so it drains and exits (docs/internals/core-protocol.md, "Shutdown"). Pending requests fail.
    func close() {
        try? stdin.close()
        end(notify: false)
    }

    // MARK: Reader thread

    /// Raw `read(2)`: `FileHandle.read(upToCount:)` waits for the whole count, so a short reply would sit unseen.
    private func readLoop(_ pipe: FileHandle) {
        let descriptor = pipe.fileDescriptor
        var chunk = [UInt8](repeating: 0, count: Self.readSize)
        var buffer = Data()
        while true {
            let count = read(descriptor, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { break }
            buffer.append(chunk, count: count)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex ..< newline]
                if !line.isEmpty { handle(Data(line)) }
                buffer.removeSubrange(buffer.startIndex ... newline)
            }
        }
        end(notify: true)
    }

    private func handle(_ line: Data) {
        guard let envelope = try? CoreWire.decode(CoreWire.Envelope.self, from: line) else {
            Self.logger.debug("core sent a line that is not a JSON-RPC message")
            return
        }
        if let method = envelope.method {
            notify(method, line)
        } else if let id = envelope.id, let entry = take(id) {
            if let error = envelope.error {
                entry.continuation.resume(throwing: CoreRPCFailure(error: error))
            } else {
                entry.continuation.resume(returning: line)
            }
        }
    }

    private func notify(_ method: String, _ line: Data) {
        switch method {
        case "activity/report":
            if let note = try? CoreWire.decode(CoreWire.Note<CoreActivityReport>.self, from: line) { onActivity?(note.params) }
        case "usage/progress":
            guard let note = try? CoreWire.decode(CoreWire.Note<CoreWire.ProgressParams>.self, from: line) else { return }
            let report = lock.withLock { pending[note.params.id]?.progress }
            report?(CoreUsageProgress(done: note.params.done, total: note.params.total))
        default:
            break
        }
    }

    /// The process is gone (`notify`, from the reader) or we closed its stdin (not `notify`). Only the first call acts;
    /// a core that is draining after `close()` is left to finish its in-flight write.
    private func end(notify: Bool) {
        lock.lock()
        if dead {
            lock.unlock()
            return
        }
        dead = true
        let entries = Array(pending.values)
        let sleepers = Array(waiters.values)
        let callback = onEnd
        pending = [:]
        waiters = [:]
        onEnd = nil
        onActivity = nil
        lock.unlock()
        for entry in entries { entry.continuation.resume(throwing: Lost(sent: true)) }
        for sleeper in sleepers { sleeper.resume() }
        guard notify else { return }
        if process.isRunning { process.terminate() }
        callback?(self)
    }
}
