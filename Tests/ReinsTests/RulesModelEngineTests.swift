import Foundation
import Testing
@testable import Reins

/// The Rules screen gives the same answers through the in-process engine and the Go core (plan S.1e, cut-over readiness). Every
/// test runs on a private copy of the synthetic fixture home (S-R1: never the real one); a write test uses a fresh copy per
/// engine, so the byte comparison is the whole home outside Reins' own folder.
@Suite("Rules, both engines")
@MainActor
struct RulesModelEngineTests {
    private func model(_ fixture: CoreFixtureHome, viaCore: Bool) throws -> (RulesModel, CoreClient?) {
        let client = viaCore ? try fixture.client() : nil
        let env = AppEnvironment(
            roots: try fixture.roots(), proc: FixtureProcessAdapter.empty, toasts: ToastCenter(announce: false),
            routing: CoreRouting(viaCore: viaCore ? [.rules] : []), makeCoreClient: { client ?? CoreClient() }
        )
        return (RulesModel(env: env), client)
    }

    private func settled(_ model: RulesModel) async throws {
        model.start()
        try await wait("the read") { model.isSettled || model.failure != nil }
        try #require(model.isSettled, "the read did not settle: \(model.failure ?? "timed out")")
    }

    private func wait(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done(), "\(what) did not happen")
    }

    private func pick(_ model: RulesModel, _ name: String, _ file: RulesFileKind) async throws {
        let project = try #require(model.snapshot?.projects.first { $0.name == name })
        model.select(RulesSelection(dir: project.dir, file: file))
        try await wait("the \(name) read") { model.isSettled && model.snapshot?.selection.dir == project.dir && model.snapshot?.selection.file == file }
    }

    // MARK: Reads

    @Test("rules.snapshot is the same for every scope the fixture has, through both engines")
    func sameSnapshots() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let inProcess = InProcessCore(roots: try fixture.roots(), proc: FixtureProcessAdapter.empty)
        let client = try fixture.client()
        defer { client.shutdown() }

        let global = try await inProcess.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        #expect(global.projectDirs.count == 3 && global.rules.count > 5 && !global.grid.isEmpty)
        #expect(try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true) == global)
        for dir in global.projectDirs {
            for scope in [CoreRuleScope.project, .local] {
                let expected = try await inProcess.rulesSnapshot(scope: scope, dir: dir, refreshProjects: false)
                #expect(expected.scope == scope && expected.dir == dir)
                #expect(try await client.rulesSnapshot(scope: scope, dir: dir, refreshProjects: false) == expected, "\(scope.rawValue) \(dir)")
            }
        }
    }

    @Test("rules.preview is the same for every cell and verdict of the global scope and one project, through both engines")
    func samePreviews() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let inProcess = InProcessCore(roots: try fixture.roots(), proc: FixtureProcessAdapter.empty)
        let client = try fixture.client()
        defer { client.shutdown() }
        let global = try await inProcess.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        let academy = try #require(global.projectDirs.first { $0.hasSuffix("spacevibe-academy") })
        _ = try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)

        // A mixed cell refuses a preview, so the refusal is part of what has to match.
        func outcome(_ service: any CoreService, _ scope: CoreRuleScope, _ dir: String?, _ capability: CoreCapability, _ verdict: CoreVerdict) async -> String {
            do { return String(describing: try await service.rulesPreview(scope: scope, dir: dir, capability: capability, verdict: verdict)) } catch let error as CoreError { return "\(error.status) \(error.message)" } catch { return "\(error)" }
        }
        var compared = 0
        var refused = 0
        for (scope, dir) in [(CoreRuleScope.global, String?.none), (.project, academy), (.local, academy)] {
            for capability in CoreCapability.allCases {
                for verdict in CoreVerdict.allCases {
                    let expected = await outcome(inProcess, scope, dir, capability, verdict)
                    #expect(await outcome(client, scope, dir, capability, verdict) == expected, "\(scope.rawValue) \(capability.rawValue) \(verdict.rawValue)")
                    compared += 1
                    if expected.hasPrefix("4") { refused += 1 }
                }
            }
        }
        #expect(compared == 54 && refused > 0 && refused < compared)
    }

    @Test("the screen shows the same scopes, rules, grid, problems and Codex page through both engines")
    func sameScreen() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let (inProcess, _) = try model(fixture, viaCore: false)
        let (viaCore, client) = try model(fixture, viaCore: true)
        defer { client?.shutdown() }
        try await settled(inProcess)
        try await settled(viaCore)
        for name in [nil, "spacevibe-academy", "spacevibe-bench"] as [String?] {
            if let name {
                try await pick(inProcess, name, .shared)
                try await pick(viaCore, name, .shared)
            }
            let expected = try #require(inProcess.snapshot)
            let actual = try #require(viaCore.snapshot)
            #expect(!expected.rules.isEmpty)
            #expect(actual.selection == expected.selection && actual.title == expected.title)
            #expect(actual.projects == expected.projects && actual.globalRuleCount == expected.globalRuleCount)
            #expect(actual.rules == expected.rules && actual.grid == expected.grid && actual.problems == expected.problems)
            #expect(actual.codex == expected.codex && actual.exists == expected.exists && actual.fileLabel == expected.fileLabel)
            #expect(CodexWording.status(actual.codex) == CodexWording.status(expected.codex))
            #expect(CodexWording.rows(actual.codex) == CodexWording.rows(expected.codex))
        }
        #expect(viaCore.badge == inProcess.badge)
    }

    // MARK: Writes

    @Test("rules.setCapability then journal.undo puts the home back, byte for byte, through both engines")
    func capabilityRoundTrip() async throws {
        var labels: [String] = []
        for viaCore in [false, true] {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            let client = viaCore ? try fixture.client() : nil
            defer { client?.shutdown() }
            let inProcess = InProcessCore(roots: try fixture.roots(), proc: FixtureProcessAdapter.empty)
            let service: any CoreService = client.map { $0 as any CoreService } ?? inProcess
            let before = try fixture.tree()

            let entry = try #require(try await service.rulesSetCapability(scope: .global, dir: nil, capability: .push, verdict: .deny).entry)
            labels.append(entry.label)
            #expect(try fixture.tree() != before, "viaCore \(viaCore): the write changed nothing")
            #expect(try await service.rulesSetCapability(scope: .global, dir: nil, capability: .push, verdict: .deny).entry == nil)
            let undone = try await service.journalUndo(id: entry.id)
            labels.append(undone.label)
            let changed = try fixture.tree().difference(from: before)
            #expect(changed.isEmpty, "differs from the original (viaCore \(viaCore)): \(changed)")
        }
        // The Undo toast shows the journal's label, so a different sentence here is a different toast.
        #expect(labels.count == 4 && labels[2] == labels[0] && labels[3] == labels[1])
    }

    @Test("add, move and remove each write one journal entry that Undo restores, through both engines")
    func ruleWritesAndUndo() async throws {
        var labels: [[String]] = []
        for viaCore in [false, true] {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            let client = viaCore ? try fixture.client() : nil
            defer { client?.shutdown() }
            let inProcess = InProcessCore(roots: try fixture.roots(), proc: FixtureProcessAdapter.empty)
            let service: any CoreService = client.map { $0 as any CoreService } ?? inProcess
            let before = try fixture.tree()

            let added = try await service.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash(echo round-trip)").entry
            let moved = try await service.rulesChangeVerdict(scope: .global, dir: nil, rule: "Bash(echo round-trip)", from: .ask, to: .deny).entry
            let removed = try await service.rulesRemove(scope: .global, dir: nil, verdict: .deny, rule: "Bash(echo round-trip)").entry
            labels.append([added.label, moved.label, removed.label])
            for entry in [removed, moved, added] { _ = try await service.journalUndo(id: entry.id) }
            let changed = try fixture.tree().difference(from: before)
            #expect(changed.isEmpty, "differs from the original (viaCore \(viaCore)): \(changed)")
        }
        #expect(labels.count == 2 && labels[1] == labels[0])
    }

    @Test("a grid write and its Undo from the screen put the home back, byte for byte, in process and through the core")
    func gridWriteFromTheScreen() async throws {
        for viaCore in [false, true] {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            let (model, client) = try model(fixture, viaCore: viaCore)
            defer { client?.shutdown() }
            try await settled(model)
            let before = try fixture.tree()

            model.requestSet(.push, to: .deny)
            try await wait("the confirmation") { model.pending != nil }
            #expect(model.pending?.question == "Set Push and deploy to Deny?", "viaCore \(viaCore)")
            model.confirmPending()
            try await wait("the toast") { model.env.toasts.current?.message == "Set Push and deploy to Deny" }
            try await wait("the re-read") { model.isSettled && model.snapshot?.grid.first { $0.capability == .push }?.state == .deny }
            #expect(try fixture.tree() != before)

            model.env.toasts.runCurrentAction()
            try await wait("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
            try await wait("the grid back") { model.isSettled && model.snapshot?.grid.first { $0.capability == .push }?.state != .deny }
            let changed = try fixture.tree().difference(from: before)
            #expect(changed.isEmpty, "differs from the original (viaCore \(viaCore)): \(changed)")
        }
    }

    @Test("a rule added from the screen, and a duplicate, read the same through both engines; Undo takes the rule out again")
    func addFromTheScreen() async throws {
        var seen: [[String?]] = []
        for viaCore in [false, true] {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            let (model, client) = try model(fixture, viaCore: viaCore)
            defer { client?.shutdown() }
            try await settled(model)
            try await pick(model, "spacevibe-bench", .shared)
            let before = try fixture.tree()

            model.draft = "Bash(npm test *)"
            model.draftVerdict = .ask
            model.submitDraft()
            try await wait("the add") { model.env.toasts.current?.message == "Added Bash(npm test *) to Ask first" && model.isSettled }
            #expect(model.snapshot?.rules.contains { $0.rule == "Bash(npm test *)" } == true)

            model.draft = "Bash(npm test *)"
            model.submitDraft()
            try await wait("the duplicate message") { model.addError != nil && !model.isWriting }
            let duplicate = model.addError
            model.draft = "(nope)"
            model.submitDraft()
            try await wait("the shape message") { model.addError != duplicate }
            seen.append([duplicate, model.addError])
            model.draft = ""

            model.env.toasts.runCurrentAction()
            try await wait("the Undo") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
            let changed = try fixture.tree().difference(from: before)
            #expect(changed.isEmpty, "differs from the original (viaCore \(viaCore)): \(changed)")
        }
        #expect(seen.count == 2 && seen[0].allSatisfy { $0 != nil } && seen[1] == seen[0])
    }

    // MARK: Refusals

    /// Status and sentence of each refusal, per engine.
    private func refusals(_ service: any CoreService, academy: String) async -> [String] {
        func run(_ what: String, _ work: () async throws -> Void) async -> String {
            do { try await work(); return "\(what): accepted" } catch let error as CoreError { return "\(what): \(error.status) \(error.message)" } catch { return "\(what): \(error)" }
        }
        let gone = academy + "-gone"
        var out: [String] = []
        out.append(await run("add a rule that is already there") { _ = try await service.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash(git push:*)") })
        out.append(await run("add an invalid rule") { _ = try await service.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "(nope)") })
        out.append(await run("remove a rule that is not there") { _ = try await service.rulesRemove(scope: .global, dir: nil, verdict: .ask, rule: "Bash(not:*)") })
        out.append(await run("move a rule to its own verdict") { _ = try await service.rulesChangeVerdict(scope: .global, dir: nil, rule: "Bash(git push:*)", from: .ask, to: .ask) })
        out.append(await run("add to a project discovery did not find") { _ = try await service.rulesAdd(scope: .project, dir: gone, verdict: .ask, rule: "Bash") })
        out.append(await run("preview a project discovery did not find") { _ = try await service.rulesPreview(scope: .project, dir: gone, capability: .run, verdict: .ask) })
        out.append(await run("a global scope with a folder") { _ = try await service.rulesAdd(scope: .global, dir: academy, verdict: .ask, rule: "Bash") })
        out.append(await run("undo an unknown entry") { _ = try await service.journalUndo(id: "no-such-entry") })
        return out
    }

    @Test("the refusals (duplicate, invalid, missing, same verdict, unknown project, stray folder, unknown Undo) have the same status and sentence through both engines")
    func sameRefusals() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let inProcess = InProcessCore(roots: try fixture.roots(), proc: FixtureProcessAdapter.empty)
        let client = try fixture.client()
        defer { client.shutdown() }
        let global = try await inProcess.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        _ = try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        let academy = try #require(global.projectDirs.first { $0.hasSuffix("spacevibe-academy") })
        let swift = await refusals(inProcess, academy: academy)
        let go = await refusals(client, academy: academy)
        #expect(swift.count == 8 && swift.allSatisfy { !$0.hasSuffix("accepted") }, "\(swift)")
        #expect(go == swift)
        #expect(swift.allSatisfy { !$0.contains(fixture.home.path) }, "a refusal names an absolute path: \(swift)")
    }

    @Test("a settings file that is not valid JSON reads the same, and refuses a write with the same label-only sentence, through both engines")
    func sameInvalidFile() async throws {
        var seen: [[String]] = []
        for viaCore in [false, true] {
            let fixture = try CoreFixtureHome()
            defer { fixture.remove() }
            try Data("{ not json".utf8).write(to: fixture.home.appendingPathComponent(".claude/settings.json"))
            let (model, client) = try model(fixture, viaCore: viaCore)
            defer { client?.shutdown() }
            try await settled(model)
            let problems = try #require(model.snapshot?.problems)
            #expect(!problems.isEmpty && problems.allSatisfy { !$0.contains(fixture.home.path) && $0.contains("~/.claude/settings.json") })
            #expect(model.snapshot?.grid.allSatisfy { !model.snapshot!.isEditable($0) } == true)
            seen.append(problems)
        }
        #expect(seen.count == 2 && seen[1] == seen[0])
    }
}
