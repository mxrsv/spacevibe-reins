import Foundation

/// The result of one ledger scan.
public struct TokenScanResult: Equatable, Sendable {
    public var ledger: TokenLedger
    /// Where an unreadable ledger was moved before this scan started over from the logs present; nil when none was.
    public var movedAside: String?
    /// Why the ledger on disk was left alone and this scan's numbers were not saved; nil when it was saved.
    public var notSaved: String?
    /// Logs found.
    public var files: Int
    /// Logs that could not be read to the end this time (their earlier rows, if any, stay).
    public var unreadable: Int

    public init(ledger: TokenLedger, movedAside: String? = nil, notSaved: String? = nil, files: Int, unreadable: Int = 0) {
        self.ledger = ledger; self.movedAside = movedAside; self.notSaved = notSaved; self.files = files; self.unreadable = unreadable
    }
}

/// Folds token usage of every log into the ledger and saves it. An actor, so a first scan of gigabytes never runs on the
/// main thread. Logs are only read; the one file written is `token-ledger.json` under the REINS data root. A log whose
/// stamp and scan version match its entry is not read again.
public actor TokenLedgerScanner {
    private let roots: Roots
    private let maxLineBytes: Int
    private let scanVersion: Int

    /// - Parameter scanVersion: tests pass another value to act out a parser change; the app keeps the default.
    public init(roots: Roots, maxLineBytes: Int = UsageScanner.maxLineBytes, scanVersion: Int = TokenLedger.scanVersion) {
        self.roots = roots
        self.maxLineBytes = maxLineBytes
        self.scanVersion = scanVersion
    }

    /// Throws only `CancellationError`; cancelling leaves the file on disk as it was.
    /// - Parameter progress: called from the scanner's executor, never from the main thread.
    public func scan(now: Date = Date(), progress: (@Sendable (UsageProgress) -> Void)? = nil) async throws -> TokenScanResult {
        let loaded = TokenLedgerStore.load(roots, now: now)
        var files = loaded.ledger.files
        let targets: [(url: URL, cli: InventoryCLI, root: URL)] =
            LogFiles.walk(roots.claude.logs).map { ($0, .claude, roots.claude.logs) } + LogFiles.walk(roots.codex.logs).map { ($0, .codex, roots.codex.logs) }
        let memo = ProjectNameMemo()
        var unreadable = 0
        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            let key = TokenLedger.key(for: target.url, cli: target.cli, logRoot: target.root)
            if case let (stamp, mtimeMs)? = LogFiles.stamp(of: target.url) {
                let old = files[key]
                if old?.stamp != stamp || old?.v != scanVersion {
                    if let log = TokenFold.read(target.url, cli: target.cli, fallbackMs: Double(mtimeMs), maxLineBytes: maxLineBytes, memo: memo) {
                        files[key] = TokenLedger.merge(old: old, fresh: TokenLedgerFile(stamp: stamp, v: scanVersion, log: log))
                    } else {
                        unreadable += 1
                    }
                }
            } else {
                unreadable += 1
            }
            let done = index + 1
            if done % UsageScanner.progressEvery == 0 {
                progress?(UsageProgress(done: done, total: targets.count))
                await Task.yield()
            }
        }
        progress?(UsageProgress(done: targets.count, total: targets.count))
        let ledger = TokenLedger(files: files)
        var notSaved = loaded.keepOff
        if notSaved == nil, ledger != loaded.ledger || loaded.movedAside != nil || !InventoryFileIO.exists(TokenLedgerStore.url(roots).path) {
            do {
                try TokenLedgerStore.save(ledger, roots)
            } catch {
                notSaved = "The token history could not be saved (\(Self.reason(error))); these numbers last until the app quits."
            }
        }
        return TokenScanResult(ledger: ledger, movedAside: loaded.movedAside?.path, notSaved: notSaved, files: targets.count, unreadable: unreadable)
    }

    /// A fixed reason or an error code, never file content (S-R3).
    private static func reason(_ error: Error) -> String {
        if let reins = error as? ReinsError { return reins.message }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
