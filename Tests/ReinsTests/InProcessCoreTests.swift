import Foundation
import Testing
import ReinsCore
@testable import Reins

/// The adapter over ReinsCore, run on a private copy of the synthetic fixture home (S-R1: never the real one).
@Suite("InProcessCore")
struct InProcessCoreTests {
    /// A copy of `core/testdata/fixtures/home` under a temporary folder, with `$HOME` replaced by that folder.
    private struct Fixture {
        let home: URL
        let roots: Roots
        let core: InProcessCore

        init() throws {
            let source = CoreTestData.directory.appendingPathComponent("fixtures", isDirectory: true)
            let manifest = try #require(try CoreTestData.json("fixtures/manifest.json") as? [String: Any])
            let token = try #require(manifest["token"] as? String)
            let mtimes = try #require(manifest["mtimes"] as? [String: Double])
            home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("reins-core-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
            let fm = FileManager.default
            for (relative, mtime) in mtimes {
                let text = try String(contentsOf: source.appendingPathComponent("home/\(relative)"), encoding: .utf8)
                let target = home.appendingPathComponent(relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.replacingOccurrences(of: token, with: home.path).utf8).write(to: target)
                try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: mtime / 1000)], ofItemAtPath: target.path)
            }
            let env = [
                "HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
                "CODEX_HOME": home.appendingPathComponent(".codex").path, "SPACEVIBE_HOME": home.appendingPathComponent(".spacevibe").path,
                "SPACEVIBE_TEST": "1",
            ]
            roots = try Roots.resolve(env: env)
            core = InProcessCore(roots: roots)
        }

        func remove() { try? FileManager.default.removeItem(at: home) }
    }

    @Test("a rule is added with an Undo entry, a duplicate is refused with 409, and Undo puts the file back")
    func rulesWriteAndUndo() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let core = fixture.core
        #expect(try await core.rulesCheck(rule: "Bash(echo core-test)") == CoreRuleCheck(valid: true, message: nil))
        #expect(try await core.rulesCheck(rule: "(nope)").valid == false)

        let added = try await core.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash(echo core-test)")
        #expect(added.entry.label.hasPrefix("Added ask rule Bash(echo core-test)"))
        var snapshot = try await core.rulesSnapshot(scope: .global, dir: nil, refreshProjects: false)
        #expect(snapshot.rules.contains { $0.rule == "Bash(echo core-test)" && $0.verdict == .ask })
        #expect(snapshot.fileLabel == "~/.claude/settings.json")

        do {
            _ = try await core.rulesAdd(scope: .global, dir: nil, verdict: .allow, rule: "Bash(echo core-test)")
            Issue.record("the duplicate was accepted")
        } catch let error as CoreError {
            #expect(error.status == 409)
            #expect(!error.message.contains(fixture.home.path))
        }

        let moved = try await core.rulesChangeVerdict(scope: .global, dir: nil, rule: "Bash(echo core-test)", from: .ask, to: .deny)
        #expect(moved.entry.count == 1)
        let removed = try await core.rulesRemove(scope: .global, dir: nil, verdict: .deny, rule: "Bash(echo core-test)")
        #expect(removed.entry.label.hasPrefix("Removed deny rule"))

        // Undo is the Go core's (S.6); the journal file is the engine's, so the engine reads it here.
        let history = Journal.history(fixture.roots)
        #expect(history.map(\.id) == [removed.entry.id, moved.entry.id, added.entry.id])
        let undone = try Journal.undo(fixture.roots, id: removed.entry.id)
        #expect(undone == removed.entry.label)
        snapshot = try await core.rulesSnapshot(scope: .global, dir: nil, refreshProjects: false)
        #expect(snapshot.rules.contains { $0.rule == "Bash(echo core-test)" && $0.verdict == .deny })
        #expect(Journal.history(fixture.roots).first?.undone == true)
    }

    @Test("a capability preview and write go through, and a repeat write answers a null entry instead of failing")
    func capability() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let core = fixture.core
        let preview = try await core.rulesPreview(scope: .global, dir: nil, capability: .read, verdict: .deny)
        #expect(preview.scopeLabel == "~/.claude/settings.json")
        #expect(preview.resulting == .deny)
        let first = try await core.rulesSetCapability(scope: .global, dir: nil, capability: .read, verdict: .deny)
        #expect(first.entry != nil)
        let again = try await core.rulesSetCapability(scope: .global, dir: nil, capability: .read, verdict: .deny)
        #expect(again.entry == nil)
    }

    @Test("rules.check refuses an empty or blank rule, a line break, an over-long rule and text that is not Tool or Tool(pattern)", arguments: [
        ("", "Enter a rule such as Bash(npm test *)."), ("   ", "Enter a rule such as Bash(npm test *)."), ("\n", "Enter a rule such as Bash(npm test *)."),
        ("Bash(npm test\nnpm publish)", "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
        ("(npm test)", "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
        ("Bash(npm test", "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
    ])
    func ruleCheckRefuses(text: String, message: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(try await fixture.core.rulesCheck(rule: text) == CoreRuleCheck(valid: false, message: message))
    }

    @Test("rules.check accepts a rule with or without surrounding whitespace, and one exactly at the length limit but not one over")
    func ruleCheckAccepts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let core = fixture.core
        for text in ["Bash(npm test *)", "  Bash(npm test *)\n", "WebFetch"] {
            #expect(try await core.rulesCheck(rule: text) == CoreRuleCheck(valid: true, message: nil), "\(text)")
        }
        let atLimit = "Bash(" + String(repeating: "a", count: Rules.maxRuleLength - "Bash()".utf16.count) + ")"
        #expect(atLimit.utf16.count == Rules.maxRuleLength)
        #expect(try await core.rulesCheck(rule: atLimit).valid)
        #expect(try await core.rulesCheck(rule: atLimit + "a").valid == false)
    }

    @Test("a write the engine refuses names the scope's file by its label, never by its path, and keeps the status")
    func writeRefusalIsScrubbed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("{ not json".utf8).write(to: fixture.home.appendingPathComponent(".claude/settings.json"))
        for work in [
            { _ = try await fixture.core.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash") },
            { _ = try await fixture.core.rulesSetCapability(scope: .global, dir: nil, capability: .run, verdict: .deny) },
        ] as [() async throws -> Void] {
            do {
                try await work()
                Issue.record("the write was accepted")
            } catch let error as CoreError {
                #expect(error.status == 409)
                #expect(error.message.contains("~/.claude/settings.json"), "\(error.message)")
                #expect(!error.message.contains(fixture.home.path), "\(error.message)")
            }
        }
        let snapshot = try await fixture.core.rulesSnapshot(scope: .global, dir: nil, refreshProjects: false)
        #expect(!snapshot.problems.isEmpty && snapshot.problems.allSatisfy { !$0.contains(fixture.home.path) })
    }

    @Test("scrub replaces the settings file path and its symlink-resolved form with the label")
    func scrubBothForms() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root = base.appendingPathComponent("reins-scrub-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try Data("{}".utf8).write(to: real.appendingPathComponent("settings.json"))

        let given = link.appendingPathComponent("settings.json").path
        let resolved = real.appendingPathComponent("settings.json").path
        try #require(given != resolved)

        let text = "\(given) is not valid JSON; also seen as \(resolved)."
        #expect(InProcessCore.scrub(text, path: given, label: "global") == "global is not valid JSON; also seen as global.")
        #expect(InProcessCore.scrub("nothing to hide", path: given, label: "global") == "nothing to hide")
    }

    @Test("a project that discovery did not find falls back to the global snapshot, and a write to it is a 404")
    func unknownProject() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gone = fixture.home.appendingPathComponent("not-a-project").path
        let snapshot = try await fixture.core.rulesSnapshot(scope: .project, dir: gone, refreshProjects: true)
        #expect(snapshot.scope == .global)
        #expect(snapshot.dir == nil)
        do {
            _ = try await fixture.core.rulesAdd(scope: .project, dir: gone, verdict: .ask, rule: "Bash")
            Issue.record("the write was accepted")
        } catch let error as CoreError {
            #expect(error.status == 404)
        }
        do {
            _ = try await fixture.core.rulesAdd(scope: .project, dir: nil, verdict: .ask, rule: "Bash")
            Issue.record("the write was accepted")
        } catch let error as CoreError {
            #expect(error.status == 400)
        }
    }

    @Test("with no config folders every method fails with the startup sentence, status 500")
    func startupProblem() async {
        let core = InProcessCore(roots: nil, startupProblem: "SPACEVIBE_TEST must be 1 or 0, got \"banana\"")
        let expected = CoreError("SPACEVIBE_TEST must be 1 or 0, got \"banana\"", status: 500)
        await expectFailure(expected) { _ = try await core.rulesCheck(rule: "Bash") }
        await expectFailure(expected) { _ = try await core.rulesSnapshot(scope: .global, dir: nil, refreshProjects: false) }
        await expectFailure(expected) { _ = try await core.rulesPreview(scope: .global, dir: nil, capability: .run, verdict: .ask) }
    }

    @Test("a call cancelled before it starts throws CancellationError and does nothing")
    func cancelled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let core = fixture.core
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await core.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash")
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(Journal.history(fixture.roots).isEmpty)
    }

    @MainActor
    @Test("AppEnvironment carries an in-process core by default, and shows a CoreError's message")
    func environment() async throws {
        let env = AppEnvironment(roots: nil, startupProblem: "No folders.")
        #expect(try await env.core.initialize().identity.envPrefix == ReinsCore.envPrefix)
        await expectFailure(CoreError("No folders.", status: 500)) { _ = try await env.core.rulesCheck(rule: "Bash") }
        #expect(AppEnvironment.message(CoreError("Gone.", status: 404)) == "Gone.")
        // The core turns an engine ReinsError into a CoreError; a screen never gets the raw one.
        #expect(AppEnvironment.message(ReinsError("Refused.", status: 403)) == CoreError.unexpectedMessage)
        #expect(AppEnvironment.message(CancellationError()) == CoreError.unexpectedMessage)
    }

    private func expectFailure(_ expected: CoreError, _ work: () async throws -> Void) async {
        do {
            try await work()
            Issue.record("expected \(expected)")
        } catch let error as CoreError {
            #expect(error == expected)
        } catch {
            Issue.record("expected a CoreError, got \(error)")
        }
    }
}
