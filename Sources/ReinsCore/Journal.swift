import Foundation

/// One recorded change. Held as raw JSON so a journal written by the Node core (including op kinds this version cannot
/// undo, such as `hook-added`) is read and written back without losing a field.
///
/// Op kinds:
/// - `file-edited` `{file, existed, backup, after}`: `file` is a real path, `backup` the old bytes in the trash (null when the edit created the file), `after` the SHA-256 hex of the bytes written.
/// - `created` `{path}`: undo moves it to the trash.
/// - `moved` `{from, to}`: `to` is in the trash; undo moves it back.
/// - `link-removed` `{path, target}`: undo makes the link again.
public struct JournalOp: Equatable, Sendable {
    public let json: JSONValue

    public init(json: JSONValue) { self.json = json }

    public var type: String { json["type"]?.stringValue ?? "" }

    public static func fileEdited(file: String, existed: Bool, backup: String?, after: String) -> JournalOp {
        JournalOp(json: .object([
            JSONMember("type", "file-edited"), JSONMember("file", .string(file)), JSONMember("existed", .bool(existed)),
            JSONMember("backup", backup.map(JSONValue.string) ?? .null), JSONMember("after", .string(after)),
        ]))
    }

    public static func created(path: String) -> JournalOp {
        JournalOp(json: .object([JSONMember("type", "created"), JSONMember("path", .string(path))]))
    }

    public static func moved(from: String, to: String) -> JournalOp {
        JournalOp(json: .object([JSONMember("type", "moved"), JSONMember("from", .string(from)), JSONMember("to", .string(to))]))
    }

    public static func linkRemoved(path: String, target: String) -> JournalOp {
        JournalOp(json: .object([JSONMember("type", "link-removed"), JSONMember("path", .string(path)), JSONMember("target", .string(target))]))
    }
}

public struct JournalEntry: Equatable, Sendable {
    public let id: String
    /// ISO 8601 UTC with milliseconds, like `Date.toISOString()`.
    public let at: String
    public let label: String
    public let undone: Bool
    public let ops: [JournalOp]

    var json: JSONValue {
        var members: [JSONMember] = [
            JSONMember("id", .string(id)), JSONMember("at", .string(at)), JSONMember("label", .string(label)),
            JSONMember("ops", .array(ops.map(\.json))),
        ]
        if undone { members.append(JSONMember("undone", .bool(true))) }
        return .object(members)
    }

    init(id: String, at: String, label: String, undone: Bool, ops: [JournalOp]) {
        self.id = id; self.at = at; self.label = label; self.undone = undone; self.ops = ops
    }

    /// Nil when the value is not an entry (no string id); such a value is dropped on the next write.
    init?(json: JSONValue) {
        guard let id = json["id"]?.stringValue else { return nil }
        self.init(
            id: id,
            at: json["at"]?.stringValue ?? "",
            label: json["label"]?.stringValue ?? "",
            undone: json["undone"]?.boolValue ?? false,
            ops: (json["ops"]?.arrayValue ?? []).map(JournalOp.init(json:))
        )
    }

    func markedUndone() -> JournalEntry {
        JournalEntry(id: id, at: at, label: label, undone: true, ops: ops)
    }
}

/// What `history` returns: the summary shape of `history` in core/mutate.mjs.
public struct HistoryItem: Equatable, Sendable {
    public let id: String
    public let at: String
    public let label: String
    public let undone: Bool
    public let count: Int
}

/// The undo journal: `<data>/journal.json`, a JSON array, newest first, at most 200 entries. Same file and entry shape
/// as the Node core, so either side can read what the other wrote.
///
/// Labels are written verbatim: callers pass a sentence about what changed (a rule name, an item name), never file content.
public enum Journal {
    public static let limit = 200
    static let fileName = "journal.json"
    /// Op kinds `undo` can reverse. The two hook kinds are written by Mutate (see MutateHooks.swift for how they are undone).
    static let undoable: Set<String> = ["file-edited", "created", "moved", "link-removed", "hook-added", "hook-removed"]

    static func journalPath(_ roots: Roots) -> String { roots.data.appendingPathComponent(fileName).path }

    /// All entries, newest first. A missing or unreadable journal reads as empty, as in the Node core.
    public static func entries(_ roots: Roots) -> [JournalEntry] {
        guard let data = FileManager.default.contents(atPath: journalPath(roots)),
              let document = try? OrderedJSON(data: data),
              let items = document.root.arrayValue else { return [] }
        return items.compactMap(JournalEntry.init(json:))
    }

    public static func history(_ roots: Roots) -> [HistoryItem] {
        entries(roots).map { HistoryItem(id: $0.id, at: $0.at, label: $0.label, undone: $0.undone, count: $0.ops.count) }
    }

    /// Adds an entry at the front and returns it.
    @discardableResult
    public static func record(_ roots: Roots, label: String, ops: [JournalOp]) throws -> JournalEntry {
        let entry = JournalEntry(id: UUID().uuidString.lowercased(), at: timestamp(), label: label, undone: false, ops: ops)
        try WriteLock.run { try write(roots, [entry] + entries(roots)) }
        return entry
    }

