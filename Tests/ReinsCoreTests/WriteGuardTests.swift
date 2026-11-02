import Foundation
import Testing
@testable import ReinsCore

/// Refusals in the write path: links that point out of a project, a path outside the CLI folder, files and folders that
/// cannot be written, rollback of a half-made skill, and the edges of a hook timeout. Every test uses a TempHome.
@Suite("Write guards")
struct WriteGuardTests {
    private struct Sandbox {
        let home: TempHome
        let roots: Roots

        init() throws {
            home = try TempHome()
            roots = try Roots.resolve(env: home.env)
        }

        func store(projects: [String] = []) -> RulesStore { RulesStore(roots: roots, projects: { projects }) }
        func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }
        var journalEmpty: Bool { Journal.history(roots).isEmpty }
        func folderNames(_ url: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
        var trashSlots: [String] { folderNames(roots.data.appendingPathComponent("trash")) }
        func strayTemps(_ folder: URL) -> [String] { folderNames(folder).filter { $0.hasSuffix(".tmp") } }
    }

    /// chmod that is put back when the scope ends, so TempHome can delete the folder.
    private func withMode<T>(_ mode: Int, _ url: URL, _ body: () throws -> T) throws -> T {
        let old = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: old], ofItemAtPath: url.path) }
        return try body()
    }

    // MARK: Rules: links out of the project

    @Test("a project whose .claude is a link to another folder is refused (409) and that folder is untouched")
    func claudeFolderLinkEscapes() throws {
        let sb = try Sandbox()
        let project = sb.home.url("proj")
        let elsewhere = try sb.home.write("elsewhere/settings.json", "{\"model\":\"theirs\"}\n").deletingLastPathComponent()
        try sb.home.write("elsewhere/settings.local.json", "{\"model\":\"theirs-local\"}\n")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent(".claude"), withDestinationURL: elsewhere)
        let store = sb.store(projects: [project.path])
        let before = sb.folderNames(elsewhere)

        for scope in [RuleScope.project(project.path), .local(project.path)] {
            let error = #expect(throws: ReinsError.self) { try store.addRule(scope: scope, verdict: .allow, rule: "Bash(ls:*)") }
            #expect(error?.status == 409, "\(scope)")
        }
        #expect(try sb.text(elsewhere.appendingPathComponent("settings.json")) == "{\"model\":\"theirs\"}\n")
        #expect(try sb.text(elsewhere.appendingPathComponent("settings.local.json")) == "{\"model\":\"theirs-local\"}\n")
        #expect(sb.folderNames(elsewhere) == before)
        #expect(sb.journalEmpty)

        let listing = try store.listRules([.project(project.path)])
        #expect(listing.rules.isEmpty && listing.problems.count == 1)
    }

    @Test("a project settings file that is a link to another file is refused (409) and that file is untouched")
    func settingsFileLinkEscapes() throws {
        let sb = try Sandbox()
        let project = sb.home.url("proj")
        let other = try sb.home.write("other.json", "{\"permissions\":{\"allow\":[\"Read\"]}}\n")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        for name in ["settings.json", "settings.local.json"] {
            try FileManager.default.createSymbolicLink(at: project.appendingPathComponent(".claude/\(name)"), withDestinationURL: other)
        }
        let store = sb.store(projects: [project.path])
        let before = try sb.text(other)
        for scope in [RuleScope.project(project.path), .local(project.path)] {
            let error = #expect(throws: ReinsError.self) { try store.addRule(scope: scope, verdict: .deny, rule: "Bash(rm:*)") }
            #expect(error?.status == 409, "\(scope)")
            #expect(throws: ReinsError.self) { try store.removeRule(scope: scope, verdict: .allow, rule: "Read") }
        }
        #expect(try sb.text(other) == before)
        #expect(sb.journalEmpty)
    }

    @Test("a normal project is still edited, and the global settings file may be a link (followed)")
    func controlsStillWork() throws {
        let sb = try Sandbox()
        let project = sb.home.url("proj")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let store = sb.store(projects: [project.path])
        try store.addRule(scope: .project(project.path), verdict: .allow, rule: "Bash(ls:*)")
        try store.addRule(scope: .local(project.path), verdict: .ask, rule: "Bash(git push:*)")
        #expect(try sb.text(project.appendingPathComponent(".claude/settings.json")).contains("Bash(ls:*)"))
        #expect(try sb.text(project.appendingPathComponent(".claude/settings.local.json")).contains("Bash(git push:*)"))

        let dotfiles = try sb.home.write("dotfiles/claude-settings.json", "{}\n")
        try FileManager.default.createDirectory(at: sb.roots.claude.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sb.roots.claude.hookFile, withDestinationURL: dotfiles)
        try store.addRule(scope: .global, verdict: .allow, rule: "Read")
        #expect(try sb.text(dotfiles).contains("\"Read\""))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sb.roots.claude.hookFile.path)) == dotfiles.path, "still a link")
    }

    // MARK: Removal outside the CLI folder

    private func item(_ roots: Roots, path: String) -> InventoryItem {
        InventoryItem(
            id: "claude:skill:user:victim", cli: .claude, kind: .skill, name: "victim", entry: "victim", description: "",
            owner: "user", path: path, file: path + "/SKILL.md", removable: true, scope: .global, project: nil
        )
    }

    @Test("removing a skill whose path goes out of the CLI folder is 403 and changes nothing")
    func removeOutsideCLIFolder() throws {
        let sb = try Sandbox()
        let victim = try sb.home.write("outside/victim/SKILL.md", "---\nname: victim\n---\n").deletingLastPathComponent()
        try FileManager.default.createDirectory(at: sb.roots.claude.skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sb.roots.claude.skills.appendingPathComponent("hop"), withDestinationURL: victim.deletingLastPathComponent()
        )
        // A link in the middle of the path (lexically inside the folder), and a `..` path (lexically outside).
        for path in [sb.roots.claude.skills.path + "/hop/victim", sb.roots.claude.skills.path + "/../../outside/victim"] {
            let error = #expect(throws: ReinsError.self) { try Mutate.removeFile(roots: sb.roots, item: item(sb.roots, path: path)) }
            #expect(error?.status == 403, "\(path)")
            #expect(error?.message == "Refusing a path outside the CLI folder.")
        }
        #expect(FileManager.default.fileExists(atPath: victim.appendingPathComponent("SKILL.md").path))
        #expect(sb.folderNames(victim.deletingLastPathComponent()) == ["victim"])
        #expect(sb.journalEmpty && sb.trashSlots.isEmpty)
    }

    @Test("a skills folder that is itself a link (dotfiles) still lets its skills be removed")
    func removeThroughLinkedSkillsFolder() throws {
        let sb = try Sandbox()
        try sb.home.write("dotfiles/skills/mine/SKILL.md", "---\nname: mine\ndescription: d\n---\n")
        try FileManager.default.createDirectory(at: sb.roots.claude.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sb.roots.claude.skills, withDestinationURL: sb.home.url("dotfiles/skills"))
        let found = try #require(Inventory.read(roots: sb.roots).items.first { $0.name == "mine" })
        let entry = try Mutate.removeItem(roots: sb.roots, id: found.id)
        #expect(entry.label == "Removed skill mine from Claude Code")
        #expect(!FileManager.default.fileExists(atPath: sb.home.url("dotfiles/skills/mine").path))
        _ = try Journal.undo(sb.roots, id: entry.id)
        #expect(FileManager.default.fileExists(atPath: sb.home.url("dotfiles/skills/mine/SKILL.md").path))
    }

    // MARK: Creating in two CLIs

    @Test("addSkill into both CLIs: when the second folder cannot be written the first skill is gone and nothing is recorded",
          .enabled(if: geteuid() != 0, "root ignores folder permissions"))
    func createAllRollback() throws {
        let sb = try Sandbox()
        try FileManager.default.createDirectory(at: sb.roots.claude.skills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sb.roots.codex.skills, withIntermediateDirectories: true)
        let error = try withMode(0o500, sb.roots.codex.skills) {
            #expect(throws: ReinsError.self) {
                try Mutate.addSkill(roots: sb.roots, clis: [.claude, .codex], name: "both", description: "when needed")
            }
        }
        #expect(error?.status == 500)
        #expect(!FileManager.default.fileExists(atPath: sb.roots.claude.skills.appendingPathComponent("both").path), "the first CLI's skill is gone")
        #expect(sb.folderNames(sb.roots.codex.skills).isEmpty)
        #expect(sb.journalEmpty)
        #expect(Journal.entries(sb.roots).isEmpty)
        // The skill went to the app trash instead of being deleted; the codex path that never existed made no empty slot.
        #expect(sb.trashSlots.count == 1)
    }

    // MARK: FileEdit refusals

    @Test("a settings path that is a folder is refused (409): no temp file, no journal entry, no trash slot")
    func settingsPathIsFolder() throws {
        let sb = try Sandbox()
        let settings = sb.roots.claude.hookFile
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.editJSON(sb.roots, file: settings, label: "Added") { try $0.setting(["model"], to: "x") }
        }
        #expect(error?.status == 409 && error?.message.contains("not a regular file") == true)
        #expect(sb.folderNames(settings).isEmpty)
        #expect(sb.strayTemps(settings.deletingLastPathComponent()).isEmpty)
        #expect(sb.journalEmpty && sb.trashSlots.isEmpty)
    }

    @Test("a read-only folder: 500, file untouched, no journal entry, no temp file, no trash slot",
          .enabled(if: geteuid() != 0, "root ignores folder permissions"))
    func readOnlyFolder() throws {
        let sb = try Sandbox()
        let settings = try sb.home.write(".claude/settings.json", "{\n  \"model\": \"keep\"\n}\n")
        let folder = settings.deletingLastPathComponent()

        for existing in [true, false] {
            let file = existing ? settings : folder.appendingPathComponent("settings.local.json")
            let error = try withMode(0o500, folder) {
                #expect(throws: ReinsError.self) {
                    try FileEdit.editJSON(sb.roots, file: file, label: "Added") { try $0.setting(["model"], to: "changed") }
                }
            }
            #expect(error?.status == 500, "existing: \(existing)")
            #expect(!(error?.message.contains("keep") ?? false))
        }
        #expect(try sb.text(settings) == "{\n  \"model\": \"keep\"\n}\n")
        #expect(sb.folderNames(folder) == ["settings.json"])
        #expect(sb.journalEmpty && sb.trashSlots.isEmpty)
    }

    // MARK: Hook timeout and undo

    private func hookTimeout(_ sb: Sandbox, _ timeout: Double?) throws -> JSONValue? {
        let entry = try Mutate.addHook(roots: sb.roots, clis: [.claude], event: "Stop", command: "echo t", timeout: timeout)
        let doc = try OrderedJSON(data: try Data(contentsOf: sb.roots.claude.hookFile))
        _ = try Journal.undo(sb.roots, id: entry.id)
        return doc.root["hooks"]?["Stop"]?[0]?["hooks"]?[0]
    }

    @Test("hook timeout: 0 and nil leave the key out (as Node does), whole numbers have no decimals, 2.5 stays 2.5")
    func hookTimeoutFormats() throws {
        let sb = try Sandbox()
        let none = try #require(try hookTimeout(sb, nil))
        let zero = try #require(try hookTimeout(sb, 0))
        let negativeZero = try #require(try hookTimeout(sb, -0.0))
        #expect(none["timeout"] == nil && zero["timeout"] == nil && negativeZero["timeout"] == nil)
        #expect(try hookTimeout(sb, 30)?["timeout"] == .number("30"))
        #expect(try hookTimeout(sb, 2.5)?["timeout"] == .number("2.5"))
        #expect(try hookTimeout(sb, 0.25)?["timeout"] == .number("0.25"))
    }

    @Test("hook timeout: nan and infinity are refused (400) and nothing is written")
    func hookTimeoutNonFinite() throws {
        let sb = try Sandbox()
        for value in [Double.nan, .infinity, -.infinity] {
            let error = #expect(throws: ReinsError.self) {
                try Mutate.addHook(roots: sb.roots, clis: [.claude], event: "Stop", command: "echo t", timeout: value)
            }
            #expect(error?.status == 400, "\(value)")
        }
        #expect(!FileManager.default.fileExists(atPath: sb.roots.claude.hookFile.path))
        #expect(sb.journalEmpty)
    }

    @Test("undo after a hand edit, on a hook file the same entry created: the hook goes, the hand edit stays")
    func undoHookFileCreatedBySameEntryAfterHandEdit() throws {
        let sb = try Sandbox()
        let file = sb.roots.claude.hookFile
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let entry = try Mutate.addHook(roots: sb.roots, clis: [.claude], event: "Stop", command: "echo made", timeout: 5)
        #expect(entry.ops.first?.json["restore"]?["existed"] == .bool(false), "the entry created the file")
        let edited = try OrderedJSON(data: try Data(contentsOf: file)).setting(["model"], to: "by-hand")
        try edited.data.write(to: file)

        _ = try Journal.undo(sb.roots, id: entry.id)
        let now = try OrderedJSON(data: try Data(contentsOf: file))
        #expect(now.root["model"]?.stringValue == "by-hand")
        #expect(Inventory.read(roots: sb.roots).hooks.filter { $0.command == "echo made" }.isEmpty)
        #expect(Journal.history(sb.roots).first?.undone == true)
        #expect(sb.strayTemps(file.deletingLastPathComponent()).isEmpty)
    }
}
