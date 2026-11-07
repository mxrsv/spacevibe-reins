import Foundation

// Hook writes and their undo. A hook op keeps the shape the Node core writes (`type`, `file`, `event`, `matcher`, `hook`)
// plus `restore`: the `file-edited` op of the exact edit. Undo puts the old bytes back when the file still holds what
// that edit wrote, so the file comes back byte for byte; if the file changed since, it falls back to the logical
// reverse (remove or re-add the hook), which is all the Node core ever does. Node ignores the extra key.
extension Mutate {
    /// Adds one hook to the hook file of each CLI.
    public static func addHook(
        roots: Roots,
        clis: [InventoryCLI],
        event: String,
        matcher: String? = nil,
        command: String,
        timeout: Double? = nil
    ) throws -> JournalEntry {
        try WriteLock.run(roots) { try addHookLocked(roots: roots, clis: clis, event: event, matcher: matcher, command: command, timeout: timeout) }
    }

    private static func addHookLocked(
        roots: Roots, clis: [InventoryCLI], event: String, matcher: String?, command: String, timeout: Double?
    ) throws -> JournalEntry {
        try Journal.prepareMutation(roots)
        let command = ActivityText.trim(command)
        try need(!command.isEmpty, "Enter the command this hook runs.")
        try requireCLIs(clis)
        for cli in clis { try need(events(cli).contains(event), "\(label(cli)) has no \(event) event.") }
        let matcher = matcher.map(ActivityText.trim).flatMap { $0.isEmpty ? nil : $0 }
        let hook = try HookEdit.hookValue(command: command, timeout: timeout)

        var ops: [JournalOp] = []
        do {
            for cli in clis {
                let file = cliRoots(roots, cli).hookFile
                let edit = try FileEdit.applyJSON(roots, file: file) { doc in
                    try HookEdit.adding(doc, file: file.path, event: event, matcher: matcher, hook: hook)
                }
                guard let edit else { continue }
                ops.append(hookOp("hook-added", file: file.path, event: event, matcher: matcher, hook: hook, restore: edit))
            }
        } catch {
            // A later CLI failed: put back the files already changed so no change is left without a journal entry.
            try Journal.rollbackMutation(roots, ops: ops)
            throw error
        }
        return try Journal.recordMutation(roots, label: "Added \(event) hook to \(labels(clis))", ops: ops)
    }

    static func removeHook(roots: Roots, hook item: InventoryHook) throws -> JournalEntry {
        try Journal.prepareMutation(roots)
        let file = cliRoots(roots, item.cli).hookFile
        var removed: JSONValue?
        let edit = try FileEdit.applyJSON(roots, file: file) { doc in
            let result = try HookEdit.removing(doc, file: file.path, event: item.event, matcher: item.matcher, command: item.command)
            removed = result.found
            try need(removed != nil, "This hook has already changed. Refresh the list.", 409)
            return result.doc
        }
        guard let edit, let removed else { throw ReinsError("This hook has already changed. Refresh the list.", status: 409) }
        let op = hookOp("hook-removed", file: file.path, event: item.event, matcher: item.matcher, hook: removed, restore: edit)
        return try Journal.recordMutation(roots, label: "Removed \(item.event) hook from \(label(item.cli))", ops: [op])
    }

    /// Removes every dead, user-level hook of one CLI in one file write and one journal entry.
    public static func removeDeadHooks(roots: Roots, cli: InventoryCLI) throws -> JournalEntry {
        try WriteLock.run(roots) { try removeDeadHooksLocked(roots: roots, cli: cli) }
    }

