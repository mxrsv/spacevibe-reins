import Foundation
import Testing
@testable import SpaceVibe

/// V5-A6 for the Skills tab: a logo toggle, a bulk add, a bulk remove and the pane's Remove go through the Go core, show ONE
/// toast, and Undo puts the whole home back byte for byte. Every test runs on a private copy of the synthetic fixture home
/// (S-R1) with the real core (`SPACEVIBE_CORE_BINARY`, as `scripts/test.sh` sets it).
@Suite("Skills model, Go core")
@MainActor
struct SkillsModelEngineTests {
    private func skills(_ fixture: CoreFixtureHome) async throws -> (SkillsModel, AppEnvironment, CoreClient) {
        let client = try fixture.client()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
        let model = SkillsModel(loadout: LoadoutModel(env: env))
        model.loadout.start()
        try await wait("the read") { model.loadout.isSettled || model.loadout.readFailure != nil }
        try #require(model.loadout.isSettled, "the read did not settle: \(model.loadout.readFailure ?? "timed out")")
        return (model, env, client)
    }

    private func wait(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done(), "\(what) did not happen")
    }

    /// Two skills only Claude Code has, which a person may change.
    private func claudeOnly(_ model: SkillsModel) -> [LoadoutRow] {
        model.rows.filter { $0.presentCLIs == [.claude] && $0.plugin == nil && $0.project == nil }
    }

    /// Runs the toast's Undo and waits for the "Undid" toast and the re-read.
    private func undo(_ model: SkillsModel, _ env: AppEnvironment, label: String) async throws {
        env.toasts.runCurrentAction()
        try await wait("the Undo toast") { env.toasts.current?.message == "Undid \(label)" }
        try await wait("the re-read") { model.loadout.isSettled }
    }

    @Test("pressing a dim logo adds the skill to that CLI with one toast; Undo restores the home byte for byte")
    func toggleAddAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let row = try #require(claudeOnly(model).first)
        #expect(model.mode(row, cli: .codex) == .toggles)

        model.toggle(row, cli: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Added \(row.name) to Codex"
        #expect(env.toasts.current?.message == label && env.toasts.current?.action != nil)
        #expect(try await fixture.tree().difference(from: before).count == 1, "one file is written: the copy")
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.key == row.key }?.presentCLIs == [.claude, .codex] }

        try await undo(model, env, label: label)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
        #expect(model.rows.first { $0.key == row.key }?.presentCLIs == [.claude])
    }

    @Test("adding the same skill again after Undo writes again: the double-click guard does not outlive the write")
    func addAgainAfterUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let picked = Array(claudeOnly(model).prefix(2))
        try #require(picked.count == 2)
        for round in 1 ... 2 {
            model.toggleBulk(picked, cli: .codex)
            try await wait("the toast of round \(round)") { env.toasts.current?.message == "Added 2 skills to Codex" }
            try await wait("the re-read of round \(round)") { model.loadout.isSettled && model.isLit(model.rows.filter { r in picked.contains { $0.key == r.key } }, cli: .codex) }
            try await undo(model, env, label: "Added 2 skills to Codex")
            env.toasts.dismiss()
        }
    }

    @Test("pressing a lit logo removes the skill from that CLI only; Undo restores it")
    func toggleRemoveAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let row = try #require(model.rows.first { $0.presentCLIs.count == 2 && $0.plugin == nil && $0.project == nil })
        #expect(model.mode(row, cli: .codex) == .toggles)

        model.toggle(row, cli: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Removed \(row.name) from Codex"
        #expect(env.toasts.current?.message == label)
        try await wait("the re-read") { model.loadout.isSettled && model.rows.first { $0.key == row.key }?.presentCLIs == [.claude] }

        try await undo(model, env, label: label)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("a bulk add is one toast and one Undo for every skill")
    func bulkAddAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let picked = Array(claudeOnly(model).prefix(2))
        try #require(picked.count == 2, "the fixture has two skills only Claude Code has")
        #expect(model.bulkMode(picked, cli: .codex) == .toggles && !model.isLit(picked, cli: .codex))

        model.toggleBulk(picked, cli: .codex)
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Added 2 skills to Codex"
        #expect(env.toasts.current?.message == label)
        #expect(try await fixture.tree().difference(from: before).count == 2)
        try await wait("the re-read") { model.loadout.isSettled && model.isLit(model.rows.filter { r in picked.contains { $0.key == r.key } }, cli: .codex) }

        try await undo(model, env, label: label)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "one Undo put both skills back; differs: \(changed)")
    }

    @Test("a bulk remove from every CLI is one toast and one Undo; a bulk toggle never removes an only copy")
    func bulkRemoveAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let both = try #require(model.rows.first { $0.presentCLIs.count == 2 && $0.plugin == nil && $0.project == nil })
        let one = try #require(claudeOnly(model).first)
        #expect(model.bulkMode([one], cli: .claude) == .onlyCopy)

        model.remove([both, one])
        try await wait("the toast") { env.toasts.current != nil }
        let label = "Removed 2 skills"
        #expect(env.toasts.current?.message == label)
        #expect(try await fixture.tree().difference(from: before).count == 3, "two copies of one skill and one copy of the other")
        try await wait("the re-read") { model.loadout.isSettled && model.rows.contains { $0.key == both.key } == false }

        try await undo(model, env, label: label)
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("a plugin's skill is read-only: no write, and a toast that says why")
    func pluginRefusal() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let plugin = try #require(model.rows.first { $0.plugin != nil })
        for cli in CoreCLI.allCases { #expect(model.mode(plugin, cli: cli) == .readOnly) }
        model.toggle(plugin, cli: .codex)
        #expect(env.toasts.current == nil, "a read-only logo does nothing")
        model.remove([plugin])
        #expect(env.toasts.current?.message == "Plugin-owned skills cannot be changed here.")
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }

    @Test("the only copy of a skill is not a toggle: its last lit logo does nothing")
    func onlyCopy() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let row = try #require(claudeOnly(model).first)
        #expect(model.mode(row, cli: .claude) == .onlyCopy)
        model.toggle(row, cli: .claude)
        try await Task.sleep(for: .milliseconds(300))
        #expect(env.toasts.current == nil)
        #expect(try await fixture.tree().difference(from: before).isEmpty)
    }

    // MARK: The current row after a removal (D2)

    /// The last listed skill a person may remove from every CLI, the row that becomes current when it goes, and the keys listed.
    private func lastRemovable(_ model: SkillsModel) throws -> (target: LoadoutRow, expected: String) {
        let keys = model.layout.rows.map(\.key)
        model.listedKeys = keys
        let target = try #require(model.layout.rows.last { $0.plugin == nil && $0.project == nil && $0.members.values.allSatisfy(\.removable) })
        let index = try #require(keys.firstIndex(of: target.key))
        let expected = index + 1 < keys.count ? keys[index + 1] : keys[index - 1]
        try #require(expected != keys.first, "the neighbour must differ from the first row for this test to mean anything")
        return (target, expected)
    }

    @Test("removing the current skill leaves its neighbour current, not the first row, and a second r during the write is dropped")
    func removeMovesCurrentRow() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let (target, expected) = try lastRemovable(model)
        model.select(target.key)

        model.remove([target])
        #expect(model.loadout.selectedKey == expected)
        let neighbour = try #require(model.rows.first { $0.key == expected })
        model.remove([neighbour])
        #expect(model.loadout.selectedKey == expected, "a repeated r during the write is dropped, so the key does not move on")
        try await wait("the toast") { env.toasts.current != nil }
        try await wait("the re-read") { model.loadout.isSettled && !model.rows.contains { $0.key == target.key } }
        #expect(model.rows.contains { $0.key == expected }, "the neighbour was not removed")
        #expect(model.current(in: model.layout.rows)?.key == expected)
    }

    @Test("a refused removal puts the key back on the row that stayed")
    func refusedRemovalPutsKeyBack() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, env, client) = try await skills(fixture)
        defer { client.shutdown() }
        let (target, expected) = try lastRemovable(model)
        model.select(target.key)
        for case .item(let item)? in target.members.values.map({ Optional($0) }) { try FileManager.default.removeItem(atPath: item.path) }

        model.remove([target])
        #expect(model.loadout.selectedKey == expected)
        try await wait("the refusal") { env.toasts.current?.tone == .danger }
        #expect(model.loadout.selectedKey == target.key)
    }
}

