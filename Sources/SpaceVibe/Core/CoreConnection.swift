import Foundation
import os

/// The one live connection to the Go core: starts the process on first use, does the `initialize` handshake, restarts it
/// with backoff after it dies, and turns a session's answers into typed results.
///
/// Restart policy (docs/internals/core-protocol.md, plan S.2):
/// - Restarts are lazy: the next request, or a live Activity subscription, starts a new session. Requests that arrive
///   while it starts wait for it.
/// - A request in flight when the core died fails with the fixed "restarted" `CoreError`. Only a read is sent again, once,
///   on the new core; a write is never sent again, because the dead core may already have applied it. A request that never
///   left this side (a dead pipe) is safe to send again whatever it is.
/// - The delay before a start grows (0.25 s, 0.5 s, ... up to 5 s) while the core keeps dying without answering a request.
final class CoreConnection: @unchecked Sendable {
    /// Methods that change nothing and may be sent again after a restart. Every other method, including one this list
    /// does not know, is treated as a write.
    static let readMethods: Set<String> = [
        "inventory.read", "usage.scan", "loadout.rows", "activity.read", "journal.history",
        "rules.snapshot", "rules.preview", "rules.check", "limits.read",
    ]
    private static let maxBackoff = 5.0
    private static let logger = Logger(subsystem: "dev.spacevibe.app", category: "core")

    private struct ClientInfo: Encodable {
        let name: String
        let version: String
    }

    private struct InitializeParams: Encodable {
        let protocolVersion: Int
        let client: ClientInfo
    }

    private let binary: URL
    private let environment: [String: String]?
    private let client: ClientInfo
    private let handshakeTimeout: Duration

    private let lock = NSLock()
    private var session: CoreSession?
    private var starting: Task<CoreSession, Error>?
    private var failures = 0
    private var incompatible: CoreError?
    private var closed = false
    private var nextID = 1
    private var sinks: [UUID: CoreActivitySink] = [:]
    private var sent: [String: Int] = [:]
    private var identity: CoreInitializeResult?

    init(binary: URL, environment: [String: String]?, clientName: String = "SpaceVibe", clientVersion: String, handshakeTimeout: Duration = .seconds(10)) {
        self.handshakeTimeout = handshakeTimeout
        self.binary = binary
        self.environment = environment
        client = ClientInfo(name: clientName, version: clientVersion)
    }

    // MARK: Requests

    /// Sends one request and decodes its answer. Throws a `CoreError` for the engine's refusal and for every fault of the
    /// helper, and `CancellationError` for a cancelled call. `progress` gets the `usage/progress` notifications.
    func call<R: Decodable>(
        _ method: String,
        _ params: some Encodable = CoreWire.NoParams(),
        as _: R.Type = R.self,
        progress: (@Sendable (CoreUsageProgress) -> Void)? = nil
    ) async throws -> R {
        let isRead = Self.readMethods.contains(method)
        var attempts = 0
        while true {
            try Task.checkCancellation()
            attempts += 1
            let session = try await liveSession()
            let id = lock.withLock { () -> Int in
                defer { nextID += 1 }
                return nextID
            }
            do {
                let line = try await session.request(
                    id: id, method: method, line: try CoreWire.line(id: id, method: method, params: params), isRead: isRead, progress: progress
                )
                lock.withLock { failures = 0 }
                do {
                    return try CoreWire.reply(R.self, from: line)
                } catch {
                    throw CoreError(CoreWire.undecodableMessage, status: 500)
                }
            } catch let lost as CoreSession.Lost {
                if attempts < 2, !lost.sent || isRead { continue }
                throw CoreError(CoreWire.restartedMessage, status: 500)
            } catch let failure as CoreRPCFailure {
                throw CoreWire.error(from: failure.error)
            }
        }
    }

    /// How many lines for `method` reached the core's pipe, retries included. A test reads it to prove a write was not
    /// sent again, and that a cancel was sent.
    func sentCount(_ method: String) -> Int { lock.withLock { sent[method] ?? 0 } }

    /// What the core said about itself in its last `initialize`; starts the core when there is none yet.
    func handshake() async throws -> CoreInitializeResult {
        _ = try await liveSession()
        return try lock.withLock {
            guard let identity else { throw CoreError(CoreWire.startFailedMessage, status: 500) }
            return identity
        }
    }

    /// The current core's process, for a test that signals or watches it.
    var process: Process? { lock.withLock { session?.isAlive == true ? session?.process : nil } }
    var processIdentifier: Int32? { process?.processIdentifier }

    /// Closes the core's stdin so it exits, and stops restarting it.
    func shutdown() {
        let current: CoreSession? = lock.withLock {
            closed = true
            defer { session = nil }
            return session
        }
        current?.close()
    }

    // MARK: Activity

    func addSink(_ sink: CoreActivitySink) -> UUID {
        let token = UUID()
        lock.withLock { sinks[token] = sink }
        return token
    }

    /// How long the last subscriber's removal waits before `activity.unsubscribe` is sent. A tab or window that comes back inside
    /// it keeps the running subscription instead of racing a late unsubscribe against its new `activity.subscribe`.
    static let unsubscribeDelay: Duration = .seconds(1)

