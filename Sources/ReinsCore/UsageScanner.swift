import Foundation

/// Counts real usage from the session logs (Claude `projects/**.jsonl`, Codex `sessions/**.jsonl` and `.jsonl.zst`).
/// An actor, so a scan that reads gigabytes never runs on the main thread. Logs are only read; the one file written is the scan
/// cache under the REINS data root. Per-file results are cached by size and mtime and stamped with `scanVersion`.
public actor UsageScanner {
    /// Bump when the parser changes what a log file yields, so cached results are rescanned. Same number as core/usage.mjs.
    public static let scanVersion = 2
    /// Default cap: lines longer than this are skipped, not parsed.
    public static let maxLineBytes = 32 << 20
    /// The progress callback runs after this many files, and once at the end.
    public static let progressEvery = 20

    private let roots: Roots
    private let maxLineBytes: Int

    public init(roots: Roots, maxLineBytes: Int = UsageScanner.maxLineBytes) {
        self.roots = roots
        self.maxLineBytes = maxLineBytes
    }

    /// Scans every log. A log that cannot be read or decompressed is skipped (it still counts in `files`). Throws only
    /// `CancellationError`; cancelling leaves the cache as it was.
    /// - Parameter progress: called from the scanner's executor, never from the main thread.
    public func scan(progress: (@Sendable (UsageProgress) -> Void)? = nil) async throws -> UsageResult {
        let roots = self.roots
        let maxLineBytes = self.maxLineBytes
        let cache = UsageScanCache.load(roots)
        let targets: [(url: URL, cli: InventoryCLI)] =
            LogFiles.walk(roots.claude.logs).map { ($0, .claude) } + LogFiles.walk(roots.codex.logs).map { ($0, .codex) }
        var next: [String: CachedFile] = [:]
        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            if let entry = Self.entry(for: target.url, cli: target.cli, cached: cache[target.url.path], maxLineBytes: maxLineBytes) { next[target.url.path] = entry }
            let done = index + 1
            if done % Self.progressEvery == 0 {
                progress?(UsageProgress(done: done, total: targets.count))
                await Task.yield()
            }
        }
        progress?(UsageProgress(done: targets.count, total: targets.count))
        UsageScanCache.save(next, roots)
        return UsageScan.aggregate(next, fileCount: targets.count)
    }

    /// The cached record when the log is unchanged, otherwise a fresh parse. Nil when the log cannot be statted or read to the end.
    nonisolated static func entry(for url: URL, cli: InventoryCLI, cached: CachedFile?, maxLineBytes: Int) -> CachedFile? {
        guard case let (stamp, mtimeMs)? = LogFiles.stamp(of: url) else { return nil }
        if let cached, cached.stamp == stamp, cached.v == scanVersion { return cached }
        let fallbackDay = UsageScan.isoDay(Date(timeIntervalSince1970: TimeInterval(mtimeMs) / 1000))
        return scanFile(url, cli: cli, stamp: stamp, fallbackDay: fallbackDay, maxLineBytes: maxLineBytes)
    }

    /// Nil when the file cannot be read to the end (missing, a broken zstd frame).
    nonisolated static func scanFile(_ url: URL, cli: InventoryCLI, stamp: String, fallbackDay: String, maxLineBytes: Int) -> CachedFile? {
        var rec = FileRecord()
        var first: String?
        do {
            try LogFiles.forEachLine(at: url, maxLineBytes: maxLineBytes) { line in
                if first == nil { first = UsageScan.day(of: line) }
                switch cli {
                case .claude: UsageScan.claudeLine(line, into: &rec, fallbackDay: fallbackDay)
                case .codex: UsageScan.codexLine(line, into: &rec, fallbackDay: fallbackDay)
                }
            }
        } catch {
            return nil
        }
        return CachedFile(v: scanVersion, stamp: stamp, cli: cli, session: sessionId(url), first: first, rec: rec)
    }

    /// A subagent log belongs to the session of the folder that holds `subagents/`; any other log is its own session.
    nonisolated static func sessionId(_ url: URL) -> String {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        if let i = parts.lastIndex(of: "subagents"), i > 0 { return String(parts[i - 1]) }
        return LogFiles.baseName(url)
    }
}
