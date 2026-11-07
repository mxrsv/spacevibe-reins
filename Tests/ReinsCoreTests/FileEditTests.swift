import Foundation
import Testing
@testable import ReinsCore

@Suite("FileEdit")
struct FileEditTests {
    /// Stands in for a secret value in settings: it must never show up in an error, a label or the journal.
    private static let canary = "CANARY-sk-live-0123456789"

    private struct Sandbox {
        let home: TempHome
        let roots: Roots
        let settings: URL

        init() throws {
            home = try TempHome()
            roots = try home.roots
            settings = home.claude.appendingPathComponent("settings.json")
        }

        func bytes(_ url: URL? = nil) throws -> Data { try Data(contentsOf: url ?? settings) }
        func text(_ url: URL? = nil) throws -> String { String(decoding: try bytes(url), as: UTF8.self) }
        func journalBytes() -> Data { (try? Data(contentsOf: roots.data.appendingPathComponent("journal.json"))) ?? Data() }

        func trashFiles() -> [String] {
            let trash = roots.data.appendingPathComponent("trash")
            let slots = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
            return slots.flatMap { slot in
                ((try? FileManager.default.contentsOfDirectory(atPath: trash.appendingPathComponent(slot).path)) ?? []).map { "\(slot)/\($0)" }
            }
        }
    }

    private func addRule(_ rule: JSONValue) -> (OrderedJSON) throws -> OrderedJSON {
        { doc in
            doc[["permissions", "allow"]] == nil
                ? try doc.setting(["permissions", "allow"], to: .array([rule]))
                : try doc.appending(rule, to: ["permissions", "allow"])
        }
    }

    @Test("set then undo restores identical bytes and keeps the mode, for tab, space and CRLF files")
    func setThenUndo() throws {
        for original in [
            "{\n\t\"env\": {\"TOKEN\": \"\(Self.canary)\"},\n\t\"model\": \"x\"\n}\n",
            "{\n    \"model\": \"x\",\n    \"permissions\": {\n        \"allow\": [\"Read\"]\n    }\n}",
            "{\r\n  \"model\": \"x\"\r\n}\r\n",
        ] {
            let sandbox = try Sandbox()
            try sandbox.home.write(".claude/settings.json", original)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: sandbox.settings.path)
            let before = try sandbox.bytes()

            let entry = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added allow rule Read (global)", change: addRule("Read")))
            let after = try sandbox.text()
            #expect(after != original)
            #expect(try sandbox.home.mode(of: sandbox.settings) == 0o640)
            if original.contains("\r\n") { #expect(after.contains("\r\n") && !after.replacingOccurrences(of: "\r\n", with: "").contains("\n")) }
            if original.contains("\t") { #expect(after.contains("\t\"model\"")) }
            let parsed = try JSONSerialization.jsonObject(with: try sandbox.bytes()) as? [String: Any]
            #expect(((parsed?["permissions"] as? [String: Any])?["allow"] as? [String])?.contains("Read") == true)
            #expect(parsed?["model"] as? String == "x")

            #expect(try Journal.undo(sandbox.roots, id: entry.id) == "Added allow rule Read (global)")
            #expect(try sandbox.bytes() == before)
            #expect(try sandbox.home.mode(of: sandbox.settings) == 0o640)
            #expect(sandbox.home.strayTempFiles(in: sandbox.home.claude, sandbox.roots.data).isEmpty)
        }
    }

    @Test("undo is refused once the file changed, and leaves the hand edit alone")
    func undoRefusedAfterHandEdit() throws {
        let sandbox = try Sandbox()
        try sandbox.home.write(".claude/settings.json", "{}\n")
        let entry = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added", change: addRule("Read")))
        try sandbox.home.write(".claude/settings.json", "{\"model\":\"hand-edited\"}\n")

        let error = #expect(throws: ReinsError.self) { try Journal.undo(sandbox.roots, id: entry.id) }
        #expect(error?.status == 409)
        #expect(error?.message.contains("changed since") == true)
        #expect(try sandbox.text() == "{\"model\":\"hand-edited\"}\n")
        #expect(Journal.history(sandbox.roots).first?.undone == false)
    }

    @Test("a second undo of the same entry is refused")
    func doubleUndo() throws {
        let sandbox = try Sandbox()
        try sandbox.home.write(".claude/settings.json", "{}\n")
        let entry = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added", change: addRule("Read")))
        _ = try Journal.undo(sandbox.roots, id: entry.id)
        let error = #expect(throws: ReinsError.self) { try Journal.undo(sandbox.roots, id: entry.id) }
        #expect(error?.status == 409)
        #expect(error?.message.contains("already undone") == true)
        #expect(try sandbox.text() == "{}\n")
    }

    @Test("a validator that rejects the temp file leaves the target, the folder and the journal untouched")
    func failedWriteLeavesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.home.write(".claude/settings.json", "{\"model\":\"x\"}\n")
        let before = try sandbox.bytes()

        let error = #expect(throws: ReinsError.self) {
            try FileEdit.edit(sandbox.roots, file: sandbox.settings, label: "Never", validate: { _ in throw ReinsError("rejected", status: 409) }) { _ in "{\"model\":\"y\"}\n" }
        }
        #expect(error?.message == "rejected")
        #expect(try sandbox.bytes() == before)
        #expect(sandbox.home.strayTempFiles(in: sandbox.home.claude, sandbox.roots.data).isEmpty)
        #expect(sandbox.trashFiles().isEmpty, "no backup left for an edit that never happened")
        #expect(Journal.history(sandbox.roots).isEmpty)

