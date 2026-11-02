import Foundation

/// The app's own trash under the data root. Removed files and the old bytes of edited files go here, never into the
/// journal, so the journal stays small and never holds file content. Layout as in core/mutate.mjs:
/// `<data>/trash/<epoch ms>-<8 hex>/<name>`, folders 0700.
public enum Trash {
    /// True when anything sits at the path, including a link whose target is gone.
    static func pathExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    static func ensureDataFolders(_ roots: Roots) throws {
        do {
            try FileManager.default.createDirectory(
                at: roots.data.appendingPathComponent("trash", isDirectory: true),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ReinsError("Could not create the Reins data folder \(roots.data.path).", status: 500)
        }
    }

    /// A fresh trash folder; returns the path where `name` goes inside it.
    static func slot(_ roots: Roots, name: String) throws -> URL {
        let folder = roots.data
            .appendingPathComponent("trash", isDirectory: true)
            .appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.lowercased().prefix(8))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw ReinsError("Could not create the Reins trash folder.", status: 500)
        }
        return folder.appendingPathComponent(name)
    }

    /// Moves a file or folder into the trash. The returned `moved` op lets undo move it back.
    public static func moveToTrash(_ roots: Roots, path: String) throws -> JournalOp {
        let destination = try slot(roots, name: (path as NSString).lastPathComponent)
        try move(from: path, to: destination.path)
        return .moved(from: path, to: destination.path)
    }

    /// Removing a link never touches what it points at: the link is deleted and its target text kept for undo.
    /// Anything else goes to the trash.
    public static func remove(_ roots: Roots, path: String) throws -> JournalOp {
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            guard unlink(path) == 0 else { throw ReinsError("Could not remove \(path) (\(AtomicWrite.errnoText())).", status: 500) }
            return .linkRemoved(path: path, target: target)
        }
        return try moveToTrash(roots, path: path)
    }

    /// Fails instead of replacing when the destination exists.
    static func move(from: String, to: String) throws {
        do {
            try FileManager.default.moveItem(atPath: from, toPath: to)
        } catch {
            throw ReinsError("Could not move \(from) (\((error as NSError).localizedFailureReason ?? "the move failed")).", status: 500)
        }
    }
}