    /// Removes a subscriber; the core stops polling only when the last one is gone and still is after `unsubscribeDelay`.
    func removeSink(_ token: UUID) {
        let last: Bool = lock.withLock {
            sinks[token] = nil
            return sinks.isEmpty
        }
        guard last else { return }
        Task { [self] in
            try? await Task.sleep(for: Self.unsubscribeDelay)
            let current: CoreSession? = lock.withLock { sinks.isEmpty ? session : nil }
            guard let current, current.isAlive else { return }
            let id = lock.withLock { () -> Int in defer { nextID += 1 }; return nextID }
            if let line = try? CoreWire.line(id: id, method: "activity.unsubscribe", params: CoreWire.NoParams()) {
                _ = try? await current.request(id: id, method: "activity.unsubscribe", line: line, isRead: true)
            }
        }
    }

    /// `activity.subscribe` on the current core, delivering the snapshot (and any push that follows it) to `sink`. Returns
    /// the session that holds the subscription, so the caller can wait for its death and subscribe again.
    func subscribe(_ sink: CoreActivitySink) async throws -> CoreSession {
        var attempts = 0
        while true {
            try Task.checkCancellation()
            attempts += 1
            let session = try await liveSession()
            let id = lock.withLock { () -> Int in defer { nextID += 1 }; return nextID }
            sink.reset()
            do {
                let line = try await session.request(
                    id: id, method: "activity.subscribe", line: try CoreWire.line(id: id, method: "activity.subscribe", params: CoreWire.NoParams()), isRead: true
                )
                guard let report = try? CoreWire.reply(CoreActivityReport.self, from: line) else {
                    throw CoreError(CoreWire.undecodableMessage, status: 500)
                }
                lock.withLock { failures = 0 }
                sink.deliver(report)
                return session
            } catch is CoreSession.Lost {
                if attempts < 3 { continue }
                throw CoreError(CoreWire.restartedMessage, status: 500)
            } catch let failure as CoreRPCFailure {
                throw CoreWire.error(from: failure.error)
            }
        }
    }

    private func deliver(_ report: CoreActivityReport) {
        let all = lock.withLock { Array(sinks.values) }
        for sink in all { sink.push(report) }
    }

    // MARK: Starting

    /// The running session, started (once, however many callers wait) when there is none.
    private func liveSession() async throws -> CoreSession {
        let task: Task<CoreSession, Error> = try lock.withLock {
            if closed { throw CoreError(CoreWire.closedMessage, status: 500) }
            if let incompatible { throw incompatible }
            if let session, session.isAlive { return Task<CoreSession, Error> { session } }
            if let starting { return starting }
            let task = Task { try await self.start() }
            starting = task
            return task
        }
        return try await task.value
    }

    private func start() async throws -> CoreSession {
        defer { lock.withLock { starting = nil } }
        let delay = lock.withLock { failures <= 1 ? 0 : min(0.25 * pow(2, Double(failures - 2)), Self.maxBackoff) }
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        do {
            let session = try spawn()
            let result = try await handshake(on: session)
            lock.withLock {
                self.session = session
                identity = result
            }
            return session
        } catch {
            lock.withLock { failures += 1 }
            throw error
        }
    }

    private func spawn() throws -> CoreSession {
        do {
            return try CoreSession(
                binary: binary,
                environment: environment,
                onActivity: { [weak self] report in self?.deliver(report) },
                onEnd: { [weak self] ended in self?.sessionEnded(ended) },
                onWritten: { [weak self] method in self?.lock.withLock { self?.sent[method, default: 0] += 1 } }
            )
        } catch {
            Self.logger.debug("core could not be started")
            throw CoreError(CoreWire.startFailedMessage, status: 500)
        }
    }

    private func handshake(on session: CoreSession) async throws -> CoreInitializeResult {
        let id = lock.withLock { () -> Int in defer { nextID += 1 }; return nextID }
        // A core that starts but never answers must not block every caller: end it after the deadline. Nothing can have been
        // written before `initialize`, so ending it loses nothing.
        let timeout = handshakeTimeout
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            session.abort()
        }
        defer { watchdog.cancel() }
        do {
            let line = try await session.request(
                id: id,
                method: "initialize",
                line: try CoreWire.line(id: id, method: "initialize", params: InitializeParams(protocolVersion: CoreProtocol.version, client: client)),
                isRead: true
            )
            let result = try CoreWire.reply(CoreInitializeResult.self, from: line)
            guard result.protocolVersion == CoreProtocol.version else { throw CoreRPCFailure(error: Self.mismatch) }
            return result
        } catch let failure as CoreRPCFailure where failure.error.code == CoreWire.versionMismatchCode {
            // The helper speaks another protocol: a fixed startup problem, and no restart loop.
            let problem = CoreError(CoreWire.incompatibleMessage, status: 500)
            lock.withLock { incompatible = problem }
            session.close()
            throw problem
        } catch is CoreSession.Lost {
            throw CoreError(CoreWire.startFailedMessage, status: 500)
        } catch let failure as CoreRPCFailure {
            session.close()
            throw CoreWire.error(from: failure.error)
        } catch let error as CoreError {
            session.close()
            throw error
        } catch {
            session.close()
            throw CoreError(CoreWire.undecodableMessage, status: 500)
        }
    }

    private static let mismatch = CoreRPCError(code: CoreWire.versionMismatchCode, message: "Protocol version not supported.", data: nil)

    /// A session whose process died. Counts toward the backoff when it was the live one.
    private func sessionEnded(_ ended: CoreSession) {
        lock.withLock {
            guard session === ended else { return }
            session = nil
            failures += 1
        }
    }
}
