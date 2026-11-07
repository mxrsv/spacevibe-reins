import Foundation
import Testing
@testable import Reins

/// The Loadout screen gives the same answers through the in-process engine and the Go core (plan S.1d, cut-over readiness).
/// Every test runs on a private copy of the synthetic fixture home (S-R1: never the real one); a write test uses a fresh copy per
/// engine, so the byte comparison is the whole home outside Reins' own folder.
@Suite("Loadout, both engines")
@MainActor
struct LoadoutModelEngineTests {
    /// The home a claude-only skill and a plugin skill live in, and a skill present in both CLIs.
    private static let removable = "claude:agent:local:architect.md"

    private func model(_ fixture: CoreFixtureHome, viaCore: Bool, screens: Set<CoreScreen> = [.loadout, .loadoutWrites]) throws -> (LoadoutModel, CoreClient?) {
        let client = viaCore ? try fixture.client() : nil
        let env = AppEnvironment(
            roots: try fixture.roots(), toasts: ToastCenter(announce: false),
            routing: CoreRouting(viaCore: viaCore ? screens : []), makeCoreClient: { client ?? CoreClient() }
        )
        return (LoadoutModel(env: env), client)
    }

    private func settled(_ model: LoadoutModel) async throws {
        model.start()
        let deadline = Date().addingTimeInterval(60)
        while !model.isSettled, model.readFailure == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(model.isSettled, "the read did not settle: \(model.readFailure ?? "timed out")")
    }

