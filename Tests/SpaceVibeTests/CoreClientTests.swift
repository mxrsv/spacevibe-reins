import Foundation
import Testing
@testable import SpaceVibe

/// `CoreClient` against the real Go core that `scripts/test.sh` builds. Each test has its own fixture home and client,
/// because swift-testing runs tests in parallel.
@Suite("CoreClient")
struct CoreClientTests {
    private static let architect = "claude:agent:local:architect.md"

    private func withClient<T>(_ body: (CoreFixtureHome, CoreClient) async throws -> T) async throws -> T {
        let fixture = try CoreFixtureHome()
        let client = try fixture.client()
        defer {
            client.shutdown()
            fixture.remove()
        }
        return try await body(fixture, client)
    }

    /// Waits until `condition` holds, up to `seconds`.
    private func eventually(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: Handshake and reads

    @Test("the handshake reports the identity, and the Swift constants equal it", .timeLimit(.minutes(1)))
    func handshake() async throws {
        try await withClient { _, client in
            let hello = try await client.initialize()
            #expect(hello.protocolVersion == CoreProtocol.version)
            #expect(hello.core.name == "spacevibe")
            #expect(hello.identity.envPrefix == CoreProtocol.envPrefix)
            #expect(hello.identity.dataDir == ".spacevibe")
            #expect(hello.methods.contains("initialize"))
        }
    }

    @Test("reads on the fixture home decode into their DTOs", .timeLimit(.minutes(1)))
    func reads() async throws {
        try await withClient { fixture, client in
            let inventory = try await client.inventoryRead()
            #expect(inventory.items.count > 20)
            #expect(inventory.roots["claude"] == fixture.home.appendingPathComponent(".claude").path)
            #expect(try await client.loadoutRows().usage == .scanning)
            #expect(try await client.limitsRead().limits.map(\.cli) == [.claude, .codex, .gemini])
            #expect(try await client.journalHistory().entries.isEmpty)
            #expect(try await client.rulesCheck(rule: "Bash(ls)").valid)
            #expect(try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: false).scope == .global)
            _ = try await client.activityRead()
        }
    }

    @Test("usage.scan reports progress and its result ends the loadout's scanning state", .timeLimit(.minutes(1)))
    func usageScan() async throws {
        try await withClient { _, client in
            let seen = LockedList<CoreUsageProgress>()
            let result = try await client.usageScan { seen.append($0) }
            #expect(result.files > 0)
            #expect(await eventually { seen.values.last.map { $0.done == $0.total } == true })
            #expect(try await client.loadoutRows().usage == .ready)
        }
    }

    @Test("a refusal arrives as a CoreError with the engine's status and sentence", .timeLimit(.minutes(1)))
    func refusal() async throws {
        try await withClient { _, client in
            let error = try await #require(throws: CoreError.self) { try await client.loadoutRemoveItem(id: "claude:agent:local:no-such.md") }
            #expect(error.status == 404)
            #expect(error.message == "This item no longer exists. Refresh the list.")
        }
    }

    @Test("a refused environment is a startup problem every method reports, and initialize still answers", .timeLimit(.minutes(1)))
    func startupProblem() async throws {
        let fixture = try CoreFixtureHome(extraEnvironment: ["SPACEVIBE_TEST": "2"])
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        #expect(try await client.initialize().identity.envPrefix == CoreProtocol.envPrefix)
        let error = try await #require(throws: CoreError.self) { try await client.inventoryRead() }
        #expect(error.status == 500)
        #expect(error.message.contains("SPACEVIBE_TEST"))
    }

    // MARK: Restart

    @Test("after kill -9 the next read starts a new core and succeeds", .timeLimit(.minutes(1)))
    func restartAfterKill() async throws {
        try await withClient { _, client in
            _ = try await client.initialize()
            let first = try #require(client.connection.processIdentifier)
            kill(first, SIGKILL)
            #expect(try await client.inventoryRead().items.count > 20)
            let second = try #require(client.connection.processIdentifier)
            #expect(second != first)
        }
    }

    @Test("a write in flight when the core dies fails with the restarted error and is never sent again", .timeLimit(.minutes(1)))
    func writeNotRetried() async throws {
        try await withClient { fixture, client in
            _ = try await client.inventoryRead()
            let pid = try #require(client.connection.processIdentifier)
            kill(pid, SIGSTOP)
            let write = Task { try await client.loadoutRemoveItem(id: Self.architect) }
            #expect(await eventually { client.connection.sentCount("loadout.removeItem") == 1 })
            kill(pid, SIGKILL)
            let error = await #expect(throws: CoreError.self) { try await write.value }
            #expect(error?.message == CoreWire.restartedMessage)
            #expect(error?.status == 500)
            #expect(client.connection.sentCount("loadout.removeItem") == 1)
            // The new core never saw the write: nothing moved, nothing recorded.
            #expect(try await client.journalHistory().entries.isEmpty)
            #expect(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent(".claude/agents/architect.md").path))
            #expect(client.connection.sentCount("loadout.removeItem") == 1)
        }
    }

    // MARK: Cancellation

    @Test("cancelling a read returns CancellationError at once, and the late answer does no harm", .timeLimit(.minutes(1)))
    func cancelRead() async throws {
        try await withClient { _, client in
            _ = try await client.initialize()
            let pid = try #require(client.connection.processIdentifier)
            kill(pid, SIGSTOP)
            let read = Task { try await client.inventoryRead() }
            #expect(await eventually { client.connection.sentCount("inventory.read") == 1 })
            let started = Date()
            read.cancel()
            await #expect(throws: CancellationError.self) { try await read.value }
            #expect(Date().timeIntervalSince(started) < 2)
            #expect(client.connection.sentCount("$/cancelRequest") == 1)
            kill(pid, SIGCONT)
            #expect(try await client.limitsRead().limits.count == 3)
            #expect(client.connection.processIdentifier == pid)
        }
    }

    @Test("ten mixed reads at once each get their own answer", .timeLimit(.minutes(1)))
    func concurrentReads() async throws {
        try await withClient { _, client in
            try await withThrowingTaskGroup(of: String.self) { group in
                for index in 0 ..< 10 {
                    group.addTask {
                        switch index % 3 {
                        case 0: return "inventory:\(try await client.inventoryRead().items.count > 20)"
                        case 1: return "limits:\(try await client.limitsRead().limits.count)"
                        default: return "check:\(try await client.rulesCheck(rule: "Bash(ls)").valid)"
                        }
                    }
                }
                var seen: [String] = []
                for try await answer in group { seen.append(answer) }
                #expect(seen.filter { $0 == "inventory:true" }.count == 4)
                #expect(seen.filter { $0 == "limits:3" }.count == 3)
                #expect(seen.filter { $0 == "check:true" }.count == 3)
            }
        }
    }

    // MARK: Shutdown

    @Test("shutdown closes the core's stdin and the core exits", .timeLimit(.minutes(1)))
    func shutdownEndsCore() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        _ = try await client.initialize()
        let core = try #require(client.connection.process)
        #expect(core.isRunning)
        client.shutdown()
        #expect(await eventually(6) { !core.isRunning })
        #expect(core.terminationStatus == 0)
        await #expect(throws: CoreError.self) { try await client.inventoryRead() }
    }

