import Foundation
import Testing
import ReinsCore
@testable import Reins

/// The journal is shared by both engines while both exist: an entry one records, the other undoes (plan G2.3, S.2).
/// "Byte-identical" is the whole home outside Reins' own folder, before the write and after the undo.
extension Dictionary where Key == String, Value == Data {
    /// The paths whose bytes differ, or that exist on only one side.
    func difference(from other: [String: Data]) -> [String] {
        Set(keys).union(other.keys).filter { self[$0] != other[$0] }.sorted()
    }
}

@Suite("Journal across engines")
struct CoreJournalInteropTests {
    private static let item = "claude:agent:local:architect.md"
    private static let file = ".claude/agents/architect.md"

    @Test("a Swift-recorded removal is undone by the Go core", .timeLimit(.minutes(1)))
    func swiftRecordsGoUndoes() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let before = try fixture.tree()

        let entry = try Mutate.removeItem(roots: try fixture.roots(), id: Self.item)
        let removed = try fixture.tree()
        #expect(removed[Self.file] == nil)
        #expect(removed != before)

        _ = try await client.inventoryRead()
        #expect(try await client.journalHistory().entries.map(\.id) == [entry.id])
        let undone = try await client.journalUndo(id: entry.id)
        #expect(undone.label == entry.label)
        let changed = try fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
        // The entry is marked undone for the Swift side too.
        #expect(Journal.history(try fixture.roots()).first?.undone == true)
    }

    @Test("a Go-recorded removal is undone by Swift's Journal.undo", .timeLimit(.minutes(1)))
    func goRecordsSwiftUndoes() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let before = try fixture.tree()

        _ = try await client.inventoryRead()
        let entry = try await client.loadoutRemoveItem(id: Self.item).entry
        let removed = try fixture.tree()
        #expect(removed[Self.file] == nil)
        #expect(removed != before)

        let roots = try fixture.roots()
        #expect(Journal.history(roots).map(\.id) == [entry.id])
        let label = try Journal.undo(roots, id: entry.id)
        #expect(label == entry.label)
        let changed = try fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
        #expect(try await client.journalHistory().entries.first?.undone == true)
    }
}