    private func wait(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done(), "\(what) did not happen")
    }

    // MARK: Reads

    @Test("loadout.rows is the same before a scan (all cells pending) and after it, through both engines")
    func sameRows() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let inProcess = InProcessCore(roots: try fixture.roots())
        let client = try fixture.client()
        defer { client.shutdown() }

        let beforeA = try await inProcess.loadoutRows()
        let beforeB = try await client.loadoutRows()
        #expect(beforeA.usage == .scanning && beforeB.usage == .scanning)
        #expect(beforeB == beforeA)

        let scanA = try await inProcess.usageScan(progress: nil)
        let scanB = try await client.usageScan(progress: nil)
        #expect(scanB == scanA)
        let afterA = try await inProcess.loadoutRows()
        let afterB = try await client.loadoutRows()
        #expect(afterA.usage == .ready && afterB.usage == .ready)
        #expect(afterA.items.contains { $0.cells.map { cells in cells.claude != .missing } ?? false })
        #expect(afterB == afterA)
    }

    @Test("the screen shows the same rows, scopes, counts, problems and usage note through both engines")
    func sameScreen() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let (inProcess, _) = try model(fixture, viaCore: false)
        let (viaCore, client) = try model(fixture, viaCore: true)
        defer { client?.shutdown() }
        try await settled(inProcess)
        try await settled(viaCore)
        let expected = try #require(inProcess.data)
        let actual = try #require(viaCore.data)
        #expect(!expected.rows.isEmpty && expected.scopes.count > 1)
        #expect(actual.rows == expected.rows)
        #expect(actual.scopes == expected.scopes)
        #expect(actual.countsByScope == expected.countsByScope)
        #expect(actual.problems == expected.problems)
        #expect(actual.events == expected.events)
        #expect(actual.globalCount == expected.globalCount)
        #expect(viaCore.usageNote == inProcess.usageNote)
        #expect(viaCore.deadHookCount(cli: .claude) == inProcess.deadHookCount(cli: .claude))
    }

    // MARK: Writes

    @Test("Remove then Undo from the screen puts the home back, byte for byte, in process, through the core, and with reads and writes split between them")
    func removeAndUndoFromTheScreen() async throws {
        // Both screens switched together, then each alone: reads in process with writes in Go, and the reverse.
        let routes: [(viaCore: Bool, screens: Set<CoreScreen>)] = [(false, []), (true, [.loadout, .loadoutWrites]), (true, [.loadoutWrites]), (true, [.loadout])]
        for (viaCore, screens) in routes {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            let (model, client) = try model(fixture, viaCore: viaCore, screens: screens)
            defer { client?.shutdown() }
            try await settled(model)
            let before = try fixture.tree()

            let row = try #require(model.data?.rows.first { $0.name == "architect" && $0.kind == .agent })
            let member = try #require(row.members[.claude])
            #expect(member.id == Self.removable)
            model.remove(row, member: member)
            try await wait("the toast") { model.env.toasts.current != nil }
            #expect(model.env.toasts.current?.message == "Removed agent architect from Claude Code", "routing: \(screens.map(\.rawValue).sorted())")
            #expect(try fixture.tree()[".claude/agents/architect.md"] == nil)
            try await wait("the re-read") { model.isSettled && model.data?.rows.contains { $0.name == "architect" } == false }

            model.env.toasts.runCurrentAction()
            try await wait("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
            #expect(model.env.toasts.current?.message == "Undid Removed agent architect from Claude Code", "routing: \(screens.map(\.rawValue).sorted())")
            let changed = try fixture.tree().difference(from: before)
            #expect(changed.isEmpty, "differs from the original (routing \(screens.map(\.rawValue).sorted())): \(changed)")
            try await wait("the row back") { model.isSettled && model.data?.rows.contains { $0.name == "architect" } == true }
        }
    }

    @Test("copy to the other CLI, remove and remove dead hooks each write one journal entry that Undo restores, through both engines")
    func writesAndUndo() async throws {
        var allLabels: [[String]] = []
        for viaCore in [false, true] {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            let client = viaCore ? try fixture.client() : nil
            defer { client?.shutdown() }
            let inProcess = InProcessCore(roots: try fixture.roots())
            let service: any CoreService = client.map { $0 as any CoreService } ?? inProcess
            let before = try fixture.tree()
            let rows = try await service.loadoutRows()
            let copy = try #require(rows.items.first { $0.cli == .claude && $0.kind == .skill && !$0.inOther && $0.scope == .global && $0.removable })
            let dead = rows.hooks.filter { $0.cli == .claude && $0.dead && $0.removable }
            #expect(!dead.isEmpty)

            var ids: [String] = []
            var labels: [String] = []
            let copied = try await service.loadoutCopyToOther(id: copy.id).entry
            ids.append(copied.id)
            labels.append(copied.label)
            let afterCopy = try fixture.tree()
            #expect(afterCopy != before)
            let removed = try await service.loadoutRemoveItem(id: copy.id).entry
            ids.append(removed.id)
            labels.append(removed.label)
            let deadEntry = try await service.loadoutRemoveDeadHooks(cli: .claude).entry
            #expect(deadEntry.label.hasPrefix("Removed \(dead.count) dead hook"), "viaCore \(viaCore): \(deadEntry.label)")
            ids.append(deadEntry.id)
            labels.append(deadEntry.label)
            allLabels.append(labels)
            let history = try await service.journalHistory().entries.map(\.id)
            #expect(Array(history.reversed()) == ids)
            for id in ids.reversed() { _ = try await service.journalUndo(id: id) }
            let changed = try fixture.tree().difference(from: before)
            #expect(changed.isEmpty, "differs from the original (viaCore \(viaCore)): \(changed)")
        }
        // The Undo toast shows the journal's label, so a different sentence here is a different toast.
        #expect(allLabels.count == 2 && allLabels[0].count == 3)
        #expect(allLabels[1] == allLabels[0])
    }

    // MARK: Refusals

    /// Status and sentence of each refusal, per engine.
    private func refusals(_ service: any CoreService, rows: CoreLoadoutRows) async -> [String] {
        func run(_ what: String, _ work: () async throws -> Void) async -> String {
            do { try await work(); return "\(what): accepted" } catch let error as CoreError { return "\(what): \(error.status) \(error.message)" } catch { return "\(what): \(error)" }
        }
        let both = rows.items.first { $0.cli == .claude && $0.kind == .skill && $0.inOther }
        let plugin = rows.items.first { !$0.removable }
        let project = rows.items.first { $0.scope == .project }
        var out: [String] = []
        if let both { out.append(await run("copy a skill the other CLI has") { _ = try await service.loadoutCopyToOther(id: both.id) }) }
        out.append(await run("copy an unknown id") { _ = try await service.loadoutCopyToOther(id: "claude:skill:global:nope") })
        out.append(await run("remove an unknown id") { _ = try await service.loadoutRemoveItem(id: "claude:skill:global:nope") })
        if let plugin { out.append(await run("remove a plugin item") { _ = try await service.loadoutRemoveItem(id: plugin.id) }) }
        if let project { out.append(await run("remove a project item") { _ = try await service.loadoutRemoveItem(id: project.id) }) }
        out.append(await run("remove dead hooks from Codex") { _ = try await service.loadoutRemoveDeadHooks(cli: .codex) })
        out.append(await run("undo an unknown entry") { _ = try await service.journalUndo(id: "no-such-entry") })
        return out
    }

    @Test("the refusals (copy over an existing name, unknown id, plugin and project items, no dead hooks, unknown Undo) have the same status and sentence through both engines")
    func sameRefusals() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let inProcess = InProcessCore(roots: try fixture.roots())
        let client = try fixture.client()
        defer { client.shutdown() }
        let rows = try await inProcess.loadoutRows()
        let swift = await refusals(inProcess, rows: rows)
        let go = await refusals(client, rows: rows)
        #expect(swift.count == 7 && swift.allSatisfy { !$0.hasSuffix("accepted") })
        #expect(go == swift)
    }
}
