import Foundation
import Observation
import ReinsCore

/// The Tokens screen's state: the ledger scan, the query built from it, and the board's choices (period, measure, the
/// picked bucket, model or project, open rows).
///
/// The scan runs in `TokenLedgerScanner`, an actor, and the query is built off the main actor too, so a first scan of a
/// long history never blocks the window. A scan starts when the tab first shows and again when it shows after
/// `staleAfter`; the ledger keeps a stamp per log, so a repeat reads only logs that changed.
@MainActor
@Observable
final class TokensModel {
    static let staleAfter: TimeInterval = 60

    let env: AppEnvironment
    let timeZone: TimeZone

    private(set) var result: TokenScanResult?
    private(set) var query: TokenQuery?
    /// Logs folded so far in a running scan.
    private(set) var progress: UsageProgress?
    private(set) var isScanning = false
    /// A scan that could not run. Cleared by the next one that does.
    private(set) var failure: String?
    private(set) var scannedAt: Date?

    var period: TokenPeriod = .day {
        didSet {
            guard period != oldValue else { return }
            selectedID = nil
            expanded = []
        }
    }
    var measure: TokenMeasure = .cost
    /// The picked bucket, by `TokenBucket.id`.
    var selectedID: Int?
    var pick: TokenPick?
    /// Bucket rows open to their four kinds.
    var expanded: Set<Int> = []
    /// Lists unfolded past their first rows: "claude", "codex", "projects".
    var unfolded: Set<String> = []
    var isPriceTableOpen = false

    @ObservationIgnored private let now: () -> Date

    init(env: AppEnvironment, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.env = env
        self.timeZone = timeZone
        self.now = now
    }

    var board: TokensBoard? {
        query.map { TokensBoard(query: $0, period: period, measure: measure, selectedID: selectedID, pick: pick) }
    }

    var isLoading: Bool { query == nil && failure == nil }
    var hasScope: Bool { selectedID != nil || pick != nil }
    /// Nothing counted and no log found: the empty state.
    var hasNoLogs: Bool { result.map { $0.files == 0 && $0.ledger.files.isEmpty } ?? false }

    // MARK: Scanning

    /// One scan, unless one is running. Never throws: what it could not do is in `failure` or the result's notes.
    func scan() async {
        guard !isScanning else { return }
        guard let roots = env.roots else {
            failure = env.startupProblem ?? "The config folders could not be resolved."
            return
        }
        isScanning = true
        progress = nil
        defer { isScanning = false }
        let when = now()
        let zone = timeZone
        do {
            let fresh = try await TokenLedgerScanner(roots: roots).scan(now: when) { [weak self] step in
                Task { @MainActor in self?.progress = step }
            }
            let built = await Task.detached(priority: .userInitiated) { TokenQuery(ledger: fresh.ledger, now: when, timeZone: zone) }.value
            result = fresh
            query = built
            scannedAt = when
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            failure = "The token history could not be read."
        }
    }

    /// Scans when nothing is shown yet or the last scan is older than `staleAfter`.
    func refreshIfStale() async {
        if let scannedAt, now().timeIntervalSince(scannedAt) < Self.staleAfter, query != nil { return }
        await scan()
    }

    func rescan() { Task { await scan() } }

    // MARK: Choices

    /// Picks a bucket; picking the picked one again clears it.
    func select(_ id: Int) { selectedID = selectedID == id ? nil : id }

    func toggleExpanded(_ id: Int) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Picks a model or project; picking it again clears it.
    func toggle(_ choice: TokenPick) { pick = pick == choice ? nil : choice }

    func toggleUnfolded(_ list: String) {
        if unfolded.contains(list) { unfolded.remove(list) } else { unfolded.insert(list) }
    }

    func clearScope() {
        selectedID = nil
        pick = nil
    }

    /// `←` (-1, older) and `→` (+1, newer) move the picked bucket along the series. With none picked, `→` starts at the
    /// oldest bucket and `←` at the newest, as the columns read left to right.
    @discardableResult
    func move(_ step: Int) -> Int? {
        guard let columns = board?.columns, !columns.isEmpty else { return nil }
        let ids = columns.map(\.id)
        let next: Int
        if let current = selectedID, let index = ids.firstIndex(of: current) {
            next = ids[min(max(index + step, 0), ids.count - 1)]
        } else {
            next = step > 0 ? ids[0] : ids[ids.count - 1]
        }
        selectedID = next
        return next
    }

    /// `↵` opens or closes the picked bucket's four kinds. False when no bucket is picked.
    func openSelected() -> Bool {
        guard let id = selectedID else { return false }
        toggleExpanded(id)
        return true
    }

    /// `Esc` closes the price table first, then clears the scope. False when there was nothing to close or clear.
    func escape() -> Bool {
        if isPriceTableOpen {
            isPriceTableOpen = false
            return true
        }
        guard hasScope else { return false }
        clearScope()
        return true
    }

    /// The scope chip's words for the pick.
    var pickTitle: String? {
        switch pick {
        case .model(_, let name): return name
        case .project(let name): return name
        case nil: return nil
        }
    }

    // MARK: Screenshots and tests

    /// Puts a scan result on screen without scanning, for the headless shots and the app tests.
    func preview(result: TokenScanResult?, now: Date) {
        self.result = result
        query = result.map { TokenQuery(ledger: $0.ledger, now: now, timeZone: timeZone) }
        scannedAt = result == nil ? nil : now
        failure = nil
    }

    /// Shots only: a scan in progress.
    func previewProgress(_ step: UsageProgress?) {
        result = nil
        query = nil
        progress = step
        isScanning = true
    }
}
