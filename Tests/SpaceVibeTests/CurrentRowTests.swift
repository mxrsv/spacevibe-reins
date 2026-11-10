import Testing
@testable import SpaceVibe

/// D2: where the current row goes when a removal takes it off the list.
@Suite("Current row after a removal")
struct CurrentRowTests {
    private let rows = ["a", "b", "c", "d"]

    @Test("a middle row hands the key to the row after it")
    func middle() {
        #expect(CurrentRow.neighbour(of: ["b"], current: "b", in: rows) == "c")
    }

    @Test("the last row hands the key to the row before it, not to the first row")
    func last() {
        #expect(CurrentRow.neighbour(of: ["d"], current: "d", in: rows) == "c")
    }

    @Test("the first row hands the key to the row after it")
    func first() {
        #expect(CurrentRow.neighbour(of: ["a"], current: "a", in: rows) == "b")
        #expect(CurrentRow.neighbour(of: ["a"], current: nil, in: rows) == "b", "no choice made: the first row is the current one")
    }

    @Test("removed neighbours are skipped, forward first and then back")
    func skipsRemoved() {
        #expect(CurrentRow.neighbour(of: ["b", "c"], current: "b", in: rows) == "d")
        #expect(CurrentRow.neighbour(of: ["c", "d"], current: "c", in: rows) == "b")
    }

    @Test("every row removed leaves no current row")
    func allRemoved() {
        #expect(CurrentRow.neighbour(of: Set(rows), current: "b", in: rows) == nil)
    }

    @Test("a current row that stays keeps the key, chosen or not")
    func notRemoved() {
        #expect(CurrentRow.neighbour(of: ["b"], current: "c", in: rows) == "c")
        #expect(CurrentRow.neighbour(of: ["d"], current: nil, in: rows) == nil)
        #expect(CurrentRow.neighbour(of: [], current: "a", in: rows) == "a")
    }
}
