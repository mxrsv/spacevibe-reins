import Foundation
import Testing
@testable import SpaceVibe

/// The Rules screen against the real Go core (plan S.7). Every test runs on a private copy of the synthetic fixture home
/// (S-R1: never the real one); a write test compares the whole home outside SpaceVibe's own folder, byte for byte, after the write
/// and its Undo.
@Suite("Rules, Go core")
@MainActor
struct RulesModelEngineTests {
    private func model(_ fixture: CoreFixtureHome) throws -> (RulesModel, CoreClient) {
        let client = try fixture.client()
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client })
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

    @Test("rules.snapshot reads every scope the fixture has and echoes the scope and folder asked")
    func snapshots() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }

        let global = try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        #expect(global.projectDirs.count == 3 && global.rules.count > 5 && !global.grid.isEmpty)
        for dir in global.projectDirs {
            for scope in [CoreRuleScope.project, .local] {
                let snapshot = try await client.rulesSnapshot(scope: scope, dir: dir, refreshProjects: false)
                #expect(snapshot.scope == scope && snapshot.dir == dir && snapshot.projectDirs == global.projectDirs, "\(scope.rawValue) \(dir)")
            }
        }
    }

    @Test("rules.preview answers every cell and verdict of the global scope and one project; a mixed cell refuses")
    func previews() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let global = try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        let academy = try #require(global.projectDirs.first { $0.hasSuffix("spacevibe-academy") })

        var compared = 0
        var refused = 0
        for (scope, dir) in [(CoreRuleScope.global, String?.none), (.project, academy), (.local, academy)] {
            for capability in CoreCapability.allCases {
                for verdict in CoreVerdict.allCases {
                    do {
                        let preview = try await client.rulesPreview(scope: scope, dir: dir, capability: capability, verdict: verdict)
                        #expect(preview.capability == capability && preview.verdict == verdict, "\(scope.rawValue) \(capability.rawValue) \(verdict.rawValue)")
                    } catch let error as CoreError {
                        #expect((400...499).contains(error.status), "\(error)")
                        refused += 1
                    }
                    compared += 1
                }
            }
        }
        #expect(compared == 54 && refused > 0 && refused < compared)
    }

    @Test("the screen shows the scopes, rules, grid and Codex page the core read")
    func screen() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        for name in [nil, "spacevibe-academy", "spacevibe-bench"] as [String?] {
            if let name { try await pick(model, name, .shared) }
            let snapshot = try #require(model.snapshot)
            #expect(!snapshot.rules.isEmpty && !snapshot.grid.isEmpty && snapshot.projects.count == 3)
            #expect(snapshot.title == (name.map { "\($0) (shared)" } ?? "Global"), "\(snapshot.title)")
            #expect(snapshot.globalRuleCount == model.badge)
            #expect(CodexWording.status(snapshot.codex).sentence.isEmpty == false && !CodexWording.rows(snapshot.codex).isEmpty)
        }
    }

    // MARK: Writes

    @Test("rules.setCapability then journal.undo puts the home back, byte for byte; a repeat write answers a null entry")
    func capabilityRoundTrip() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let before = try fixture.tree()

        let entry = try #require(try await client.rulesSetCapability(scope: .global, dir: nil, capability: .push, verdict: .deny).entry)
        #expect(try fixture.tree() != before, "the write changed nothing")
        #expect(try await client.rulesSetCapability(scope: .global, dir: nil, capability: .push, verdict: .deny).entry == nil)
        #expect(try await client.journalUndo(id: entry.id).label == entry.label)
        let changed = try fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("add, move and remove each write one journal entry that Undo restores, byte for byte")
    func ruleWritesAndUndo() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let before = try fixture.tree()

        let added = try await client.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash(echo round-trip)").entry
        let moved = try await client.rulesChangeVerdict(scope: .global, dir: nil, rule: "Bash(echo round-trip)", from: .ask, to: .deny).entry
        let removed = try await client.rulesRemove(scope: .global, dir: nil, verdict: .deny, rule: "Bash(echo round-trip)").entry
        #expect(added.label.hasPrefix("Added ask rule") && moved.count == 1 && removed.label.hasPrefix("Removed deny rule"))
        for entry in [removed, moved, added] { _ = try await client.journalUndo(id: entry.id) }
        let changed = try fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("a grid write and its Undo from the screen put the home back, byte for byte")
    func gridWriteFromTheScreen() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let before = try fixture.tree()

        model.requestSet(.push, to: .deny)
        try await wait("the confirmation") { model.pending != nil }
        #expect(model.pending?.question == "Set Push and deploy to Deny?")
        model.confirmPending()
        try await wait("the toast") { model.env.toasts.current?.message == "Set Push and deploy to Deny" }
        try await wait("the re-read") { model.isSettled && model.snapshot?.grid.first { $0.capability == .push }?.state == .deny }
        #expect(try fixture.tree() != before)

        model.env.toasts.runCurrentAction()
        try await wait("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
        try await wait("the grid back") { model.isSettled && model.snapshot?.grid.first { $0.capability == .push }?.state != .deny }
        let changed = try fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    @Test("a rule added from the screen shows; a duplicate and an invalid rule are refused next to the field; Undo takes the rule out again")
    func addFromTheScreen() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
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
        #expect(duplicate != nil && model.addError != nil)
        model.draft = ""

        model.env.toasts.runCurrentAction()
        try await wait("the Undo") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
        let changed = try fixture.tree().difference(from: before)
        #expect(changed.isEmpty, "differs from the original: \(changed)")
    }

    // MARK: Refusals

    /// Status and sentence of each refusal.
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
        return out
    }

    @Test("the refusals (duplicate, invalid, missing, same verdict, unknown project, stray folder) keep their status and name no absolute path")
    func refusalsAreStable() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let global = try await client.rulesSnapshot(scope: .global, dir: nil, refreshProjects: true)
        let academy = try #require(global.projectDirs.first { $0.hasSuffix("spacevibe-academy") })
        let seen = await refusals(client, academy: academy)
        #expect(seen == [
            "add a rule that is already there: 409 Bash(git push:*) is already in ask. Change its verdict instead.",
            "add an invalid rule: 400 That is not a valid rule. Use Tool or Tool(pattern) on one line.",
            "remove a rule that is not there: 409 This rule has already changed. Refresh the list.",
            "move a rule to its own verdict: 400 The rule already has that verdict.",
            "add to a project discovery did not find: 404 That project is not known to SpaceVibe.",
            "preview a project discovery did not find: 404 That project is not known to SpaceVibe.",
            "a global scope with a folder: 400 A global scope takes no folder.",
        ])
    }

    @Test("rules.check says why a rule is refused, in the sentences shown next to the add field", arguments: [
        ("", "Enter a rule such as Bash(npm test *)."), ("   ", "Enter a rule such as Bash(npm test *)."), ("\n", "Enter a rule such as Bash(npm test *)."),
        ("Bash(npm test\nnpm publish)", "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
        ("(npm test)", "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
        ("Bash(npm test", "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
    ])
    func ruleCheckRefuses(text: String, message: String) async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        #expect(try await client.rulesCheck(rule: text) == CoreRuleCheck(valid: false, message: message))
    }

    @Test("rules.check accepts a rule with or without surrounding whitespace, and one exactly at the 1000-unit limit but not one over")
    func ruleCheckAccepts() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        for text in ["Bash(npm test *)", "  Bash(npm test *)\n", "WebFetch"] {
            #expect(try await client.rulesCheck(rule: text) == CoreRuleCheck(valid: true, message: nil), "\(text)")
        }
        let atLimit = "Bash(" + String(repeating: "a", count: 1000 - "Bash()".utf16.count) + ")"
        #expect(atLimit.utf16.count == 1000)
        #expect(try await client.rulesCheck(rule: atLimit).valid)
        #expect(try await client.rulesCheck(rule: atLimit + "a").valid == false)
    }

    @Test("a project that discovery did not find falls back to the global snapshot, and a write to it is a 404")
    func unknownProject() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let client = try fixture.client()
        defer { client.shutdown() }
        let gone = fixture.home.appendingPathComponent("not-a-project").path
        let snapshot = try await client.rulesSnapshot(scope: .project, dir: gone, refreshProjects: true)
        #expect(snapshot.scope == .global && snapshot.dir == nil)
        do {
            _ = try await client.rulesAdd(scope: .project, dir: gone, verdict: .ask, rule: "Bash")
            Issue.record("the write was accepted")
        } catch let error as CoreError {
            #expect(error.status == 404)
        }
        do {
            _ = try await client.rulesAdd(scope: .project, dir: nil, verdict: .ask, rule: "Bash")
            Issue.record("the write was accepted")
        } catch let error as CoreError {
            #expect(error.status == 400)
        }
    }

    @Test("a settings file that is not valid JSON reads as a problem named by its label, never its path, and the grid is not editable")
    func invalidFile() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        try Data("{ not json".utf8).write(to: fixture.home.appendingPathComponent(".claude/settings.json"))
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        try await settled(model)
        let snapshot = try #require(model.snapshot)
        #expect(!snapshot.problems.isEmpty && snapshot.problems.allSatisfy { !$0.contains(fixture.home.path) && $0.contains("~/.claude/settings.json") })
        #expect(snapshot.grid.allSatisfy { !snapshot.isEditable($0) })

        for work in [
            { _ = try await client.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash") },
            { _ = try await client.rulesSetCapability(scope: .global, dir: nil, capability: .run, verdict: .deny) },
        ] as [() async throws -> Void] {
            do {
                try await work()
                Issue.record("the write was accepted")
            } catch let error as CoreError {
                #expect(error.status == 409 && error.message.contains("~/.claude/settings.json") && !error.message.contains(fixture.home.path), "\(error)")
            }
        }
    }
}
