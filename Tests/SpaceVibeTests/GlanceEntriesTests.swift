import Foundation
import Testing
@testable import SpaceVibe

/// GL-T3: a `CoreActivityReport` becomes the glance widget's entries (GW-R2 to GW-R5, GW8 to GW12). Synthetic sessions only.
@Suite("Glance entries", .fixtureCLIs)
struct GlanceEntriesTests {
    private static let minute = 60_000.0

    private func session(_ id: String, cli: CLIID = .claude, state: CoreSessionState = .running, lastWrite: Double? = 1_000,
                         tool: CoreActivityTool? = nil, pid: Int = 4100, reason: String = "log written 1 s ago") -> CoreActivitySession {
        CoreActivitySession(cli: cli, id: id, title: "Task \(id)", project: nil, pid: pid, state: state, stateReason: reason, reasonCode: nil,
                            currentTool: tool, ageMs: 3_600_000, lastWriteAgoMs: lastWrite, cost: nil, costNote: nil)
    }

    private func report(_ sessions: [CoreActivitySession]) -> CoreActivityReport {
        CoreActivityReport(sessions: sessions, failures: [], files: [], unmeasurable: [], stats: CoreActivityStats(logs: sessions.count, truncated: 0))
    }

    private func entries(_ sessions: [CoreActivitySession]) -> GlanceEntries { GlanceEntries(report: report(sessions)) }

    @Test("each core state maps to its glance state, and ended has no entry")
    func stateMapping() {
        let result = entries([
            session("r", state: .running),
            session("w", state: .waiting),
            session("d", state: .idle, lastWrite: 2 * Self.minute),
            session("i", state: .idle, lastWrite: 40 * Self.minute),
            session("u", state: .unmeasurable),
            session("e", state: .ended),
        ])
        let states = Dictionary(uniqueKeysWithValues: result.all.map { ($0.sessionID, $0.state) })
        #expect(states == ["r": .working, "w": .waiting, "d": .done, "i": .idle, "u": .unmeasurable])
        #expect(result.all.count == 5)
    }

    @Test("an ended-only report is the empty result")
    func endedOnlyIsEmpty() {
        let result = entries([session("a", state: .ended), session("b", state: .ended)])
        #expect(result.isEmpty)
        #expect(result == .empty)
    }

    @Test("done holds through exactly 10 minutes, and one millisecond more is idle")
    func doneWindowEdge() {
        #expect(GlanceEntries.doneWindowMs == 600_000)
        let result = entries([
            session("edge", state: .idle, lastWrite: 600_000),
            session("past", state: .idle, lastWrite: 600_001),
            session("now", state: .idle, lastWrite: 0),
        ])
        let states = Dictionary(uniqueKeysWithValues: result.all.map { ($0.sessionID, $0.state) })
        #expect(states == ["edge": .done, "past": .idle, "now": .done])
    }

    @Test("an idle session with no known write is idle, not done")
    func nilLastWriteIsIdle() {
        let result = entries([session("x", state: .idle, lastWrite: nil)])
        #expect(result.all.map(\.state) == [.idle])
    }

    @Test("an entry carries the session's id, CLI, title, pid, reason and tool text")
    func entryFields() throws {
        let result = entries([
            session("u1", cli: .codex, state: .unmeasurable, pid: 48213, reason: "Rollout could not be read"),
            session("r1", state: .running, tool: CoreActivityTool(name: "Bash", target: "scripts/test.sh")),
            session("w1", state: .waiting, tool: CoreActivityTool(name: "AskUserQuestion", target: "")),
        ])
        let unmeasurable = try #require(result.all.first { $0.sessionID == "u1" })
        #expect(unmeasurable.cli == .codex)
        #expect(unmeasurable.id == "codex:u1")
        #expect(unmeasurable.title == "Task u1")
        #expect(unmeasurable.pid == 48213)
        #expect(unmeasurable.stateReason == "Rollout could not be read")
        #expect(unmeasurable.toolText == nil)
        #expect(result.all.first { $0.sessionID == "r1" }?.toolText == "Bash · scripts/test.sh")
        #expect(result.all.first { $0.sessionID == "w1" }?.toolText == "AskUserQuestion")
    }

    @Test("order is waiting, working, done, unmeasurable, idle; newest write first, nil last, then id")
    func order() {
        let result = entries([
            session("idle-old", state: .idle, lastWrite: 50 * Self.minute),
            session("run-nil", state: .running, lastWrite: nil),
            session("un", state: .unmeasurable, lastWrite: 1_000),
            session("run-new", state: .running, lastWrite: 500),
            session("done", state: .idle, lastWrite: 5 * Self.minute),
            session("run-b", cli: .codex, state: .running, lastWrite: 2_000),
            session("idle-nil", state: .idle, lastWrite: nil),
            session("wait", state: .waiting, lastWrite: 90 * Self.minute),
            session("run-a", state: .running, lastWrite: 2_000),
        ])
        #expect(result.all.map(\.sessionID) == ["wait", "run-new", "run-a", "run-b", "run-nil", "done", "un", "idle-old", "idle-nil"])
    }

    @Test("the order does not depend on the report's order")
    func orderIsStable() {
        let sessions = (0..<9).map { session("s\($0)", state: [.running, .waiting, .idle][$0 % 3], lastWrite: $0 % 2 == 0 ? 1_000 : nil) }
        #expect(entries(sessions) == entries(sessions.reversed()))
    }

    @Test("no session: the empty result, nothing shown, no overflow")
    func zeroSessions() {
        let result = entries([])
        #expect(result.isEmpty)
        #expect(result.shown.isEmpty)
        #expect(result.overflow == 0)
        #expect(result == .empty)
    }

