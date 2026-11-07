import Foundation
import Testing
@testable import ReinsCore

/// The app runs every write and every Undo on its own thread. These tests drive the engine the same way: many threads at
/// once, against one journal and one settings file. Nothing here touches the real config (TempHome, SPACEVIBE_TEST=1).
@Suite("Write concurrency")
struct WriteConcurrencyTests {
    /// Collects results from `concurrentPerform` bodies; the bodies never call `#expect`.
    private final class Collector<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
        var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
    }

    @Test("200 concurrent records all survive, in the journal, with no temp file left")
    func concurrentRecords() throws {
        let home = try TempHome()
        let roots = try home.roots
        let failures = Collector<String>()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            do { try Journal.record(roots, label: "entry \(i)", ops: []) } catch { failures.add("\(i): \(error)") }
        }
        #expect(failures.all.isEmpty, "\(failures.all.prefix(3))")
        let labels = Set(Journal.history(roots).map(\.label))
        #expect(labels.count == 200)
        #expect(labels == Set((0..<200).map { "entry \($0)" }))
        #expect(home.strayTempFiles(in: roots.data).isEmpty)
    }

    @Test("50 concurrent rule additions to one settings.json all land, each with its own journal entry")
    func concurrentSettingsAppends() throws {
        let home = try TempHome()
        let roots = try home.roots
        let settings = try home.write(".claude/settings.json", "{\n  \"model\": \"keep\"\n}\n")
        let store = RulesStore(roots: roots)
        let outcomes = Collector<Int?>()   // nil = success, else the status of the refusal
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            do { try store.addRule(scope: .global, verdict: .allow, rule: "Bash(rule-\(i):*)"); outcomes.add(nil) } catch {
                outcomes.add((error as? ReinsError)?.status ?? -1)
            }
        }
        let succeeded = outcomes.all.filter { $0 == nil }.count
        // In one process the lock serializes the writers, so none may be refused; a refusal would be a 409, never a silent drop.
        #expect(succeeded == 50, "refusals: \(outcomes.all.compactMap { $0 })")
        let document = try OrderedJSON(data: try Data(contentsOf: settings))
        let allowed = document.root["permissions"]?["allow"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(allowed) == Set((0..<50).map { "Bash(rule-\($0):*)" }))
        #expect(allowed.count == succeeded)
        #expect(document.root["model"]?.stringValue == "keep")
        #expect(Journal.history(roots).count == succeeded)
        #expect(home.strayTempFiles(in: settings.deletingLastPathComponent(), roots.data).isEmpty)
    }

    @Test("an Undo interleaved with writes never loses an entry")
    func undoInterleaved() throws {
        let home = try TempHome()
        let roots = try home.roots
        var older: [JournalEntry] = []
        for i in 0..<20 {
            let folder = try home.write("made/\(i)/file.txt", "x").deletingLastPathComponent()
            older.append(try Journal.record(roots, label: "older \(i)", ops: [.created(path: folder.path)]))
        }
        let failures = Collector<String>()
        DispatchQueue.concurrentPerform(iterations: 120) { i in
            do {
                if i % 6 == 0 { _ = try Journal.undo(roots, id: older[i / 6].id) } else { try Journal.record(roots, label: "new \(i)", ops: []) }
            } catch { failures.add("\(i): \(error)") }
        }
        #expect(failures.all.isEmpty, "\(failures.all.prefix(3))")
        let history = Journal.history(roots)
        #expect(history.count == 20 + 100)
        #expect(Set(history.filter(\.undone).map(\.label)) == Set((0..<20).map { "older \($0)" }))
        #expect(history.filter { !$0.undone }.count == 100)
        for i in 0..<20 { #expect(!FileManager.default.fileExists(atPath: home.url("made/\(i)").path), "folder \(i) moved to the trash") }
        #expect(home.strayTempFiles(in: roots.data).isEmpty)
    }

    @Test("writers next to one target never share a temp file (the lock is not what protects this)")
    func uniqueTempNames() throws {
        let home = try TempHome()
        let target = home.url("shared/file.txt")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let failures = Collector<String>()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            do { try AtomicWrite.write(to: target.path, data: Data("writer \(i)\n".utf8), mode: 0o600) } catch { failures.add("\(i): \(error)") }
        }
        #expect(failures.all.isEmpty, "\(failures.all.prefix(3))")
        let text = String(decoding: try Data(contentsOf: target), as: UTF8.self)
        #expect(text.hasPrefix("writer ") && text.hasSuffix("\n"))
        #expect(home.strayTempFiles(in: target.deletingLastPathComponent()).isEmpty)
    }

    @Test("a file changed by someone else between the read and the rename is left alone (409)")
    func externalChangeBeforeRename() throws {
        let home = try TempHome()
        let roots = try home.roots
        let file = try home.write(".claude/settings.json", "{\n  \"model\": \"mine\"\n}\n")
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.apply(roots, file: file, validate: { _ in
                // `validate` runs on the temp file, after the read and before the rename: write the target from "another process".
                try Data("{\"model\":\"theirs\"}\n".utf8).write(to: file)
            }, change: { _ in "{\n  \"model\": \"next\"\n}\n" })
        }
        #expect(error?.status == 409)
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "{\"model\":\"theirs\"}\n")
        #expect(home.strayTempFiles(in: file.deletingLastPathComponent()).isEmpty)
        #expect(Journal.history(roots).isEmpty)
        let trash = roots.data.appendingPathComponent("trash")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []).isEmpty, "the unused backup slot is removed")
    }

    @Test("a file created by someone else while a new file is being written is left alone (409)")
    func externalCreateBeforeRename() throws {
        let home = try TempHome()
        let roots = try home.roots
        let file = home.claude.appendingPathComponent("settings.json")
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.apply(roots, file: file, validate: { _ in
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{}\n".utf8).write(to: file)
            }, change: { _ in "{\"model\":\"x\"}\n" })
        }
        #expect(error?.status == 409)
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "{}\n")
        #expect(home.strayTempFiles(in: file.deletingLastPathComponent()).isEmpty)
    }
}