        // A throwing `change` is the same.
        #expect(throws: ReinsError.self) { try FileEdit.edit(sandbox.roots, file: sandbox.settings, label: "Never") { _ in throw ReinsError("no") } }
        #expect(try sandbox.bytes() == before)
        #expect(sandbox.home.strayTempFiles(in: sandbox.home.claude, sandbox.roots.data).isEmpty)
    }

    @Test("invalid JSON and wrong shapes are refused with a 409 that never quotes content")
    func invalidInputRefused() throws {
        let sandbox = try Sandbox()
        let cases = [
            "{\"env\":{\"TOKEN\":\"\(Self.canary)\"} oops",
            "[\"\(Self.canary)\"]",
            "\"\(Self.canary)\"",
            "{\"a\":\"\(Self.canary)\",}",
        ]
        for content in cases {
            try sandbox.home.write(".claude/settings.json", content)
            let before = try sandbox.bytes()
            let error = #expect(throws: ReinsError.self) {
                try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Never", change: addRule("Read"))
            }
            #expect(error?.status == 409)
            #expect(error?.message.contains(Self.canary) == false)
            #expect(error?.message.contains("Nothing was changed") == true)
            #expect(try sandbox.bytes() == before)
        }
        #expect(Journal.history(sandbox.roots).isEmpty)
        #expect(sandbox.home.strayTempFiles(in: sandbox.home.claude, sandbox.roots.data).isEmpty)

        // The same file is also refused when the new bytes would not parse.
        try sandbox.home.write(".claude/settings.json", "{}\n")
        let broken = #expect(throws: ReinsError.self) {
            try FileEdit.edit(sandbox.roots, file: sandbox.settings, label: "Never", validate: { _ = try FileEdit.parseObject($0, file: sandbox.settings) }) { _ in "{\"a\":\(Self.canary)" }
        }
        #expect(broken?.status == 409)
        #expect(broken?.message.contains(Self.canary) == false)
        #expect(try sandbox.text() == "{}\n")
    }

    @Test("a symlinked settings file stays a symlink and the target is written")
    func symlinkKept() throws {
        let sandbox = try Sandbox()
        let target = try sandbox.home.write("shared/settings.json", "{}\n")
        try FileManager.default.createDirectory(at: sandbox.home.claude, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sandbox.settings, withDestinationURL: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)

        let entry = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added", change: addRule("Read")))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sandbox.settings.path)) == target.path)
        #expect(try sandbox.text(target).contains("\"Read\""))
        #expect(try sandbox.home.mode(of: target) == 0o600)

        _ = try Journal.undo(sandbox.roots, id: entry.id)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sandbox.settings.path)) == target.path)
        #expect(try sandbox.text(target) == "{}\n")
        #expect(sandbox.home.strayTempFiles(in: sandbox.home.claude, sandbox.roots.data).isEmpty)
    }

    @Test("a link to nothing is refused instead of being replaced")
    func danglingLink() throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.home.claude, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: sandbox.settings.path, withDestinationPath: sandbox.home.url("missing.json").path)
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Never", change: addRule("Read"))
        }
        #expect(error?.status == 409)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sandbox.settings.path)) != nil)
    }

    @Test("a missing file is created with mode 0600, and undo moves it to the trash")
    func createdFile() throws {
        let sandbox = try Sandbox()
        let project = sandbox.home.url("proj/.claude/settings.local.json")
        let entry = try #require(try FileEdit.editJSON(sandbox.roots, file: project, label: "Added", change: addRule("Bash(git status)")))
        #expect(try sandbox.home.mode(of: project) == 0o600)
        let text = try sandbox.text(project)
        #expect(text.hasSuffix("}\n"))
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        #expect(((parsed?["permissions"] as? [String: Any])?["allow"] as? [String]) == ["Bash(git status)"])

        _ = try Journal.undo(sandbox.roots, id: entry.id)
        #expect(!FileManager.default.fileExists(atPath: project.path))
        let trashed = sandbox.trashFiles()
        #expect(trashed.count == 1 && trashed[0].hasSuffix("/settings.local.json"))
    }

    @Test("a no-op writes nothing and records nothing, even for a missing file")
    func noOp() throws {
        let sandbox = try Sandbox()
        #expect(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Never") { $0 } == nil)
        #expect(!FileManager.default.fileExists(atPath: sandbox.settings.path))

        try sandbox.home.write(".claude/settings.json", "{\"model\":\"x\"}")
        let before = try sandbox.bytes()
        #expect(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Never") { $0 } == nil)
        #expect(try FileEdit.edit(sandbox.roots, file: sandbox.settings, label: "Never") { $0 } == nil)
        #expect(try sandbox.bytes() == before)
        #expect(Journal.history(sandbox.roots).isEmpty)
    }

    @Test("a blank file counts as an empty object")
    func blankFile() throws {
        let sandbox = try Sandbox()
        try sandbox.home.write(".claude/settings.json", "  \n")
        let entry = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added", change: addRule("Read")))
        #expect(try sandbox.text().contains("\"Read\""))
        _ = try Journal.undo(sandbox.roots, id: entry.id)
        #expect(try sandbox.text() == "  \n")
    }

    @Test("text edit keeps bytes that Swift string equality would treat as equal")
    func canonicalEquivalence() throws {
        let sandbox = try Sandbox()
        let precomposed = "caf\u{00E9}\n", decomposed = "cafe\u{0301}\n"
        try sandbox.home.write(".claude/notes.txt", precomposed)
        let file = sandbox.home.claude.appendingPathComponent("notes.txt")
        let entry = try #require(try FileEdit.edit(sandbox.roots, file: file, label: "Rewrote") { _ in decomposed })
        #expect(try sandbox.bytes(file) == Data(decomposed.utf8))
        _ = try Journal.undo(sandbox.roots, id: entry.id)
        #expect(try sandbox.bytes(file) == Data(precomposed.utf8))
    }

    @Test("a file that is not UTF-8 text is refused, not rewritten")
    func binaryRefused() throws {
        let sandbox = try Sandbox()
        let bytes = Data([0x7B, 0xFF, 0xFE, 0x7D])
        try sandbox.home.write(".claude/settings.json", bytes)
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Never", change: addRule("Read"))
        }
        #expect(error?.status == 409)
        #expect(try sandbox.bytes() == bytes)
    }

    @Test("a secret in the settings never appears in an error message, a label or the journal")
    func canaryNeverLeaks() throws {
        let sandbox = try Sandbox()
        let original = "{\n  \"env\": {\"TOKEN\": \"\(Self.canary)\"},\n  \"apiKeyHelper\": \"echo \(Self.canary)\"\n}\n"
        try sandbox.home.write(".claude/settings.json", original)
        var seen: [String] = []

        let first = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added allow rule Read (global)", change: addRule("Read")))
        let second = try #require(try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "Added allow rule Edit (global)", change: addRule("Edit")))
        seen += Journal.history(sandbox.roots).map { "\($0.label) \($0.id) \($0.at)" }

        // Hand edit with a broken file: every refusal message is collected.
        try sandbox.home.write(".claude/settings.json", "{\"env\":{\"TOKEN\":\"\(Self.canary)\"} oops")
        for attempt in [
            { _ = try FileEdit.editJSON(sandbox.roots, file: sandbox.settings, label: "x", change: addRule("Read")) },
            { _ = try Journal.undo(sandbox.roots, id: second.id) },
            { _ = try Journal.undo(sandbox.roots, id: first.id) },
        ] as [() throws -> Void] {
            do { try attempt() } catch { seen.append((error as? ReinsError)?.message ?? "\(error)"); seen.append(error.localizedDescription) }
        }

        #expect(seen.count >= 8)
        for text in seen { #expect(!text.contains(Self.canary)) }
        #expect(!String(decoding: sandbox.journalBytes(), as: UTF8.self).contains(Self.canary))
        // The old bytes do live in the trash (that is where undo reads them), never in the journal.
        #expect(sandbox.trashFiles().count == 2)
    }

    @Test("under SPACEVIBE_TEST=1 an edit refuses a path under the real home")
    func refusesRealHome() throws {
        let sandbox = try Sandbox()
        let real = URL(fileURLWithPath: Roots.realHomeDirectory()).appendingPathComponent(".spacevibe-never-written/settings.json")
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.editJSON(sandbox.roots, file: real, label: "Never", change: addRule("Read"))
        }
        #expect(error?.message.contains("real home") == true)
        #expect(!FileManager.default.fileExists(atPath: real.path))
    }
}
