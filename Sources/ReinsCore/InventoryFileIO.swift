import Foundation

/// Bounded, never-throwing file reads for the inventory. A missing, unreadable or oversized file yields nil or a flag, never a crash.
enum InventoryFileIO {
    /// SKILL.md and agent files: only the head matters (frontmatter, description).
    static let maxTextBytes = 1 << 20
    /// Settings and hook files.
    static let maxJSONBytes = 16 << 20

    enum JSONFile {
        case missing
        /// Exists but cannot be opened or read (permission, a folder, I/O error).
        case unreadable
        case tooLarge
        case invalid
        case value(JSONValue)
    }

    /// Up to `maxBytes` of the file as text (invalid UTF-8 becomes U+FFFD, as Node does). Nil when it cannot be read.
    static func readText(_ url: URL, maxBytes: Int = maxTextBytes) -> String? {
        guard let data = readData(url, maxBytes: maxBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func readData(_ url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes) ?? Data()
    }

    static func readJSON(_ url: URL) -> JSONFile {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .missing
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxJSONBytes + 1) else { return .unreadable }
        if data.count > maxJSONBytes { return .tooLarge }
        guard let doc = try? OrderedJSON(text: String(decoding: data, as: UTF8.self)) else { return .invalid }
        return .value(doc.root)
    }

    /// Entry names of a folder, sorted. Empty when the folder is missing or cannot be read.
    static func list(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    /// The folder exists but cannot be listed (a denied folder reads as "not readable", never as empty).
    static func isUnreadableFolder(_ url: URL) -> Bool {
        guard isDirectory(url) else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) == nil
    }

    /// Follows symlinks.
    static func isDirectory(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue
    }

    /// Modification time in ms since 1970, following symlinks. Nil when the file cannot be statted.
    static func modifiedMs(_ url: URL) -> Double? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let t = modificationTime(info)
        return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// `path.join`: components appended with single slashes.
    static func join(_ base: String, _ parts: String...) -> String {
        parts.reduce(base) { ($0 as NSString).appendingPathComponent($1) }
    }

    /// `path.resolve` for an absolute path: `.` and `..` folded, no trailing slash. Symlinks are not followed.
    static func normalize(_ path: String) -> String {
        var stack: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = stack.popLast(); continue }
            stack.append(part)
        }
        return "/" + stack.joined(separator: "/")
    }

    /// The real path with symlinks followed, or the normalized path when it does not exist.
    static func realPath(_ path: String) -> String {
        let abs = normalize(path)
        guard let resolved = realpath(abs, nil) else { return abs }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
