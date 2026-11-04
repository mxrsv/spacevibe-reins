import Foundation

/// One file in a save of the Agents page: what its text becomes. `change` gets the current text (nil when the file does
/// not exist) and returns the next text, or nil to leave it alone; `validate` runs on the text read back before the rename.
public struct AgentFileChange: Sendable {
    public let file: URL
    public let change: @Sendable (String?) throws -> String?
    public let validate: (@Sendable (String) throws -> Void)?
    /// When another process writes the file between the read and the rename: how many times to read it again and apply
    /// the same change, and what to say when that fails too. Zero keeps `FileEdit`'s own refusal.
    public let retries: Int
    public let conflictMessage: String?

    public init(file: URL, validate: (@Sendable (String) throws -> Void)? = nil, retries: Int = 0, conflictMessage: String? = nil,
                change: @escaping @Sendable (String?) throws -> String?) {
        self.file = file
        self.change = change
        self.validate = validate
        self.retries = retries
        self.conflictMessage = conflictMessage
    }
}

/// Every save of the Agents page (spec, Writes: Every save; plan, "Write approach and recovery"): one journal entry with a
/// `file-edited` op per file. Each file is replaced atomically through `FileEdit.apply`, which copies the old bytes to the
/// trash first (mode 0600) and refuses a file that changed since it was read. A failure partway through rolls back the
/// files already written, so a save lands whole or not at all. Undo is `Journal.undo` with the entry's id.
public enum AgentSave {
    /// Where an organisation's managed Claude Code settings live on macOS. Shown, never written.
    public static let managedFolder = "/Library/Application Support/ClaudeCode"

    static let managedRefusal = ReinsError("Managed settings are set by your organisation. Reins shows them and never writes them.", status: 403)

    /// - Returns: the journal entry, or nil when no file changed (nothing is recorded).
    @discardableResult
    public static func save(_ roots: Roots, label: String, changes: [AgentFileChange]) throws -> JournalEntry? {
        for change in changes where isManaged(change.file) { throw managedRefusal }
        return try WriteLock.run {
            try Journal.prepareMutation(roots)
            var ops: [JournalOp] = []
            do {
                for change in changes {
                    if let op = try apply(roots, change) { ops.append(op) }
                }
            } catch {
                if !ops.isEmpty { try Journal.rollbackMutation(roots, ops: ops) }
                throw error
            }
            guard !ops.isEmpty else { return nil }
            return try Journal.recordMutation(roots, label: label, ops: ops)
        }
    }

    /// One file, read again and changed again when another process wrote it meanwhile, up to `retries` times.
    private static func apply(_ roots: Roots, _ change: AgentFileChange) throws -> JournalOp? {
        var attempt = 0
        while true {
            do {
                return try FileEdit.apply(roots, file: change.file, validate: change.validate, change: change.change)
            } catch let error where FileEdit.isChangedWhileEditing(error) {
                guard attempt < change.retries else {
                    if let message = change.conflictMessage { throw ReinsError(message, status: 409) }
                    throw error
                }
                attempt += 1
            }
        }
    }

    public static func isManaged(_ file: URL) -> Bool {
        let path = file.standardizedFileURL.path
        return path == managedFolder || path.hasPrefix(managedFolder + "/")
    }

    /// A JSON settings file edited through `OrderedJSON` (a missing or blank file starts as `{}`), refusing a file that is
    /// not a JSON object without quoting it.
    public static func jsonChange(_ file: URL, _ edit: @escaping @Sendable (OrderedJSON) throws -> OrderedJSON) -> AgentFileChange {
        AgentFileChange(file: file, validate: { text in _ = try FileEdit.parseObject(text, file: file) }) { text in
            let blank = text.map { $0.allSatisfy(\.isWhitespace) } ?? true
            let start = blank ? try OrderedJSON(text: "{}\n") : try FileEdit.parseObject(text ?? "", file: file)
            let next = try edit(start)
            return blank && next.bytes == start.bytes ? text : next.text
        }
    }

    /// The Advanced editor's save: the masked text the user edited, with each untouched secret put back, as long as the
    /// file still holds what was masked. `check` validates the result's syntax (JSON or TOML).
    public static func advancedChange(_ file: URL, masked: MaskedText, edited: String, check: @escaping @Sendable (String) throws -> Void) -> AgentFileChange {
        AgentFileChange(file: file, validate: check) { current in
            guard ContentHash.sha256Hex(Data((current ?? "").utf8)) == masked.originalDigest else {
                throw ReinsError("\(file.lastPathComponent) changed since you opened it. Nothing was saved; open it again.", status: 409)
            }
            let text = try masked.unmask(edited)
            try check(text)
            return text
        }
    }
}
