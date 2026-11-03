import Foundation
import Testing
@testable import ReinsCore

@Suite("Roots")
struct RootsTests {
    /// A stand-in for the real home: the guard compares against whatever `realHome` says.
    private func twoFolders() throws -> (fakeReal: TempHome, scratch: TempHome) {
        (try TempHome(), try TempHome())
    }

    @Test("accepts temp roots and derives the CLI folders")
    func acceptsTempRoots() throws {
        let (fakeReal, scratch) = try twoFolders()
        let roots = try Roots.resolve(env: scratch.env, realHome: fakeReal.root.path)
        #expect(roots.claude.root.path == scratch.claude.path)
        #expect(roots.claude.hookFile.path == scratch.claude.appendingPathComponent("settings.json").path)
        #expect(roots.claude.logs.lastPathComponent == "projects")
        #expect(roots.codex.hookFile.lastPathComponent == "hooks.json")
        #expect(roots.codex.logs.lastPathComponent == "sessions")
        #expect(roots.codex.skills.lastPathComponent == "skills")
        #expect(roots.data.path == scratch.reins.path)
    }

    @Test("Claude Code's state file follows CLAUDE_CONFIG_DIR, else sits in HOME; Gemini CLI's folder is in HOME")
    func stateFileAndGemini() throws {
        let (fakeReal, scratch) = try twoFolders()
        let configured = try Roots.resolve(env: scratch.env, realHome: fakeReal.root.path)
        #expect(configured.claudeState.path == scratch.claude.appendingPathComponent(".claude.json").path)
        #expect(configured.gemini.path == scratch.url(".gemini").path)
        var env = scratch.env
        env["CLAUDE_CONFIG_DIR"] = nil
        #expect(try Roots.resolve(env: env, realHome: fakeReal.root.path).claudeState.path == scratch.url(".claude.json").path)
    }

    @Test("falls back to folders under HOME and ignores empty values")
    func defaults() throws {
        let (fakeReal, scratch) = try twoFolders()
        let env = ["HOME": scratch.root.path, "CLAUDE_CONFIG_DIR": "", "REINS_TEST": "1"]
        let roots = try Roots.resolve(env: env, realHome: fakeReal.root.path)
        #expect(roots.claude.root.path == scratch.claude.path)
        #expect(roots.codex.root.path == scratch.codex.path)
        #expect(roots.data.path == scratch.reins.path)
    }

    @Test("REINS_TEST=1 refuses a root under the real home")
    func refusesRealRoots() throws {
        let (fakeReal, scratch) = try twoFolders()
        for key in ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "REINS_HOME"] {
            var env = scratch.env
            env[key] = fakeReal.root.appendingPathComponent("deep/dir").path
            #expect(throws: RootsError.self, "\(key) under the real home") {
                _ = try Roots.resolve(env: env, realHome: fakeReal.root.path)
            }
        }
        // HOME itself being the real home means all three defaults are real.
        var env = scratch.env
        for key in ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "REINS_HOME"] { env[key] = nil }
        env["HOME"] = fakeReal.root.path
        #expect(throws: RootsError.self) { _ = try Roots.resolve(env: env, realHome: fakeReal.root.path) }
    }

    @Test("the error names the root and the label")
    func errorDetails() throws {
        let (fakeReal, scratch) = try twoFolders()
        var env = scratch.env
        env["CODEX_HOME"] = fakeReal.root.appendingPathComponent(".codex").path
        do {
            _ = try Roots.resolve(env: env, realHome: fakeReal.root.path)
            Issue.record("expected an error")
        } catch let error as RootsError {
            #expect(error == .underRealHome(label: "codex", path: env["CODEX_HOME"]!))
        }
    }

    @Test("a symlink that leads into the real home is refused, even for a root that does not exist yet")
    func refusesThroughSymlinks() throws {
        let (fakeReal, scratch) = try twoFolders()
        try FileManager.default.createDirectory(at: fakeReal.claude, withIntermediateDirectories: true)
        let link = scratch.url("innocent")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fakeReal.claude)

        var env = scratch.env
        env["CLAUDE_CONFIG_DIR"] = link.path
        #expect(throws: RootsError.self) { _ = try Roots.resolve(env: env, realHome: fakeReal.root.path) }

        env["CLAUDE_CONFIG_DIR"] = link.appendingPathComponent("not/created/yet").path
        #expect(throws: RootsError.self) { _ = try Roots.resolve(env: env, realHome: fakeReal.root.path) }
    }

    @Test("a symlinked home is compared by its real path")
    func realHomeBehindSymlink() throws {
        let (fakeReal, scratch) = try twoFolders()
        let alias = scratch.url("home-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fakeReal.root)
        var env = scratch.env
        env["CLAUDE_CONFIG_DIR"] = fakeReal.claude.path
        #expect(throws: RootsError.self) { _ = try Roots.resolve(env: env, realHome: alias.path) }
    }

    @Test("a sibling folder whose name starts like the real home is not under it")
    func prefixIsNotAncestor() throws {
        let scratch = try TempHome()
        let home = scratch.url("me").path
        var env = scratch.env
        env["CLAUDE_CONFIG_DIR"] = scratch.url("me-other/.claude").path
        _ = try Roots.resolve(env: env, realHome: home)
    }

    @Test("without REINS_TEST nothing is checked")
    func noGuardWithoutFlag() throws {
        let (fakeReal, scratch) = try twoFolders()
        var env = scratch.env
        env["REINS_TEST"] = nil
        env["CLAUDE_CONFIG_DIR"] = fakeReal.claude.path
        #expect(try Roots.resolve(env: env, realHome: fakeReal.root.path).claude.root.path == fakeReal.claude.path)
        env["REINS_TEST"] = "0"
        _ = try Roots.resolve(env: env, realHome: fakeReal.root.path)
    }

    @Test("the account's real home, as the password database says, is refused")
    func theActualRealHome() throws {
        let real = Roots.realHomeDirectory()
        #expect(!real.isEmpty)
        // Pure path resolution: nothing is read or written under the real home.
        let env = ["HOME": real, "REINS_TEST": "1"]
        #expect(throws: RootsError.self) { _ = try Roots.resolve(env: env) }
        // And the default environment of this very test run (scripts/test.sh sets REINS_TEST=1) is never the real home.
        let temp = try TempHome()
        _ = try Roots.resolve(env: temp.env)
    }
}
