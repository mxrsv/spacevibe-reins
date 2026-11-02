import Foundation

// The token history that outlives the logs (spec, Tab: Tokens; AC9). One entry per log, keyed so a rollout Codex
// compresses keeps its key; a changed log replaces its own entry, a missing log keeps it. The file holds names, dates
// and numbers only, never log text, and is readable by the owner only.

/// One log's entry: the stamp it was folded at, and what it yielded.
public struct TokenLedgerFile: Codable, Equatable, Sendable {
    /// `"<size>:<floor(mtime ms)>"` of the log when it was folded, the stamp the usage cache uses.
    public var stamp: String
    /// `TokenLedger.scanVersion` of the fold that wrote it.
    public var v: Int
    public var log: TokenLog

    public init(stamp: String, v: Int, log: TokenLog) {
        self.stamp = stamp; self.v = v; self.log = log
    }
}

public struct TokenLedger: Codable, Equatable, Sendable {
    /// Layout of the file. A ledger of another format is moved aside, never read as empty and never overwritten.
    public static let format = 1
    /// Bump when the fold changes what a log yields: logs still present are folded again, gone ones keep their rows.
    public static let scanVersion = 1

    public var format = TokenLedger.format
    /// Keyed by `<cli>/<path under that CLI's log folder, without .jsonl or .jsonl.zst>`.
    public var files: [String: TokenLedgerFile] = [:]

    public init(files: [String: TokenLedgerFile] = [:]) { self.files = files }

    /// The key of a log under `logRoot`: compressing `x.jsonl` to `x.jsonl.zst` keeps it, so a session is never counted twice.
    static func key(for url: URL, cli: InventoryCLI, logRoot: URL) -> String {
        let root = logRoot.path.hasSuffix("/") ? logRoot.path : logRoot.path + "/"
        let dir = url.deletingLastPathComponent().path
        let relativeDir = dir.hasPrefix(root) ? String(dir.dropFirst(root.count)) : (dir + "/" == root ? "" : dir)
        let name = LogFiles.baseName(url)
        return "\(cli.rawValue)/" + (relativeDir.isEmpty ? name : "\(relativeDir)/\(name)")
    }

    /// The entry a fresh fold of a log leaves. Same scan version: each hour and model keeps the larger of the old and the
    /// new counts, so a rescan never lowers a past day (a log only grows; a rewritten one cannot take history away).
    /// Another version: the fresh fold replaces the entry, because the counting itself changed.
    static func merge(old: TokenLedgerFile?, fresh: TokenLedgerFile) -> TokenLedgerFile {
        guard let old, old.v == fresh.v else { return fresh }
        struct Key: Hashable { var hour: Int; var model: String }
        var rows: [Key: TokenCounts] = [:]
        for row in old.log.rows { rows[Key(hour: row.hour, model: row.model)] = row.counts }
        for row in fresh.log.rows {
            let key = Key(hour: row.hour, model: row.model)
            rows[key] = rows[key].map { $0.atLeast(row.counts) } ?? row.counts
        }
        var log = fresh.log
        log.project = fresh.log.project ?? old.log.project
        log.rows = rows.map { TokenRow(hour: $0.key.hour, model: $0.key.model, counts: $0.value) }.sorted { ($0.hour, $0.model) < ($1.hour, $1.model) }
        return TokenLedgerFile(stamp: fresh.stamp, v: fresh.v, log: log)
    }

    /// Every row with the log it came from.
    public var entries: [(cli: InventoryCLI, session: String, project: String?, row: TokenRow)] {
        files.values.flatMap { file in file.log.rows.map { (file.log.cli, file.log.session, file.log.project, $0) } }
    }
}

/// `token-ledger.json` under the REINS data root.
enum TokenLedgerStore {
    static let fileName = "token-ledger.json"
    static let maxBytes = 512 << 20

    static func url(_ roots: Roots) -> URL { roots.data.appendingPathComponent(fileName) }

    struct Loaded {
        var ledger: TokenLedger
        /// Where an unreadable ledger was moved; nil when there was none.
        var movedAside: URL?
        /// Set when the file on disk must not be replaced (it could not be read or moved aside). The scan still runs.
        var keepOff: String?
    }

    /// A missing ledger is an empty one. One that cannot be decoded, or has another format, is moved aside and reported,
    /// because it can hold days no log has any more; one that cannot even be opened is left alone and never overwritten.
    static func load(_ roots: Roots, now: Date = Date()) -> Loaded {
        let target = url(roots)
        var info = stat()
        if stat(target.path, &info) != 0, errno == ENOENT || errno == ENOTDIR { return Loaded(ledger: TokenLedger()) }
        let leftAlone = Loaded(ledger: TokenLedger(), keepOff: "The token history at \(target.path) cannot be read, so it was left as it is.")
        guard info.st_mode & S_IFMT == S_IFREG, let handle = try? FileHandle(forReadingFrom: target) else { return leftAlone }
        let data = try? handle.read(upToCount: maxBytes + 1)
        try? handle.close()
        if let data, data.count <= maxBytes, let ledger = try? JSONDecoder().decode(TokenLedger.self, from: data), ledger.format == TokenLedger.format {
            return Loaded(ledger: ledger)
        }
        do {
            return Loaded(ledger: TokenLedger(), movedAside: try moveAside(target, now: now))
        } catch {
            return Loaded(ledger: TokenLedger(), keepOff: "The token history at \(target.path) is unreadable and could not be moved aside, so it was left as it is.")
        }
    }

    /// `token-ledger.unreadable-<UTC time>.json` next to the ledger, never over an existing file.
    static func moveAside(_ target: URL, now: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let base = "token-ledger.unreadable-\(formatter.string(from: now))"
        let dir = target.deletingLastPathComponent()
        let fm = FileManager.default
        for n in 0..<100 {
            let candidate = dir.appendingPathComponent(n == 0 ? "\(base).json" : "\(base)-\(n).json")
            if fm.fileExists(atPath: candidate.path) { continue }
            try fm.moveItem(at: target, to: candidate)
            return candidate
        }
        throw ReinsError("No free name to move \(target.path) aside.", status: 500)
    }

    /// Atomic, mode 0600, in a data folder of mode 0700 when it has to be made.
    static func save(_ ledger: TokenLedger, _ roots: Roots) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: roots.data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ledger)
        try AtomicWrite.write(to: Roots.resolvedPath(url(roots).path), data: data, mode: 0o600)
    }
}