    @Test("releasing the client ends the core", .timeLimit(.minutes(1)))
    func deinitEndsCore() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        var client: CoreClient? = try fixture.client()
        _ = try await #require(client).initialize()
        let core = try #require(client?.connection.process)
        client = nil
        #expect(await eventually(6) { !core.isRunning })
        #expect(core.terminationStatus == 0)
    }

    // MARK: Activity

    @Test("an Activity subscription starts with a snapshot and takes a fresh one after the core restarts", .timeLimit(.minutes(1)))
    func activityResubscribes() async throws {
        try await withClient { _, client in
            var iterator = client.activitySubscribe().makeAsyncIterator()
            let first = try await iterator.next()
            #expect(first != nil)
            let pid = try #require(client.connection.processIdentifier)
            kill(pid, SIGKILL)
            let again = try await iterator.next()
            #expect(again != nil)
            #expect(try #require(client.connection.processIdentifier) != pid)
        }
    }

    // MARK: Startup failures

    @Test("a helper that speaks another protocol version is a fixed startup problem, not a restart loop", .timeLimit(.minutes(1)))
    func versionMismatch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-fake-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("spacevibe")
        let reply = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"Protocol version not supported.","data":{"protocolVersion":2}}}"#
        let launches = folder.appendingPathComponent("launches")
        try "#!/bin/sh\necho started >> '\(launches.path)'\nread line\necho '\(reply)'\nread line\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CoreClient(binary: script)
        defer { client.shutdown() }
        for _ in 0 ..< 2 {
            let error = try await #require(throws: CoreError.self) { try await client.inventoryRead() }
            #expect(error.message == CoreWire.incompatibleMessage)
        }
        // One launch: the second call hit the stored problem instead of starting the helper again.
        #expect(try String(contentsOf: launches, encoding: .utf8).split(separator: "\n").count == 1)
    }

    @Test("a helper that never answers initialize is ended after the deadline", .timeLimit(.minutes(1)))
    func silentHelper() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-silent-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("spacevibe")
        try "#!/bin/sh\nexec sleep 60\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CoreClient(binary: script, handshakeTimeout: .milliseconds(400))
        defer { client.shutdown() }
        let started = Date()
        let error = try await #require(throws: CoreError.self) { try await client.inventoryRead() }
        #expect(error.message == CoreWire.startFailedMessage)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("a client given no environment starts the helper with ours, so the folders it names reach the core", .timeLimit(.minutes(1)))
    func inheritsEnvironment() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-env-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("spacevibe")
        let seen = folder.appendingPathComponent("seen")
        try "#!/bin/sh\nprintf '%s' \"$HOME\" > '\(seen.path)'\nread line\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CoreClient(binary: script, handshakeTimeout: .milliseconds(400))
        defer { client.shutdown() }
        _ = try? await client.inventoryRead()
        #expect(try String(contentsOf: seen, encoding: .utf8) == ProcessInfo.processInfo.environment["HOME"])
    }

    @Test("a missing helper is a fixed startup problem", .timeLimit(.minutes(1)))
    func missingBinary() async throws {
        let client = CoreClient(binary: URL(fileURLWithPath: "/nonexistent/spacevibe"))
        let error = try await #require(throws: CoreError.self) { try await client.inventoryRead() }
        #expect(error.message == CoreWire.startFailedMessage)
    }
}

/// A list a `@Sendable` callback appends to.
final class LockedList<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []
    func append(_ element: Element) { lock.withLock { items.append(element) } }
    var values: [Element] { lock.withLock { items } }
}
