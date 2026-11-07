import Foundation
import Testing
import ReinsCore
@testable import Reins

/// X-lock: the Swift engine and the Go core write ONE journal under one data folder at the same time (plan X-lock). Without
/// the cross-process `flock` the two read the same `journal.json`, and the later write drops the earlier entry.
@Suite("Write lock across processes")
struct CoreWriteLockInteropTests {
    private static let swiftThreads = 3
    private static let swiftWritesPerThread = 15
    private static let goWrites = 45

    private func journalIDs(_ fixture: CoreFixtureHome) throws -> [String] {
        let data = try Data(contentsOf: fixture.data.appendingPathComponent("journal.json"))
        let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return entries.compactMap { $0["id"] as? String }
    }

    @Test("concurrent Swift writers and a real Go core lose no journal entry", .timeLimit(.minutes(2)))
    func noLostEntry() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let roots = try fixture.roots()
        let client = try fixture.client()
        defer { client.shutdown() }
        _ = try await client.initialize()

        // Go: one core, writes in order (they serialize anyway); the concurrency is Swift against Go. Each toggle changes the
        // file, so each records an entry; a no-op (`entry: null`) would record none and is simply not counted.
        let go = Task { () -> [String] in
            var ids: [String] = []
            for index in 0 ..< Self.goWrites {
                let verdict: CoreVerdict = index.isMultiple(of: 2) ? .deny : .allow
                let result = try await client.rulesSetCapability(scope: .global, dir: nil, capability: .read, verdict: verdict)
                if let entry = result.entry { ids.append(entry.id) }
            }
            return ids
        }
        // Swift: several threads, each editing files of its own, so only the journal is shared.
        let swift = Task.detached { () -> [String] in
            let ids = IDList()
            DispatchQueue.concurrentPerform(iterations: Self.swiftThreads) { thread in
                for index in 0 ..< Self.swiftWritesPerThread {
                    let file = roots.claude.root.appendingPathComponent("swift-writer-\(thread)-\(index).txt")
                    do {
                        let entry = try FileEdit.edit(roots, file: file, label: "Swift writer \(thread)-\(index)") { _ in "written by thread \(thread), write \(index)\n" }
                        if let entry { ids.append(entry.id) }
                    } catch {
                        ids.fail("\(error)")
                    }
                }
            }
            #expect(ids.failures.isEmpty, "\(ids.failures)")
            return ids.values
        }
        let (goIDs, swiftIDs) = try await (go.value, swift.value)

        #expect(swiftIDs.count == Self.swiftThreads * Self.swiftWritesPerThread)
        #expect(goIDs.count >= Self.goWrites - 1, "almost every toggle changes the file")
        let journal = try journalIDs(fixture)
        let written = goIDs + swiftIDs
        #expect(written.count < 200, "the journal keeps 200 entries; stay under it")
        #expect(journal.count == written.count, "journal holds \(journal.count) entries, \(written.count) were written")
        let lost = Set(written).subtracting(journal)
        #expect(lost.isEmpty, "\(lost.count) written entries are missing from the journal")
    }

    @Test("the lock file is 0600 in a 0700 data folder, as Go makes it", .timeLimit(.minutes(1)))
    func lockFileMode() throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let roots = try fixture.roots()
        _ = try FileEdit.edit(roots, file: roots.claude.root.appendingPathComponent("probe.txt"), label: "Probe") { _ in "x\n" }
        func mode(_ url: URL) throws -> Int { try #require((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue) }
        #expect(try mode(fixture.data.appendingPathComponent("write.lock")) == 0o600)
        #expect(try mode(fixture.data) == 0o700)
    }
}

private final class IDList: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    private var errors: [String] = []
    func append(_ id: String) { lock.withLock { ids.append(id) } }
    func fail(_ message: String) { lock.withLock { errors.append(message) } }
    var values: [String] { lock.withLock { ids } }
    var failures: [String] { lock.withLock { errors } }
}