    /// Reverses an entry's ops, last first, and marks it undone; returns its label.
    /// All or nothing: if one op refuses or fails, the ones already reversed are put back and the entry stays undoable.
    public static func undo(_ roots: Roots, id: String) throws -> String {
        try WriteLock.run { try undoLocked(roots, id: id) }
    }

    private static func undoLocked(_ roots: Roots, id: String) throws -> String {
        let all = entries(roots)
        guard let entry = all.first(where: { $0.id == id }) else { throw ReinsError("That history entry is gone.", status: 404) }
        guard !entry.undone else { throw ReinsError("This was already undone.", status: 409) }
        if entry.ops.contains(where: { !undoable.contains($0.type) }) {
            throw ReinsError("This history entry has changes this version cannot undo. Nothing was changed.", status: 400)
        }
        var rollbacks: [() -> Void] = []
        do {
            if Mutate.isHookRemovalBatch(entry.ops) {
                rollbacks.append(try Mutate.undoHookRemovalBatch(roots, entry.ops))
            } else {
                for op in entry.ops.reversed() { rollbacks.append(try undoOp(roots, op)) }
            }
            try write(roots, all.map { $0.id == id ? $0.markedUndone() : $0 })
        } catch {
            for rollback in rollbacks.reversed() { rollback() }
            throw error
        }
        return entry.label
    }

    // MARK: Writing

    private static func write(_ roots: Roots, _ entries: [JournalEntry]) throws {
        try Trash.ensureDataFolders(roots)
        let json = JSONValue.array(entries.prefix(limit).map(\.json))
        // Two-space JSON.stringify layout without a trailing newline, as the Node core writes it.
        let text = try OrderedJSON.pretty(json, trailingNewline: false)
        try AtomicWrite.write(to: journalPath(roots), data: Data(text.utf8), mode: 0o600)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    // MARK: Undoing one op

    private static func field(_ op: JournalOp, _ key: String) throws -> String {
        guard let value = op.json[key]?.stringValue else { throw ReinsError("Unknown history entry.") }
        return value
    }

    /// Reverses one op and returns a closure that puts things back (best effort), used when a later op refuses.
    private static func undoOp(_ roots: Roots, _ op: JournalOp) throws -> () -> Void {
        switch op.type {
        case "created":
            let path = try field(op, "path")
            guard Trash.pathExists(path) else { return {} }
            let moved = try Trash.moveToTrash(roots, path: path)
            return { try? Trash.move(from: moved.json["to"]?.stringValue ?? "", to: path) }

        case "moved":
            let from = try field(op, "from"), to = try field(op, "to")
            guard !Trash.pathExists(from) else { throw ReinsError("\(from) already exists again, so it was left alone.", status: 409) }
            guard Trash.pathExists(to) else { throw ReinsError("The saved copy of \(from) is gone, so it was left alone.", status: 409) }
            try Trash.move(from: to, to: from)
            return { try? Trash.move(from: from, to: to) }

        case "link-removed":
            let path = try field(op, "path"), target = try field(op, "target")
            guard !Trash.pathExists(path) else { throw ReinsError("\(path) already exists again, so it was left alone.", status: 409) }
            do { try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target) } catch {
                throw ReinsError("Could not restore the link at \(path).", status: 500)
            }
            return { _ = unlink(path) }

        case "file-edited":
            return try undoFileEdit(roots, op)

        case "hook-added", "hook-removed":
            return try Mutate.undoHookOp(roots, op)

        default:
            throw ReinsError("Unknown history entry.")
        }
    }

    static func undoFileEdit(_ roots: Roots, _ op: JournalOp) throws -> () -> Void {
        let file = try field(op, "file"), after = try field(op, "after")
        let existed = op.json["existed"]?.boolValue ?? false
        // Only undo what this edit wrote: a hand edit made since then is not ours to overwrite.
        guard let now = FileManager.default.contents(atPath: file), ContentHash.sha256Hex(now) == after else {
            throw ReinsError("\(file) changed since this edit, so it was left alone.", status: 409)
        }
        guard existed else {
            let moved = try Trash.moveToTrash(roots, path: file)
            return { try? Trash.move(from: moved.json["to"]?.stringValue ?? "", to: file) }
        }
        guard let backup = op.json["backup"]?.stringValue, let old = FileManager.default.contents(atPath: backup) else {
            throw ReinsError("The saved copy of \(file) is gone, so it was left alone.", status: 409)
        }
        var info = stat()
        let mode = stat(file, &info) == 0 ? Int(info.st_mode & 0o777) : 0o600
        try AtomicWrite.write(to: file, data: old, mode: mode, beforeRename: {
            guard FileManager.default.contents(atPath: file) == now else {
                throw ReinsError("\(file) changed while Reins was undoing, so it was left alone.", status: 409)
            }
        })
        return { try? AtomicWrite.write(to: file, data: now, mode: mode) }
    }
}
