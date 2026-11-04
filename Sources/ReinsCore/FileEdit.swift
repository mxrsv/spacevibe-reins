import Foundation

/// The one way Reins changes a config file: atomic, undoable, content-safe. Same job as `editFile` in core/mutate.mjs,
/// plus a JSON layer that does what `parseConfig` and `serialize` do in core/rules.mjs.
///
/// - The previous bytes are copied to the app trash first; the returned op lets `Journal.undo` put back exactly those
///   bytes (only if the file still holds what this edit wrote) or move a file this edit created to the trash.
/// - A symlinked file stays a symlink: the target is written.
/// - The mode is kept; a new file gets 0600.
/// - The temp file is re-read and validated before the rename, so a bad write never replaces the file.
/// - Errors never quote file content.
public enum FileEdit {
    /// The end of the message for a file another process wrote between Reins reading it and replacing it.
    static let changedWhileEditing = " changed while Reins was editing it, so it was left alone. Try again."

    static func isChangedWhileEditing(_ error: Error) -> Bool {
        (error as? ReinsError).map { $0.status == 409 && $0.message.hasSuffix(changedWhileEditing) } ?? false
    }

    // MARK: Text

    /// Edits a text file. `change` gets the current text (nil when the file does not exist) and returns the next text;
    /// returning nil or the same bytes is a no-op (result nil, no write). `validate` gets the text read back from the
    /// temp file; throwing aborts before the rename.
    /// - Returns: the op to put in a journal entry, or nil for a no-op.
    public static func apply(
        _ roots: Roots,
        file: URL,
        validate: ((String) throws -> Void)? = nil,
        change: (String?) throws -> String?
    ) throws -> JournalOp? {
        try WriteLock.run { try applyLocked(roots, file: file, validate: validate, change: change) }
    }

