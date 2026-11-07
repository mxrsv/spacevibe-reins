import Foundation

/// One scanned log as the cache keeps it. The layout matches Node usage (git b58269d), so a cache written by either engine is readable by the other.
struct CachedFile: Codable, Equatable, Sendable {
    /// `UsageScanner.scanVersion` when it was parsed.
    var v: Int
    /// `"<size>:<floor(mtime ms)>"`: a changed log is parsed again.
    var stamp: String
    var cli: InventoryCLI
    var session: String
    var first: String?
    var rec: FileRecord

    /// Modification time of the log in ms, from the stamp.
    var mtimeMs: Int64 { Int64(stamp.split(separator: ":").last ?? "0") ?? 0 }
}

/// `usage-cache.json` under the REINS data root: names, days, hook hashes and durations, plus the path and session id of each log.
enum UsageScanCache {
    static let fileName = "usage-cache.json"

    private struct Lossy: Decodable {
        let value: CachedFile?
        init(from decoder: Decoder) throws { value = try? CachedFile(from: decoder) }
    }

    static func url(_ roots: Roots) -> URL { roots.data.appendingPathComponent(fileName) }

    /// An unreadable, oversized or corrupt cache is an empty one; a single bad entry drops only itself.
    static func load(_ roots: Roots) -> [String: CachedFile] {
        guard let data = InventoryFileIO.readData(url(roots), maxBytes: 512 << 20),
              let entries = try? JSONDecoder().decode([String: Lossy].self, from: data) else { return [:] }
        return entries.compactMapValues(\.value)
    }

    /// Best effort: a cache that cannot be written only costs the next scan its speed.
    static func save(_ cache: [String: CachedFile], _ roots: Roots) {
        let fm = FileManager.default
        let target = url(roots)
        guard (try? fm.createDirectory(at: roots.data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil,
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: target, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}
