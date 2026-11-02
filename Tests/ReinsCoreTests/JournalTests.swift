import CryptoKit
import Foundation
import Testing
@testable import ReinsCore

@Suite("Journal")
struct JournalTests {
    private func roots(_ home: TempHome) throws -> Roots { try Roots.resolve(env: home.env) }
    private func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    private func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    @Test("sha256 matches CryptoKit and the Node core")
    func sha256() {
        #expect(ContentHash.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // `{"model":"y"}\n` hashed by the Node core in a real journal entry.
        #expect(ContentHash.sha256Hex(Data("{\"model\":\"y\"}\n".utf8)) == "e6435d1aa4741b10a9f7a2363778ee376b5a70c5905ff4d1fc6827b82d01f110")
        var generator = SystemRandomNumberGenerator()
        for count in [0, 1, 55, 56, 63, 64, 65, 119, 120, 1000, 100_000] {
            let data = Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
            #expect(ContentHash.sha256Hex(data) == hex(data), "length \(count)")
        }
    }

    @Test("record writes the Node layout: newest first, key order, lowercase id, ms timestamp, mode 0600")
    func recordLayout() throws {
        let home = try TempHome()
        let r = try roots(home)
        let first = try Journal.record(r, label: "first", ops: [.created(path: "/x/one")])
        let second = try Journal.record(r, label: "second", ops: [])

        #expect(first.id == first.id.lowercased() && first.id.count == 36)
        #expect(first.at.range(of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$"#, options: .regularExpression) != nil)
        #expect(Journal.history(r).map(\.label) == ["second", "first"])
        #expect(Journal.history(r).map(\.count) == [0, 1])
        #expect(Journal.history(r).allSatisfy { !$0.undone })

        let text = String(decoding: try read(home.reins.appendingPathComponent("journal.json")), as: UTF8.self)
        #expect(text.hasPrefix("[\n  {\n    \"id\": \"\(second.id)\",\n    \"at\": \"\(second.at)\",\n    \"label\": \"second\",\n    \"ops\": []\n  },"))
        #expect(!text.contains("undone"))
        #expect(!text.hasSuffix("\n"))
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        #expect(parsed.count == 2)

        let attributes = try FileManager.default.attributesOfItem(atPath: home.reins.appendingPathComponent("journal.json").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let trash = try FileManager.default.attributesOfItem(atPath: home.reins.appendingPathComponent("trash").path)
        #expect((trash[.posixPermissions] as? Int) == 0o700)
    }

    @Test("keeps at most 200 entries")
    func limit() throws {
        let home = try TempHome()
        let r = try roots(home)
        for i in 0..<205 { try Journal.record(r, label: "entry \(i)", ops: []) }
        let history = Journal.history(r)
        #expect(history.count == 200)
        #expect(history.first?.label == "entry 204")
    }

    @Test("reads a journal written by the Node core, undoes it, and keeps ops it cannot undo intact")
    func crossReadNodeJournal() throws {
        let home = try TempHome()
        let r = try roots(home)
        let settings = try home.write(".claude/settings.json", "{\"model\":\"y\"}\n")
        let backup = try home.write(".reins/trash/1793637068527-ff71479b/settings.json", "{\"model\":\"x\"}\n")
        let created = try home.write(".claude/skills/new/SKILL.md", "---\nname: new\n---\n")
        // Shape copied from an entry the Node core wrote (synthetic paths): a file edit, a created skill, a hook op.
        let nodeJournal = """
        [
          {
            "id": "e271c1e3-dfc2-4e9f-9d14-ba967210bee5",
            "at": "2026-11-02T16:31:08.528Z",
            "label": "Added allow rule Read (global)",
            "ops": [
              {
                "type": "file-edited",
                "file": "\(settings.path)",
                "existed": true,
                "backup": "\(backup.path)",
                "after": "e6435d1aa4741b10a9f7a2363778ee376b5a70c5905ff4d1fc6827b82d01f110"
              },
              {
                "type": "created",
                "path": "\(created.deletingLastPathComponent().path)"
              }
            ]
          },
          {
            "id": "11111111-2222-3333-4444-555555555555",
            "at": "2026-11-02T16:00:00.000Z",
            "label": "Added Stop hook to Claude Code",
            "undone": true,
            "ops": [
              {
                "type": "hook-added",
                "file": "\(settings.path)",
                "event": "Stop",
                "matcher": null,
                "hook": {
                  "type": "command",
                  "command": "echo",
                  "timeout": 5
                }
              }
            ]
          },
          {
            "id": "99999999-2222-3333-4444-555555555555",
            "at": "2026-11-02T15:00:00.000Z",
            "label": "Removed Stop hook from Claude Code",
            "ops": [
              { "type": "hook-removed", "file": "\(settings.path)", "event": "Stop", "matcher": null, "hook": { "type": "command", "command": "echo", "timeout": 5 } }
            ]
          }
        ]
        """
        try home.write(".reins/journal.json", nodeJournal)

        let history = Journal.history(r)
        #expect(history.map(\.count) == [2, 1, 1])
        #expect(history.map(\.undone) == [false, true, false])

        // Hook ops are undone by Mutate (see MutateTests); an entry that is already undone is refused.
        #expect(throws: ReinsError.self) { try Journal.undo(r, id: "11111111-2222-3333-4444-555555555555") }

        let label = try Journal.undo(r, id: "e271c1e3-dfc2-4e9f-9d14-ba967210bee5")
        #expect(label == "Added allow rule Read (global)")
        #expect(String(decoding: try read(settings), as: UTF8.self) == "{\"model\":\"x\"}\n")
        #expect(!FileManager.default.fileExists(atPath: created.deletingLastPathComponent().path))

        // Recording a new entry rewrites the file; the foreign ops (with their numbers and nulls) survive.
        try Journal.record(r, label: "later", ops: [])
        let after = Journal.entries(r)
        #expect(after.map(\.label) == ["later", "Added allow rule Read (global)", "Added Stop hook to Claude Code", "Removed Stop hook from Claude Code"])
        #expect(after.map(\.undone) == [false, true, true, false])
        let hook = try #require(after[2].ops.first)
        #expect(hook.type == "hook-added")
        #expect(hook.json["hook"]?["timeout"] == .number("5"))
        #expect(hook.json["matcher"] == .null)
    }

    @Test("an entry written here has the shape the Node core reads")
    func nodeCanReadOurEntry() throws {
        let home = try TempHome()
        let r = try roots(home)
        let file = try home.write(".claude/settings.json", "{}\n")
        let entry = try #require(try FileEdit.editJSON(r, file: file, label: "Added") { try $0.setting(["model"], to: "x") })
        _ = try Journal.undo(r, id: entry.id)
        let raw = try #require(JSONSerialization.jsonObject(with: try read(home.reins.appendingPathComponent("journal.json"))) as? [[String: Any]])
        let op = try #require((raw[0]["ops"] as? [[String: Any]])?.first)
        #expect(Set(op.keys) == ["type", "file", "existed", "backup", "after"])
        #expect(op["type"] as? String == "file-edited")
        #expect(op["existed"] as? Bool == true)
        #expect((op["after"] as? String)?.count == 64)
        #expect(raw[0]["undone"] as? Bool == true)
        // Node reads `file` as a real path and `backup` as a path inside the trash.
        #expect((op["backup"] as? String)?.hasPrefix(home.reins.appendingPathComponent("trash").path) == true)
    }

    @Test("unknown id is 404 and a second undo is 409")
    func undoErrors() throws {
        let home = try TempHome()
        let r = try roots(home)
        let missing = #expect(throws: ReinsError.self) { try Journal.undo(r, id: "nope") }
        #expect(missing?.status == 404)

        let entry = try Journal.record(r, label: "nothing", ops: [])
        _ = try Journal.undo(r, id: entry.id)
        let again = #expect(throws: ReinsError.self) { try Journal.undo(r, id: entry.id) }
        #expect(again?.status == 409)
        #expect(again?.message.contains("already undone") == true)
    }

    @Test("created, moved and link-removed ops undo in reverse order")
    func fileOps() throws {
        let home = try TempHome()
        let r = try roots(home)
        let skill = try home.write(".claude/skills/a/SKILL.md", "---\nname: a\n---\n")
        let skillDir = skill.deletingLastPathComponent()
        let shared = try home.write("shared/b/SKILL.md", "---\nname: b\n---\n")
        let link = home.claude.appendingPathComponent("skills/b")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: shared.deletingLastPathComponent())
        let fresh = try home.write(".claude/skills/c/SKILL.md", "c")

        let removedDir = try Trash.remove(r, path: skillDir.path)
        let removedLink = try Trash.remove(r, path: link.path)
        #expect(removedDir.type == "moved" && removedLink.type == "link-removed")
        #expect(!FileManager.default.fileExists(atPath: skillDir.path))
        #expect(FileManager.default.fileExists(atPath: shared.path), "removing a link leaves its target")
        let entry = try Journal.record(r, label: "Removed", ops: [removedDir, removedLink, .created(path: fresh.deletingLastPathComponent().path)])

        _ = try Journal.undo(r, id: entry.id)
        #expect(FileManager.default.fileExists(atPath: skill.path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == shared.deletingLastPathComponent().path)
        #expect(!FileManager.default.fileExists(atPath: fresh.path), "a created folder goes to the trash")
        #expect(Journal.history(r).first?.undone == true)
    }

    @Test("an entry that cannot be undone fully changes nothing")
    func neverPartial() throws {
        let home = try TempHome()
        let r = try roots(home)
        let created = try home.write("made/file.txt", "keep me")
        let edited = try home.write("edited.json", "{\"a\":1}\n")
        let backup = try home.write(".reins/trash/1-aaaaaaaa/edited.json", "{}\n")
        // Undo runs last op first: it moves `made` away, then refuses on the edited file (its hash does not match).
        let entry = try Journal.record(r, label: "Two ops", ops: [
            .fileEdited(file: edited.path, existed: true, backup: backup.path, after: String(repeating: "0", count: 64)),
            .created(path: created.deletingLastPathComponent().path),
        ])
        let error = #expect(throws: ReinsError.self) { try Journal.undo(r, id: entry.id) }
        #expect(error?.status == 409)
        #expect(FileManager.default.fileExists(atPath: created.path), "the first reversed op was put back")
        #expect(String(decoding: try read(edited), as: UTF8.self) == "{\"a\":1}\n")
        #expect(Journal.history(r).first?.undone == false)
    }
}
