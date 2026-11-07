import Foundation
import Testing
@testable import SpaceVibe

/// `CoreSession` against small shell scripts that stand in for the helper: what leaves the pipe, in which order, and what
/// the reader does with very long lines.
@Suite("CoreSession")
struct CoreSessionTests {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var _methods: [String] = []
        private var _task: Task<Data, Error>?
        var methods: [String] { lock.withLock { _methods } }
        var task: Task<Data, Error>? { get { lock.withLock { _task } } set { lock.withLock { _task = newValue } } }
        func add(_ method: String) { lock.withLock { _methods.append(method) } }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var _set = false
        var isSet: Bool { lock.withLock { _set } }
        func set() { lock.withLock { _set = true } }
    }

    private func withScript<T>(_ body: String, _ run: (URL) async throws -> T) async throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("spacevibe")
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return try await run(script)
    }

    private func eventually(_ seconds: Double = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func scan(_ session: CoreSession, id: Int, isRead: Bool) async throws -> Data {
        try await session.request(id: id, method: "usage.scan", line: try CoreWire.line(id: id, method: "usage.scan", params: CoreWire.NoParams()), isRead: isRead)
    }

    @Test("a cancel from another thread never reaches the pipe before the request it cancels", .timeLimit(.minutes(1)))
    func cancelFollowsItsRequest() async throws {
        try await withScript("cat > /dev/null") { script in
            let log = Log()
            let ended = Flag()
            let session = try CoreSession(
                binary: script, environment: nil, onActivity: { _ in }, onEnd: { _ in ended.set() }, onWritten: { log.add($0) }
            )
            // Right after the request is registered, cancel it on another thread and give that thread time to write. A
            // session that lets the cancel through here writes it first; one that holds the request's line first makes the
            // cancel wait, so the half second runs out and the request goes out before it.
            session.afterRegister = { _ in
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    while log.task == nil { usleep(1000) }
                    log.task?.cancel()
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 0.5)
            }
            log.task = Task { try await scan(session, id: 7, isRead: false) }
            #expect(await eventually { log.methods.contains("$/cancelRequest") }, "the cancel was never written")
            #expect(log.methods.first == "usage.scan", "the written lines were \(log.methods)")
            session.close()
            _ = try? await log.task?.value
            #expect(!ended.isSet)
        }
    }

    @Test("a 20 MiB answer on one line arrives whole and quickly", .timeLimit(.minutes(1)))
    func largeLine() async throws {
        let body = """
        read line
        printf '{"jsonrpc":"2.0","id":1,"result":"'
        head -c 20971520 /dev/zero | tr '\\0' a
        printf '"}\\n'
        cat > /dev/null
        """
        try await withScript(body) { script in
            let session = try CoreSession(binary: script, environment: nil, onActivity: { _ in }, onEnd: { _ in }, onWritten: { _ in })
            defer { session.close() }
            let started = ContinuousClock.now
            let line = try await scan(session, id: 1, isRead: true)
            let took = ContinuousClock.now - started
            #expect(line.count > 20 * 1024 * 1024)
            #expect(took < .seconds(5), "reading the line took \(took)")
        }
    }

    @Test("a stream past the line cap ends the session and fails what is pending", .timeLimit(.minutes(1)))
    func overCap() async throws {
        let body = """
        read line
        head -c 70000000 /dev/zero | tr '\\0' a
        exec sleep 60
        """
        try await withScript(body) { script in
            let ended = Flag()
            let session = try CoreSession(binary: script, environment: nil, onActivity: { _ in }, onEnd: { _ in ended.set() }, onWritten: { _ in })
            defer { session.close() }
            let request = Task { try await scan(session, id: 1, isRead: true) }
            let dead = await eventually { !session.isAlive }
            #expect(dead, "the session stayed alive past the cap")
            guard dead else { return }
            #expect(ended.isSet, "the connection was not told, so it would not restart the core")
            let lost = await #expect(throws: CoreSession.Lost.self) { try await request.value }
            #expect(lost?.sent == true)
            // `end` fails the request first and terminates the process after, and SIGTERM is not instant.
            #expect(await eventually { !session.process.isRunning }, "the process outlived the session")
        }
    }
}
