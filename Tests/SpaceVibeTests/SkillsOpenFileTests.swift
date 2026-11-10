import Foundation
import Testing
@testable import SpaceVibe

/// H3: `Open file` never hands a link's target to the system. A `SKILL.md` that links to a `.command` would run in Terminal,
/// so only a resolved regular `.md` file opens and anything else is shown in Finder. Temp folders only (S-R1).
@MainActor
@Suite("Skills model, Open file")
struct SkillsOpenFileTests {
    private enum Call: Equatable { case open(URL), reveal(URL) }

    private func model(calls: @escaping (Call) -> Void) -> SkillsModel {
        let env = AppEnvironment(toasts: ToastCenter(announce: false))
        let model = SkillsModel(loadout: LoadoutModel(env: env))
        model.openFile = { calls(.open($0)) }
        model.revealFile = { calls(.reveal($0)) }
        return model
    }

    private func row(file: URL) -> LoadoutRow {
        let item = CoreInventoryItem(
            id: "claude:skill:global:demo", cli: .claude, kind: .skill, name: "demo", entry: "demo", description: "", owner: "user",
            path: file.deletingLastPathComponent().path, file: file.path, removable: true, scope: .global, project: nil, inOther: false,
            key: "skill::demo"
        )
        return LoadoutRow(
            key: "skill::demo", kind: .skill, project: nil, members: [.claude: .item(item)],
            cells: CoreCells(claude: .missing, codex: .missing), flags: CoreRowFlags(one: false, neverRan: false, dead: false),
            name: "demo", detail: "", plugin: nil, errors: 0, runs: 0, addedNote: nil
        )
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sv-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a SKILL.md linked to a .command is shown in Finder, never opened")
    func linkToCommandReveals() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("run.command")
        try "#!/bin/sh\necho hi\n".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("SKILL.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        var calls: [Call] = []
        model { calls.append($0) }.openFile(of: row(file: link))
        #expect(calls == [.reveal(target.resolvingSymlinksInPath())])
    }

    @Test("a SKILL.md linked to a .md opens the resolved file")
    func linkToMarkdownOpens() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("plain.md")
        try "# demo\n".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("SKILL.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        var calls: [Call] = []
        model { calls.append($0) }.openFile(of: row(file: link))
        #expect(calls == [.open(target.resolvingSymlinksInPath())])
    }

    @Test("a plain SKILL.md opens")
    func plainFileOpens() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("SKILL.md")
        try "# demo\n".write(to: file, atomically: true, encoding: .utf8)

        var calls: [Call] = []
        model { calls.append($0) }.openFile(of: row(file: file))
        #expect(calls == [.open(file.resolvingSymlinksInPath())])
    }

    @Test("a missing file or a folder is shown in Finder")
    func notARegularFileReveals() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folderNamedMd = dir.appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: folderNamedMd, withIntermediateDirectories: true)
        let missing = dir.appendingPathComponent("gone/SKILL.md")

        var calls: [Call] = []
        let model = model { calls.append($0) }
        model.openFile(of: row(file: folderNamedMd))
        model.openFile(of: row(file: missing))
        #expect(calls == [.reveal(folderNamedMd.resolvingSymlinksInPath()), .reveal(missing.resolvingSymlinksInPath())])
    }
}
