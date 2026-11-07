import Foundation

/// Explicit setup only. Merely opening Reins never changes Claude's status line.
public enum StatuslineSetup {
    public static func executable(_ roots: Roots) -> URL { roots.data.appendingPathComponent("bin/reins-statusline") }

    public static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Managed children must be real directories within the data root, including under SPACEVIBE_TEST.
    static func managedDirectory(_ roots: Roots, name: String) throws -> URL {
        let folder = roots.data.appendingPathComponent(name)
        try FileEdit.refuseRealHomeUnderTest(folder.path)
        var info = stat()
        if lstat(folder.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR {
            throw ReinsError("The collector directory is not a regular directory.", status: 409)
        }
        let expected = URL(fileURLWithPath: Roots.resolvedPath(roots.data.path)).appendingPathComponent(name).path
        guard Roots.resolvedPath(folder.path) == expected else {
            throw ReinsError("The collector directory leaves the Reins data folder.", status: 409)
        }
        return folder
    }

    /// Preserves every other settings member and delegates to the exact original shell command.
    /// The returned journal entry can be undone, with the existing conflict checks protecting later edits.
    public static func install(_ roots: Roots, binary: URL) throws -> JournalEntry? {
        let folder = try managedDirectory(roots, name: "bin")
        let destination = executable(roots)
        let prefix = "\(quote(destination.path)) --capture \(quote(roots.data.path)) \(quote(roots.claude.root.path)) "
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if binary.standardizedFileURL != destination.standardizedFileURL {
            try AtomicWrite.write(to: destination.path, data: Data(contentsOf: binary), mode: 0o700)
        }
        return try FileEdit.editJSON(roots, file: roots.claude.hookFile, label: "Enable Claude limit capture") { document in
            let original = document.root["statusLine"]
            if let original, original != .null {
                guard original.objectValue != nil, original["type"]?.stringValue == "command",
                      original["command"]?.stringValue != nil else {
                    throw ReinsError("The current status line is unsupported; nothing was replaced.", status: 409)
                }
            }
            let command = original?["command"]?.stringValue ?? ""
            if command.hasPrefix(prefix) { return document }
            let base = original == .null ? try document.removing(["statusLine"]) : document
            return try base.setting(["statusLine", "type"], to: "command")
                .setting(["statusLine", "command"], to: .string(prefix + quote(command)))
        }
    }
}