    private static func applyLocked(
        _ roots: Roots,
        file: URL,
        validate: ((String) throws -> Void)?,
        change: (String?) throws -> String?
    ) throws -> JournalOp? {
        try refuseRealHomeUnderTest(file.path)
        let target = try resolveTarget(file.path)
        let before: Data?
        if target.existed {
            guard let bytes = FileManager.default.contents(atPath: target.real) else {
                throw ReinsError("Could not read \(target.real). Nothing was changed.", status: 409)
            }
            before = bytes
        } else {
            before = nil
        }
        let beforeText: String?
        if let before {
            guard let text = String(data: before, encoding: .utf8) else {
                throw ReinsError("\(target.real) is not UTF-8 text. Nothing was changed.", status: 409)
            }
            beforeText = text
        } else {
            beforeText = nil
        }

        guard let nextText = try change(beforeText) else { return nil }
        let next = Data(nextText.utf8)
        // Compare bytes: Swift String equality treats canonically equivalent text as equal.
        if next == before { return nil }

        var backup: URL?
        if target.existed, let before {
            let slot = try Trash.slot(roots, name: (target.real as NSString).lastPathComponent)
            try AtomicWrite.write(to: slot.path, data: before, mode: 0o600)
            backup = slot
        } else {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: target.real).deletingLastPathComponent(), withIntermediateDirectories: true
                )
            } catch {
                throw ReinsError("Could not create the folder for \(target.real). Nothing was changed.", status: 500)
            }
        }
        do {
            try AtomicWrite.write(to: target.real, data: next, mode: target.mode, validate: { written in
                guard let text = String(data: written, encoding: .utf8) else {
                    throw ReinsError("The new \(target.real) would not be valid text. Nothing was changed.", status: 409)
                }
                try validate?(text)
            }, beforeRename: {
                // Another process (a CLI, a hand edit) may have written since the read above; never overwrite that.
                guard FileManager.default.contents(atPath: target.real) == before else {
                    throw ReinsError("\(target.real)\(changedWhileEditing)", status: 409)
                }
            })
        } catch {
            // The old file is untouched; do not leave an unused backup behind.
            if let backup { try? FileManager.default.removeItem(at: backup.deletingLastPathComponent()) }
            throw error
        }
        return .fileEdited(file: target.real, existed: target.existed, backup: backup?.path, after: ContentHash.sha256Hex(next))
    }

    /// `apply` plus a journal entry named `label`. Nil when nothing changed (no entry is recorded).
    public static func edit(
        _ roots: Roots,
        file: URL,
        label: String,
        validate: ((String) throws -> Void)? = nil,
        change: (String?) throws -> String?
    ) throws -> JournalEntry? {
        try WriteLock.run {
            try Journal.prepareMutation(roots)
            guard let op = try apply(roots, file: file, validate: validate, change: change) else { return nil }
            return try Journal.recordMutation(roots, label: label, ops: [op])
        }
    }

    // MARK: JSON

    /// Edits a JSON file whose top level is an object. A missing or blank file counts as `{}`. `change` gets the parsed
    /// document and returns an edited one (use the `OrderedJSON` edit methods, which keep key order, indent, line
    /// endings and every untouched byte). Invalid JSON or a non-object file is refused with a 409 that never quotes
    /// content. `validate` also runs on the document read back from the temp file.
    /// - Returns: the op to put in a journal entry, or nil for a no-op.
    public static func applyJSON(
        _ roots: Roots,
        file: URL,
        validate: ((OrderedJSON) throws -> Void)? = nil,
        change: (OrderedJSON) throws -> OrderedJSON
    ) throws -> JournalOp? {
        try apply(
            roots,
            file: file,
            validate: { text in try validate?(parseObject(text, file: file)) },
            change: { text in
                let blank = text.map { $0.allSatisfy(\.isWhitespace) } ?? true
                // A new file starts from a one-line object with a final newline, like a file written by hand.
                let start = blank ? try OrderedJSON(text: "{}\n") : try parseObject(text ?? "", file: file)
                let next = try change(start)
                return blank && next.bytes == start.bytes ? text : next.text
            }
        )
    }

    /// `applyJSON` plus a journal entry named `label`. Nil when nothing changed.
    public static func editJSON(
        _ roots: Roots,
        file: URL,
        label: String,
        validate: ((OrderedJSON) throws -> Void)? = nil,
        change: (OrderedJSON) throws -> OrderedJSON
    ) throws -> JournalEntry? {
        try WriteLock.run {
            try Journal.prepareMutation(roots)
            guard let op = try applyJSON(roots, file: file, validate: validate, change: change) else { return nil }
            return try Journal.recordMutation(roots, label: label, ops: [op])
        }
    }

    /// Parse errors are replaced by a fixed sentence: the parser's position and the text around it can hold a secret.
    static func parseObject(_ text: String, file: URL) throws -> OrderedJSON {
        let document: OrderedJSON
        do { document = try OrderedJSON(text: text) } catch {
            throw ReinsError("\(file.path) is not valid JSON. Nothing was changed.", status: 409)
        }
        guard document.root.objectValue != nil else {
            throw ReinsError("\(file.path) does not hold a JSON object. Nothing was changed.", status: 409)
        }
        return document
    }

    // MARK: Target

    private struct Target {
        let real: String
        let existed: Bool
        let mode: Int
    }

    /// Follows links so the file a link points at is the one written. A link to nothing is refused (the Node core would
    /// replace the link with a regular file, which loses the user's link).
    private static func resolveTarget(_ path: String) throws -> Target {
        var linkInfo = stat()
        var info = stat()
        let linkExists = lstat(path, &linkInfo) == 0
        guard stat(path, &info) == 0 else {
            if linkExists { throw ReinsError("\(path) is a link to a file that does not exist, so it was left alone.", status: 409) }
            return Target(real: path, existed: false, mode: 0o600)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw ReinsError("\(path) is not a regular file.", status: 409) }
        return Target(real: Roots.resolvedPath(path), existed: true, mode: Int(info.st_mode & 0o777))
    }

    /// Defense in depth for tests: under REINS_TEST=1 a path under the real home is never written, whatever the roots say.
    private static func refuseRealHomeUnderTest(_ path: String) throws {
        guard ProcessInfo.processInfo.environment["REINS_TEST"] == "1" else { return }
        let home = Roots.resolvedPath(Roots.realHomeDirectory())
        let resolved = Roots.resolvedPath(path)
        if resolved == home || resolved.hasPrefix(home.hasSuffix("/") ? home : home + "/") {
            throw ReinsError("REINS_TEST=1: refusing to write under the real home.", status: 500)
        }
    }
}