    @Test("6 sessions all show, with no +N")
    func sixSessions() {
        let result = entries((1...6).map { session("s\($0)", lastWrite: Double($0)) })
        #expect(GlanceEntries.shownLimit == 6)
        #expect(result.shown.count == 6)
        #expect(result.all.count == 6)
        #expect(result.overflow == 0)
        #expect(!result.isEmpty)
    }

    @Test("7 sessions show 6 plus +1")
    func sevenSessions() {
        let result = entries((1...7).map { session("s\($0)", lastWrite: Double($0)) })
        #expect(result.shown.map(\.sessionID) == ["s1", "s2", "s3", "s4", "s5", "s6"])
        #expect(result.overflow == 1)
        #expect(result.all.count == 7)
    }

    @Test("12 sessions show 6 plus +6, waiting first, and the hover list keeps all 12 in the same order")
    func twelveSessions() {
        let states: [CoreSessionState] = [.running, .running, .idle, .idle, .waiting, .running, .idle, .unmeasurable, .running, .idle, .idle, .waiting]
        let sessions = states.enumerated().map { index, state in
            session(String(format: "s%02d", index + 1), cli: index % 3 == 0 ? .codex : .claude, state: state,
                    lastWrite: state == .idle ? Double(index) * 3 * Self.minute : Double(index) * 1_000)
        }
        let result = entries(sessions)
        #expect(result.all.count == 12)
        #expect(result.shown.count == 6)
        #expect(result.overflow == 6)
        #expect(result.shown.prefix(2).allSatisfy { $0.state == .waiting })
        #expect(result.shown == Array(result.all.prefix(6)))
        let ranks = result.all.map(\.state.rawValue)
        #expect(ranks == ranks.sorted())
    }

    // MARK: Order while the pointer is on the widget

    @Test("kept order: new write ages do not reorder the rows already shown, and each entry carries the new values")
    func keepingOrderHoldsRows() throws {
        let before = entries([session("a", lastWrite: 1_000), session("b", lastWrite: 2_000), session("c", lastWrite: 3_000)])
        #expect(before.all.map(\.sessionID) == ["a", "b", "c"])
        let fresh = entries([session("a", lastWrite: 9_000, tool: CoreActivityTool(name: "Bash", target: "")),
                             session("b", lastWrite: 500), session("c", lastWrite: 100)])
        #expect(fresh.all.map(\.sessionID) == ["c", "b", "a"])
        let kept = fresh.keepingOrder(of: before)
        #expect(kept.all.map(\.sessionID) == ["a", "b", "c"])
        #expect(try #require(kept.all.first).lastWriteAgoMs == 9_000)
        #expect(kept.all.first?.toolText == "Bash")
        #expect(Set(kept.all.map(\.id)) == Set(fresh.all.map(\.id)))
    }

    @Test("kept order: a new session goes to the end of its group, an ended one drops, groups keep the GW-R3 order")
    func keepingOrderAppendsAndDrops() {
        let before = entries([session("w1", state: .waiting, lastWrite: 1_000),
                              session("r1", lastWrite: 1_000), session("r2", lastWrite: 2_000), session("r3", lastWrite: 3_000),
                              session("i1", state: .idle, lastWrite: 40 * Self.minute)])
        let fresh = entries([session("w1", state: .waiting, lastWrite: 2_000),
                             session("r1", lastWrite: 9_000), session("r3", lastWrite: 100), session("r4", lastWrite: 1),
                             session("w2", state: .waiting, lastWrite: 1),
                             session("r2", state: .ended),
                             session("i1", state: .idle, lastWrite: 41 * Self.minute)])
        let kept = fresh.keepingOrder(of: before)
        #expect(kept.all.map(\.sessionID) == ["w1", "w2", "r1", "r3", "r4", "i1"])
        let ranks = kept.all.map(\.state.rawValue)
        #expect(ranks == ranks.sorted())
    }

    @Test("kept order: a session whose state changed joins the end of its new group")
    func keepingOrderStateChange() {
        let before = entries([session("w1", state: .waiting, lastWrite: 1_000),
                              session("r1", lastWrite: 1_000), session("r2", lastWrite: 2_000)])
        let fresh = entries([session("w1", state: .waiting, lastWrite: 1_000),
                             session("r1", state: .waiting, lastWrite: 1), session("r2", lastWrite: 2_000)])
        #expect(fresh.keepingOrder(of: before).all.map(\.sessionID) == ["w1", "r1", "r2"])
        let fresher = entries([session("w1", lastWrite: 1), session("r1", state: .waiting, lastWrite: 1), session("r2", lastWrite: 2_000)])
        #expect(fresher.keepingOrder(of: fresh).all.map(\.sessionID) == ["r1", "r2", "w1"])
    }

    @Test("kept order: from nothing it is the report's own order; a frozen strip still shows 6 plus +N")
    func keepingOrderEdges() {
        let fresh = entries((1...8).map { session("s\($0)", lastWrite: Double(9 - $0)) })
        #expect(fresh.keepingOrder(of: .empty) == fresh)
        #expect(GlanceEntries.empty.keepingOrder(of: fresh) == .empty)
        let reordered = entries((1...8).map { session("s\($0)", lastWrite: Double($0)) }).keepingOrder(of: fresh)
        #expect(reordered.all.map(\.sessionID) == fresh.all.map(\.sessionID))
        #expect(reordered.shown.count == 6 && reordered.overflow == 2)
    }
}
