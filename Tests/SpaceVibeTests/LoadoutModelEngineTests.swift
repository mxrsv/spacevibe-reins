import Foundation
import Testing
@testable import SpaceVibe

/// The Loadout screen runs on the Go core (plan S.5 and S.6). Every test runs on a private copy of the synthetic fixture home
/// (S-R1: never the real one), so a write test's byte comparison is the whole home outside SpaceVibe's own folder.
@Suite("Loadout, Go core")
@MainActor
struct LoadoutModelEngineTests {
    /// The home a claude-only skill and a plugin skill live in, and a skill present in both CLIs.
    private static let removable = "claude:agent:local:architect.md"

    private func model(_ fixture: CoreFixtureHome) throws -> (LoadoutModel, CoreClient) {
        let client = try fixture.client()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
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

    @Test("loadout.rows is scanning until a scan finishes, then ready with cells, counts and row flags")
    func rowsBeforeAndAfterScan() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }

        let before = try await client.loadoutRows()
        #expect(before.usage == .scanning)
        #expect(before.items.allSatisfy { $0.cells != nil })

        let scan = try await client.usageScan(progress: nil)
        #expect(scan.files > 100)
        let after = try await client.loadoutRows()
        #expect(after.usage == .ready)
        #expect(after.items.contains { $0.cells.map { cells in cells.claude != .missing } ?? false })
        #expect(after.countsByScope["global"]?.all ?? 0 > 0)
        #expect(after.rowFlags.count == Set(after.items.map(\.key) + after.hooks.map(\.key)).count)
        #expect(after.hooks.contains { $0.usage != nil })
    }

    @Test("a second scan while one runs is refused with 409")
    func overlappingScan() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let first = Task { try await client.usageScan(progress: nil) }
        let second = Task { try await client.usageScan(progress: nil) }
        let outcomes = [await first.result, await second.result]
        let failures = outcomes.compactMap { outcome -> CoreError? in
            if case .failure(let error) = outcome { return error as? CoreError }
            return nil
        }
        // Whichever started second is refused; if the first was already done, both succeed.
        #expect(failures.allSatisfy { $0.status == 409 })
        #expect(outcomes.contains { if case .success = $0 { true } else { false } })
    }

    @Test("the screen shows the fixture's rows, scopes, counts, problems and usage note")
    func screen() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let data = try #require(model.data)
        #expect(!data.rows.isEmpty && data.scopes.count > 1)
        #expect(data.countsByScope.count == data.scopes.count)
        #expect(data.globalCount > 0 && model.badge == data.globalCount)
        #expect(model.usageNote.hasPrefix("Counted from"))
        #expect(model.deadHookCount(cli: .claude) > 0)
    }

    // MARK: Writes

    @Test("Remove then Undo from the screen puts the home back, byte for byte")
    func removeAndUndoFromTheScreen() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let before = try await fixture.tree()

        let row = try #require(model.data?.rows.first { $0.name == "architect" && $0.kind == .agent })
        let member = try #require(row.members[.claude])
        #expect(member.id == Self.removable)
        model.remove(row, member: member)
        try await wait("the toast") { model.env.toasts.current != nil }
        #expect(model.env.toasts.current?.message == "Removed agent architect from Claude Code")
        #expect(try await fixture.tree()[".claude/agents/architect.md"] == nil)
        try await wait("the re-read") { model.isSettled && model.data?.rows.contains { $0.name == "architect" } == false }

        model.env.toasts.runCurrentAction()
        try await wait("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
        #expect(model.env.toasts.current?.message == "Undid Removed agent architect from Claude Code")
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
        try await wait("the row back") { model.isSettled && model.data?.rows.contains { $0.name == "architect" } == true }
    }

    @Test("copy to the other CLI, remove and remove dead hooks each write one journal entry that Undo restores")
    func writesAndUndo() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let before = try await fixture.tree()
        let rows = try await client.loadoutRows()
        let copy = try #require(rows.items.first { $0.cli == .claude && $0.kind == .skill && !$0.inOther && $0.scope == .global && $0.removable })
        let dead = rows.hooks.filter { $0.cli == .claude && $0.dead && $0.removable }
        #expect(!dead.isEmpty)

        var ids: [String] = []
        let copied = try await client.loadoutCopyToOther(id: copy.id).entry
        ids.append(copied.id)
        #expect(try await fixture.tree() != before)
        ids.append(try await client.loadoutRemoveItem(id: copy.id).entry.id)
        let deadEntry = try await client.loadoutRemoveDeadHooks(cli: .claude).entry
        #expect(deadEntry.label.hasPrefix("Removed \(dead.count) dead hook"), "\(deadEntry.label)")
        ids.append(deadEntry.id)
        let history = try await client.journalHistory().entries.map(\.id)
        #expect(Array(history.reversed()) == ids)
        for id in ids.reversed() { _ = try await client.journalUndo(id: id) }
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    // MARK: Linked skills (M2) and a refused Undo (JA7)

    private static let linkedName = "linked-demo"

    /// A Claude Code skill `linked-demo` of its own, plus `.codex/skills/linked-demo` as a link to it (owner `link`), or with
    /// `sharedFolder` the whole `.codex/skills` folder as a link to `.claude/skills`.
    private func linkSkill(in fixture: CoreFixtureHome, sharedFolder: Bool = false) throws {
        let fm = FileManager.default
        let claudeSkills = fixture.home.appendingPathComponent(".claude/skills", isDirectory: true)
        let folder = claudeSkills.appendingPathComponent(Self.linkedName, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("---\nname: \(Self.linkedName)\ndescription: Shared by a link.\n---\n".utf8).write(to: folder.appendingPathComponent("SKILL.md"))
        let codexSkills = fixture.home.appendingPathComponent(".codex/skills", isDirectory: true)
        if sharedFolder {
            try fm.removeItem(at: codexSkills)
            try fm.createSymbolicLink(at: codexSkills, withDestinationURL: claudeSkills)
        } else {
            try fm.createSymbolicLink(at: codexSkills.appendingPathComponent(Self.linkedName), withDestinationURL: folder)
        }
    }

    private func linkedRow(_ model: LoadoutModel) throws -> LoadoutRow {
        try #require(model.data?.rows.first { $0.name == Self.linkedName && $0.kind == .skill })
    }

    @Test("a Claude Code skill and a Codex link to it: Remove from every CLI takes the link first and succeeds; Undo restores both")
    func removeLinkedSkillFromEveryCLI() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        try linkSkill(in: fixture)
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let before = try await fixture.tree()
        let row = try linkedRow(model)
        #expect(row.members[.codex]?.owner == "link" && row.members[.claude]?.owner == "user")
        #expect(LoadoutRows.logoMode(row, cli: .claude, events: [:]) == .onlyCopy, "the real copy is the only copy while a link points at it")

        let plan = LoadoutRows.removeWrites([row], from: nil)
        #expect(plan.steps.first == .remove(id: try #require(row.members[.codex]).id, from: .codex), "the link goes first")
        #expect(model.perform(skillWrites: plan.steps, guardKey: "linked", label: "Removed \(Self.linkedName)"))
        try await wait("the toast") { model.env.toasts.current != nil }
        #expect(model.env.toasts.current?.message == "Removed \(Self.linkedName)" && model.env.toasts.current?.tone != .danger)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: fixture.home.appendingPathComponent(".claude/skills/\(Self.linkedName)").path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: fixture.home.appendingPathComponent(".codex/skills/\(Self.linkedName)").path)) == nil)
        try await wait("the re-read") { model.isSettled && model.data?.rows.contains { $0.name == Self.linkedName } == false }

        model.env.toasts.runCurrentAction()
        try await wait("the Undo toast") { model.env.toasts.current?.message == "Undid Removed \(Self.linkedName)" }
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
        let target = try fm.destinationOfSymbolicLink(atPath: fixture.home.appendingPathComponent(".codex/skills/\(Self.linkedName)").path)
        #expect(target == fixture.home.appendingPathComponent(".claude/skills/\(Self.linkedName)").path)
    }

    @Test("removing the real copy alone is refused while a link points at it, and the link alone may go")
    func realCopyIsTheOnlyCopyWhileLinked() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        try linkSkill(in: fixture)
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let row = try linkedRow(model)
        #expect(LoadoutRows.removeWrites([row], from: .claude).steps.isEmpty)
        #expect(LoadoutRows.removeWrites([row], from: .codex).steps.count == 1)
    }

    @Test("`.codex/skills` linked to `.claude/skills`: Remove from every CLI succeeds, the second step finding its skill already gone")
    func removeFromSharedSkillsFolder() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        try linkSkill(in: fixture, sharedFolder: true)
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let before = try await fixture.tree()
        let row = try linkedRow(model)
        #expect(row.presentCLIs == [.claude, .codex])

        let plan = LoadoutRows.removeWrites([row], from: nil)
        #expect(plan.steps.count == 2)
        #expect(model.perform(skillWrites: plan.steps, guardKey: "shared", label: "Removed \(Self.linkedName)"))
        try await wait("the toast") { model.env.toasts.current != nil }
        #expect(model.env.toasts.current?.message == "Removed \(Self.linkedName)" && model.env.toasts.current?.tone != .danger)
        #expect(!FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent(".claude/skills/\(Self.linkedName)").path))
        try await wait("the re-read") { model.isSettled && model.data?.rows.contains { $0.name == Self.linkedName } == false }

        model.env.toasts.runCurrentAction()
        try await wait("the Undo toast") { model.env.toasts.current?.message == "Undid Removed \(Self.linkedName)" }
        let changed = try await fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("a refused Undo shows the core's own sentence, for one entry and for several")
    func refusedUndoSaysWhy() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let rows = try #require(model.data?.rows.filter { $0.kind == .skill && $0.presentCLIs == [.claude] && $0.plugin == nil && $0.project == nil })
        let folder = fixture.home.appendingPathComponent(".claude/skills", isDirectory: true)

        // One entry: the folder is recreated before Undo.
        let one = try #require(rows.first)
        #expect(model.perform(skillWrites: LoadoutRows.removeWrites([one], from: nil).steps, guardKey: "one", label: "Removed \(one.name)"))
        try await wait("the toast") { model.env.toasts.current?.message == "Removed \(one.name)" }
        let path = folder.appendingPathComponent(one.name, isDirectory: true).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        model.env.toasts.runCurrentAction()
        try await wait("the refusal") { model.env.toasts.current?.tone == .danger }
        #expect(model.env.toasts.current?.message == "\(path) already exists again, so it was left alone.")

        // Several entries: the label comes first, then the sentence.
        let pair = Array(rows.dropFirst().prefix(2))
        try #require(pair.count == 2)
        let steps = LoadoutRows.removeWrites(pair, from: nil).steps
        try await wait("the guard") { model.guardedWrites == 0 }
        #expect(model.perform(skillWrites: steps, guardKey: "two", label: "Removed 2 skills"))
        try await wait("the toast") { model.env.toasts.current?.message == "Removed 2 skills" }
        let again = folder.appendingPathComponent(pair[1].name, isDirectory: true).path
        try FileManager.default.createDirectory(atPath: again, withIntermediateDirectories: true)
        model.env.toasts.runCurrentAction()
        try await wait("the refusal") { model.env.toasts.current?.tone == .danger }
        #expect(model.env.toasts.current?.message == "Could not undo all of Removed 2 skills. \(again) already exists again, so it was left alone.")
    }

    // MARK: Refusals

    /// Status and sentence of each refusal.
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

    @Test("the refusals (copy over an existing name, unknown id, plugin and project items, no dead hooks, unknown Undo) have the core's status and sentence")
    func refusals() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let rows = try await client.loadoutRows()
        let seen = await refusals(client, rows: rows)
        #expect(seen == [
            "copy a skill the other CLI has: 409 Codex already has a skill named explain.",
            "copy an unknown id: 404 This item no longer exists. Refresh the list.",
            "remove an unknown id: 404 This item no longer exists. Refresh the list.",
            "remove a plugin item: 403 This one belongs to a plugin. Remove the plugin instead.",
            "remove a project item: 403 This one belongs to a project folder, so SpaceVibe only shows it. Change it in the project.",
            "remove dead hooks from Codex: 409 No dead hooks to remove.",
            "undo an unknown entry: 404 That history entry is gone.",
        ])
    }
}