    private static func removeDeadHooksLocked(roots: Roots, cli: InventoryCLI) throws -> JournalEntry {
        try Journal.prepareMutation(roots)
        let dead = Inventory.read(roots: roots).hooks.filter { $0.cli == cli && $0.dead && $0.removable }
        try need(!dead.isEmpty, "No dead hooks to remove.", 409)
        let file = cliRoots(roots, cli).hookFile
        var removed: [(hook: InventoryHook, value: JSONValue)] = []
        let edit = try FileEdit.applyJSON(roots, file: file) { doc in
            var doc = doc
            for hook in dead {
                let result = try HookEdit.removing(doc, file: file.path, event: hook.event, matcher: hook.matcher, command: hook.command)
                doc = result.doc
                if let found = result.found { removed.append((hook, found)) }
            }
            return doc
        }
        guard let edit, !removed.isEmpty else { throw ReinsError("No dead hooks to remove.", status: 409) }
        let ops = removed.map { hookOp("hook-removed", file: file.path, event: $0.hook.event, matcher: $0.hook.matcher, hook: $0.value, restore: edit) }
        return try Journal.recordMutation(roots, label: "Removed \(ops.count) dead hooks from \(label(cli))", ops: ops)
    }

    private static func hookOp(_ type: String, file: String, event: String, matcher: String?, hook: JSONValue, restore: JournalOp) -> JournalOp {
        JournalOp(json: .object([
            JSONMember("type", .string(type)), JSONMember("file", .string(file)), JSONMember("event", .string(event)),
            JSONMember("matcher", matcher.map(JSONValue.string) ?? .null), JSONMember("hook", hook), JSONMember("restore", restore.json),
        ]))
    }

    // MARK: Undo

    /// Several hook removals in one entry are one file write (`removeDeadHooks`): undo them together, not one by one.
    static func isHookRemovalBatch(_ ops: [JournalOp]) -> Bool {
        ops.count > 1 && ops.allSatisfy { $0.type == "hook-removed" }
    }

    /// Reverses one `hook-added` or `hook-removed` op. Returns a closure that puts things back, for `Journal.undo`'s all-or-nothing.
    static func undoHookOp(_ roots: Roots, _ op: JournalOp) throws -> () -> Void {
        try undoHooks(roots, [op])
    }

    /// Reverses a batch of `hook-removed` ops that share one file.
    static func undoHookRemovalBatch(_ roots: Roots, _ ops: [JournalOp]) throws -> () -> Void {
        try undoHooks(roots, ops)
    }

    private static func undoHooks(_ roots: Roots, _ ops: [JournalOp]) throws -> () -> Void {
        guard let first = ops.first, let file = first.json["file"]?.stringValue else { throw ReinsError("Unknown history entry.") }
        if let restore = first.json["restore"], restore["type"]?.stringValue == "file-edited" {
            do {
                return try Journal.undoFileEdit(roots, JournalOp(json: restore))
            } catch let error as ReinsError where error.status == 409 {
                // The file is not what that edit wrote any more (edited by hand, or by a later entry): reverse the hooks only.
            }
        }
        return try undoByHooks(roots, file: URL(fileURLWithPath: file), ops: ops)
    }

    private static func undoByHooks(_ roots: Roots, file: URL, ops: [JournalOp]) throws -> () -> Void {
        let realFile = Roots.resolvedPath(file.path)
        let before = FileManager.default.contents(atPath: realFile)
        var mode = 0o600
        var info = stat()
        if stat(realFile, &info) == 0 { mode = Int(info.st_mode & 0o777) }
        let edit = try FileEdit.applyJSON(roots, file: file) { doc in
            var doc = doc
            for op in ops {
                guard let event = op.json["event"]?.stringValue, let hook = op.json["hook"] else { throw ReinsError("Unknown history entry.") }
                let matcher = op.json["matcher"]?.stringValue
                switch op.type {
                case "hook-added":
                    doc = try HookEdit.removing(doc, file: file.path, event: event, matcher: matcher, command: hook["command"]?.stringValue ?? "").doc
                case "hook-removed":
                    doc = try HookEdit.adding(doc, file: file.path, event: event, matcher: matcher, hook: hook)
                default:
                    throw ReinsError("Unknown history entry.")
                }
            }
            return doc
        }
        guard edit != nil else { return {} }
        return {
            if let before { try? AtomicWrite.write(to: realFile, data: before, mode: mode) } else { unlink(realFile) }
        }
    }
}