/// A core whose second copy fails, so a bulk write has to undo the first.
private final class FailingSecondCopyCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }

    override func loadoutRows() async throws -> CoreLoadoutRows {
        let rows = SkillRowsFixture.snapshot([("a", SkillRowsFixture.counted(1), nil, "user", nil), ("b", SkillRowsFixture.counted(1), nil, "user", nil)])
        return rows
    }

    override func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult {
        CoreUsageResult(
            totals: CoreUsageTotals(claude: CoreCLITotals(skill: [:], agent: [:], hook: [:]), codex: CoreCLITotals(skill: [:], agent: [:], hook: [:])),
            sessions: CoreUsageSessions(claude: 1, codex: 0),
            windows: CoreUsageWindows(claude: CoreLogWindow(files: 1, oldest: nil, newest: nil), codex: CoreLogWindow(files: 0, oldest: nil, newest: nil)), files: 1)
    }

    override func loadoutCopyToOther(id: String) async throws -> CoreEntryResult {
        let n = lock.withLock { () -> Int in _calls.append("copy \(id)"); return _calls.filter { $0.hasPrefix("copy") }.count }
        if n == 2 { throw CoreError("Codex already has a skill named b.", status: 409) }
        return CoreEntryResult(entry: CoreJournalEntry(id: "entry-\(n)", at: "2026-11-07T10:00:00.000Z", label: "Copied", undone: false, count: 1))
    }

    override func journalUndo(id: String) async throws -> CoreUndoResult {
        lock.withLock { _calls.append("undo \(id)") }
        return CoreUndoResult(label: "Copied")
    }
}

