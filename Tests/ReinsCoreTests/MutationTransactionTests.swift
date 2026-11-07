import Foundation
import Testing
@testable import ReinsCore

@Suite("Mutation transactions")
struct MutationTransactionTests {
    enum Operation: CaseIterable {
        case rule, addSkill, addAgent, removeSkill, removeAgent, copySkill, copyAgent, addHook, removeHook, removeDeadHooks
    }

    private func seed(_ home: TempHome) throws -> Roots {
        let roots = try Roots.resolve(env: home.env)
        try home.write(".claude/settings.json", #"{"permissions":{"deny":["Bash"]}}"#)
        _ = try Mutate.addSkill(roots: roots, clis: [.claude], name: "existing-skill", description: "Synthetic skill")
        _ = try Mutate.addAgent(roots: roots, clis: [.claude], name: "existing-agent", description: "Synthetic agent")
        for name in ["missing-first.sh", "missing-second.sh"] {
            _ = try Mutate.addHook(roots: roots, clis: [.claude], event: "Stop", command: home.url(name).path)
        }
        try home.write(".spacevibe/journal.json", "[]")
        return roots
    }

    private func run(_ operation: Operation, roots: Roots) throws {
        let inventory = Inventory.read(roots: roots)
        func item(_ kind: InventoryKind) throws -> String {
            try #require(inventory.items.first { $0.kind == kind && $0.cli == .claude }).id
        }
        switch operation {
        case .rule:
            _ = try RulesStore(roots: roots).changeVerdict(scope: .global, rule: "Bash", from: .deny, to: .allow)
        case .addSkill:
            _ = try Mutate.addSkill(roots: roots, clis: [.claude, .codex], name: "new-skill", description: "Synthetic")
        case .addAgent:
            _ = try Mutate.addAgent(roots: roots, clis: [.claude, .codex], name: "new-agent", description: "Synthetic")
        case .removeSkill: _ = try Mutate.removeItem(roots: roots, id: item(.skill))
        case .removeAgent: _ = try Mutate.removeItem(roots: roots, id: item(.agent))
        case .copySkill: _ = try Mutate.copyToOther(roots: roots, id: item(.skill))
        case .copyAgent: _ = try Mutate.copyToOther(roots: roots, id: item(.agent))
        case .addHook:
            _ = try Mutate.addHook(roots: roots, clis: [.claude, .codex], event: "Stop", command: "echo synthetic")
        case .removeHook:
            _ = try Mutate.removeItem(roots: roots, id: #require(inventory.hooks.first).id)
        case .removeDeadHooks:
            #expect(inventory.hooks.filter { $0.cli == .claude && $0.dead }.count == 2)
            _ = try Mutate.removeDeadHooks(roots: roots, cli: .claude)
        }
    }

    /// Compare all agent configuration bytes, including copied skill files; empty parent folders are harmless.
    private func contents(_ roots: Roots) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for base in [roots.claude.root, roots.codex.root] {
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let file as URL in files {
                if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    result[file.path] = try Data(contentsOf: file)
                }
            }
        }
        return result
    }

    @Test("corrupt history refuses every mutation before touching configuration", arguments: Operation.allCases)
    func corruptJournal(_ operation: Operation) throws {
        let home = try TempHome()
        let roots = try seed(home)
        let before = try contents(roots)
        let trash = try FileManager.default.contentsOfDirectory(atPath: home.url(".spacevibe/trash").path).sorted()
        try home.write(".spacevibe/journal.json", "{ invalid history")
        let error = #expect(throws: ReinsError.self) { try run(operation, roots: roots) }
        #expect(error?.message == Journal.unreadableMessage)
        #expect(try contents(roots) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.url(".spacevibe/trash").path).sorted() == trash)
        #expect(try String(contentsOf: home.url(".spacevibe/journal.json"), encoding: .utf8) == "{ invalid history")
    }

    @Test("journal persistence failure restores every mutation, including shared hook backups",
          .enabled(if: geteuid() != 0, "root ignores folder permissions"), arguments: Operation.allCases)
    func persistenceFailure(_ operation: Operation) throws {
        let home = try TempHome()
        let roots = try seed(home)
        let before = try contents(roots)
        // Preflight can read the journal and mutations can save backups in the existing writable trash.
        // Only creating the atomic journal temp file fails, after the config mutation completed.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: roots.data.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: roots.data.path) }
        let error = #expect(throws: ReinsError.self) { try run(operation, roots: roots) }
        #expect(error?.status == 500)
        #expect(error?.message.contains("journal.json.spacevibe-") == true)
        #expect(error?.message != Journal.rollbackFailureMessage)
        #expect(try contents(roots) == before)
        #expect(try String(contentsOf: home.url(".spacevibe/journal.json"), encoding: .utf8) == "[]")
        let paths = FileManager.default.enumerator(atPath: home.root.path)?.allObjects as? [String] ?? []
        #expect(!paths.contains { $0.contains(".spacevibe-") && $0.hasSuffix(".tmp") })
    }

    @Test("a journal that fails after preflight restores a symlink target and its mode")
    func failureAfterPreflight() throws {
        let home = try TempHome()
        let roots = try seed(home)
        let target = try home.write("dotfiles/settings.json", "{}\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        let link = home.url(".claude/linked-settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let error = #expect(throws: ReinsError.self) {
            try FileEdit.editJSON(roots, file: link, label: "Synthetic edit") { document in
                // This closure runs after the journal preflight, before the config mutation.
                try FileManager.default.removeItem(at: home.url(".spacevibe/journal.json"))
                try FileManager.default.createDirectory(at: home.url(".spacevibe/journal.json"), withIntermediateDirectories: false)
                return try document.setting(["model"], to: "synthetic")
            }
        }
        #expect(error?.message == Journal.unreadableMessage)
        #expect(try String(contentsOf: target, encoding: .utf8) == "{}\n")
        #expect((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test("rollback failure preserves a concurrent edit and still restores the other operations")
    func rollbackFailure() throws {
        let home = try TempHome()
        let roots = try seed(home)
        let codex = try home.write(".codex/config.toml", "model = \"before\"\n")
        let error = #expect(throws: ReinsError.self) {
            try WriteLock.run {
                try Journal.prepareMutation(roots)
                let first = try #require(FileEdit.apply(roots, file: codex) { _ in "model = \"after\"\n" })
                let op = try #require(FileEdit.apply(roots, file: roots.claude.hookFile) { _ in "{}\n" })
                try home.write(".claude/settings.json", "concurrent writer\n")
                try home.write(".spacevibe/journal.json", "{ now corrupt")
                return try Journal.recordMutation(roots, label: "Synthetic edit", ops: [first, op])
            }
        }
        #expect(error?.status == 500)
        #expect(error?.message == Journal.rollbackFailureMessage)
        #expect(try String(contentsOf: roots.claude.hookFile, encoding: .utf8) == "concurrent writer\n")
        #expect(try String(contentsOf: codex, encoding: .utf8) == "model = \"before\"\n")
    }
}
