import Foundation
import Testing
@testable import SpaceVibe

/// Two Activity subscribers on one `CoreConnection` (the Activity page and the glance widget), against a shell script that
/// stands in for the core: it logs the method of every line it reads, answers `initialize`, answers the first
/// `activity.subscribe` with a report holding one session and every later one with an empty report, and never pushes. That is
/// the real core after the last live session ended: its baseline is the newest snapshot, so it stays silent.
@Suite("CoreConnection subscribers", .fixtureCLIs)
struct CoreActivitySubscribersTests {
    /// One consumed stream: a task collects what it yields until it is cancelled.
    private final class Reader: Sendable {
        let reports: LockedList<CoreActivityReport>
        private let task: Task<Void, Never>

        init(_ stream: AsyncThrowingStream<CoreActivityReport, Error>) {
            let reports = LockedList<CoreActivityReport>()
            self.reports = reports
            task = Task {
                do {
                    for try await report in stream { reports.append(report) }
                } catch {}
            }
        }

        func end() { task.cancel() }
    }

    private static let oneSession = CoreActivityReport(
        sessions: [CoreActivitySession(
            cli: .claude, id: "s1", title: "task s1", project: nil, pid: 100, state: .running, stateReason: "log written 2 s ago",
            reasonCode: nil, currentTool: nil, ageMs: nil, lastWriteAgoMs: 2_000, cost: nil, costNote: nil
        )],
        failures: [], files: [], unmeasurable: [], stats: CoreActivityStats(logs: 1, truncated: 0)
    )
    private static let noSession = CoreActivityReport(sessions: [], failures: [], files: [], unmeasurable: [], stats: CoreActivityStats(logs: 1, truncated: 0))

    private func withFakeCore<T>(_ body: (CoreClient, _ methods: () -> [String]) async throws -> T) async throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-subscribers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("methods")
        let identity = CoreInitializeResult(
            protocolVersion: CoreProtocol.version, core: .init(name: "spacevibe", version: "test"),
            identity: .init(envPrefix: "SPACEVIBE", dataDir: folder.path), methods: ["activity.subscribe", "activity.unsubscribe"]
        )
        func json(_ value: some Encodable) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        let script = folder.appendingPathComponent("spacevibe")
        try """
        #!/bin/sh
        INIT='\(try json(identity))'
        ONE='\(try json(Self.oneSession))'
        NONE='\(try json(Self.noSession))'
        n=0
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p')
          method=$(printf '%s' "$line" | sed -n 's/.*"method":"\\([^"]*\\)".*/\\1/p')
          echo "$method" >> '\(log.path)'
          case "$method" in
            initialize) printf '%s\\n' "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":$id,\\"result\\":$INIT}" ;;
            activity.subscribe)
              n=$((n + 1))
              if [ "$n" -eq 1 ]; then report=$ONE; else report=$NONE; fi
              printf '%s\\n' "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":$id,\\"result\\":$report}" ;;
            activity.unsubscribe) printf '%s\\n' "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":$id,\\"result\\":{}}" ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CoreClient(binary: script)
        defer { client.shutdown() }
        let methods = { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        return try await body(client, methods)
    }

    private func eventually(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("a second subscriber's snapshot also reaches the first, so an ended session leaves both", .timeLimit(.minutes(1)))
    func snapshotReachesEverySink() async throws {
        try await withFakeCore { client, _ in
            let widget = Reader(client.activitySubscribe())
            defer { widget.end() }
            #expect(await eventually { widget.reports.values == [Self.oneSession] })
            let page = Reader(client.activitySubscribe())
            defer { page.end() }
            #expect(await eventually { page.reports.values == [Self.noSession] })
            // The core's baseline is now the empty report and it pushes nothing more: the widget must have it already.
            #expect(await eventually { widget.reports.values == [Self.oneSession, Self.noSession] })
        }
    }

    @Test("a subscribe that starts while the last sink's unsubscribe is under way reaches the core after it", .timeLimit(.minutes(1)))
    func unsubscribeNeverOvertakesASubscribe() async throws {
        try await withFakeCore { client, methods in
            let first = Reader(client.activitySubscribe())
            #expect(await eventually { first.reports.values.count == 1 })
            let later = LockedList<Reader>()
            // Between the unsubscribe's decision and its line, a new subscriber comes and gets time to send its subscribe.
            client.connection.beforeUnsubscribe = {
                guard later.values.isEmpty else { return }
                later.append(Reader(client.activitySubscribe()))
                try? await Task.sleep(for: .milliseconds(300))
            }
            first.end()
            #expect(await eventually(6) { later.values.first?.reports.values.count == 1 })
            #expect(await eventually { methods().filter { $0.hasPrefix("activity.") }.count == 3 })
            let activity = methods().filter { $0.hasPrefix("activity.") }
            #expect(activity == ["activity.subscribe", "activity.unsubscribe", "activity.subscribe"],
                    "the new subscription is the last word the core heard, so it keeps polling")
            later.values.first?.end()
            client.connection.beforeUnsubscribe = nil
        }
    }
}