@Suite("Skills model, a bulk write that fails")
@MainActor
struct SkillsBulkFailureTests {
    @Test("a failed step undoes the steps already written and shows the core's sentence, with no Undo")
    func failureRollsBack() async throws {
        let core = FailingSecondCopyCore()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core })
        let model = SkillsModel(loadout: LoadoutModel(env: env))
        model.loadout.start()
        let deadline = Date().addingTimeInterval(30)
        while !model.loadout.isSettled, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(model.loadout.isSettled)

        model.add(model.rows, to: .codex)
        let until = Date().addingTimeInterval(30)
        while env.toasts.current == nil, Date() < until { try await Task.sleep(for: .milliseconds(20)) }
        #expect(env.toasts.current?.message == "Codex already has a skill named b.")
        #expect(env.toasts.current?.tone == .danger && env.toasts.current?.action == nil)
        #expect(core.calls.filter { $0.hasPrefix("copy") }.count == 2)
        #expect(core.calls.filter { $0.hasPrefix("undo") } == ["undo entry-1"], "the one that was written is undone")
    }
}

/// A core that accepts every copy and records what it was asked, for a write that spans both CLIs.
private final class RecordingCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }

    override func loadoutRows() async throws -> CoreLoadoutRows {
        SkillRowsFixture.snapshot([("a", SkillRowsFixture.counted(1), nil, "user", nil), ("b", nil, SkillRowsFixture.counted(1), "user", nil)])
    }

    override func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult {
        CoreUsageResult(
            totals: CoreUsageTotals(claude: CoreCLITotals(skill: [:], agent: [:], hook: [:]), codex: CoreCLITotals(skill: [:], agent: [:], hook: [:])),
            sessions: CoreUsageSessions(claude: 1, codex: 1),
            windows: CoreUsageWindows(claude: CoreLogWindow(files: 1, oldest: nil, newest: nil), codex: CoreLogWindow(files: 1, oldest: nil, newest: nil)), files: 2)
    }

    override func loadoutCopyToOther(id: String) async throws -> CoreEntryResult {
        let n = lock.withLock { () -> Int in _calls.append("copy \(id)"); return _calls.filter { $0.hasPrefix("copy") }.count }
        return CoreEntryResult(entry: CoreJournalEntry(id: "entry-\(n)", at: "2026-11-07T10:00:00.000Z", label: "Copied", undone: false, count: 1))
    }

    override func journalUndo(id: String) async throws -> CoreUndoResult {
        lock.withLock { _calls.append("undo \(id)") }
        return CoreUndoResult(label: "Copied")
    }
}

@Suite("Skills model, a write that spans both CLIs")
@MainActor
struct SkillsAddToOtherTests {
    @Test("`a` on picks that each lack the other CLI is one toast whose Undo undoes every file, newest first")
    func oneToastOneUndo() async throws {
        let core = RecordingCore()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core })
        let model = SkillsModel(loadout: LoadoutModel(env: env))
        model.loadout.start()
        func wait(_ done: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(30)
            while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        }
        try await wait { model.loadout.isSettled }
        try #require(model.loadout.isSettled)
        #expect(model.detected == [.claude, .codex])

        model.addToOtherCLI(model.rows)
        try await wait { env.toasts.current != nil }
        #expect(env.toasts.current?.message == "Added 2 skills to the other CLI")
        #expect(core.calls == ["copy codex:skill:global:b", "copy claude:skill:global:a"], "b goes to Claude Code, then a to Codex, in one write")
        #expect(env.toasts.current?.action != nil)

        env.toasts.runCurrentAction()
        try await wait { env.toasts.current?.message == "Undid Added 2 skills to the other CLI" }
        #expect(env.toasts.current?.message == "Undid Added 2 skills to the other CLI")
        #expect(core.calls.filter { $0.hasPrefix("undo") } == ["undo entry-2", "undo entry-1"])
    }
}
