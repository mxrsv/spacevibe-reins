import Foundation
import Observation
import ReinsCore

/// What the table shows right now: the scope's rows before and after the chip filter, its chip counts and the bar scale.
struct LoadoutView {
    var scope: LoadoutScope
    var all: [LoadoutRow]
    var shown: [LoadoutRow]
    var counts: FilterCounts
    var max: [LoadoutKind: Int]
}

/// The Loadout screen's state: the inventory, the usage scan, the chip and scope choice, and every write.
///
/// Reads and the scan run off the main actor. The inventory is read first and shown with pending cells; the scan then fills the
/// cells in. After every write (and every Undo) the inventory is read again; the usage totals are kept, because a write cannot
/// change what the logs say. A newer read or build replaces an older one, so a slow one never overwrites a fresh one.
@MainActor
@Observable
final class LoadoutModel {
    /// A second click on the same button inside this time is ignored, so one write cannot run twice.
    static let writeGuard: Duration = .seconds(1.5)

    let env: AppEnvironment

    private(set) var data: LoadoutData?
    /// The inventory could not be read at all (no config folders).
    private(set) var readFailure: String?
    private(set) var usageResult: UsageResult?
    private(set) var scanProgress: UsageProgress?
    private(set) var scanFailure: String?

    var scope = LoadoutRows.globalScope
    var filter = LoadoutFilter.all
    var selectedKey: String?
    /// Bumped by every jump from the palette; the table scrolls to `selectedKey` when it changes.
    private(set) var jumpToken = 0

    /// Screenshots only: show row actions without hover, and show only some sections.
    var revealRowActions = false
    var shotKinds: Set<LoadoutKind>?

    /// Set by the screen, so a palette entry can switch to this tab.
    @ObservationIgnored weak var shell: ShellModel?
    @ObservationIgnored private var raw: InventorySnapshot?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var scanRunning = false
    @ObservationIgnored private var readsInFlight = 0
    @ObservationIgnored private var buildsRequested = 0
    @ObservationIgnored private var buildsApplied = 0
    @ObservationIgnored private var readGeneration = 0
    @ObservationIgnored private var buildGeneration = 0
    @ObservationIgnored private var inFlight = Set<String>()

    init(env: AppEnvironment) { self.env = env }

    var isLoading: Bool { data == nil && readFailure == nil }

    /// Reads, scans and builds are all done. Screenshots wait for this.
    var isSettled: Bool {
        data != nil && readsInFlight == 0 && !scanRunning && buildsRequested == buildsApplied
    }

    var usageNote: String {
        LoadoutFormat.usageNote(result: usageResult, progress: scanProgress, failure: scanFailure)
    }

    var badge: Int? { data?.globalCount }

    // MARK: Reading

    /// The first read and scan. Safe to call again.
    func start() {
        guard !started else { return }
        started = true
        reload()
        scan()
    }

    /// The app became active again: files may have changed outside.
    func refresh() {
        guard started else { return }
        reload()
        scan()
    }

    func retry() {
        readFailure = nil
        reload()
        scan()
    }

    func reload() {
        guard let roots = env.roots else {
            readFailure = env.startupProblem ?? "The config folders could not be resolved."
            return
        }
        readGeneration += 1
        let generation = readGeneration
        readsInFlight += 1
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) { Inventory.read(roots: roots) }.value
            readsInFlight -= 1
            guard generation == readGeneration else { return }
            raw = snapshot
            readFailure = nil
            await rebuild()
        }
    }

    private func scan() {
        guard let roots = env.roots, !scanRunning else { return }
        scanRunning = true
        let scanner = UsageScanner(roots: roots)
        Task {
            do {
                let result = try await scanner.scan(progress: { [weak self] progress in
                    Task { @MainActor in self?.scanProgress = progress }
                })
                usageResult = result
                scanFailure = nil
            } catch is CancellationError {
                // Nothing to report; the next refresh scans again.
            } catch {
                // The engine only throws on cancellation, so this is a defensive branch. The message is the engine's own
                // sentence or a fixed one, never a raw description (S-R3).
                scanFailure = AppEnvironment.message(error)
            }
            scanRunning = false
            scanProgress = nil
            await rebuild()
        }
    }

    private func rebuild() async {
        guard let snapshot = raw else { return }
        buildsRequested += 1
        buildGeneration += 1
        let generation = buildGeneration
        let usage = usageResult.map(UsageInput.ready) ?? .scanning
        let built = await Task.detached(priority: .userInitiated) { LoadoutData.build(raw: snapshot, usage: usage) }.value
        buildsApplied += 1
        guard generation == buildGeneration else { return }
        data = built
    }

    // MARK: Choices

    func view() -> LoadoutView? {
        guard let data else { return nil }
        let effective = data.scopes.first { $0.value == scope } ?? data.scopes[0]
        let all = LoadoutRows.inScope(data.rows, scope: effective.value)
        return LoadoutView(
            scope: effective,
            all: all,
            shown: all.filter { filter.matches($0.flags) },
            counts: data.countsByScope[effective.value] ?? Inventory.filterCounts([]),
            max: LoadoutRows.maxRuns(all)
        )
    }

    func setScope(_ value: String) {
        scope = value
        selectedKey = nil
    }

    func select(_ key: String) { selectedKey = key }

    /// From the palette: show the row, with the filter off and its scope on.
    func jump(to row: LoadoutRow) {
        scope = row.project ?? LoadoutRows.globalScope
        filter = .all
        selectedKey = row.key
        jumpToken += 1
        shell?.select(LoadoutTab.tabID)
    }

    // MARK: Writes

    func add(_ row: LoadoutRow, to cli: InventoryCLI) {
        guard let id = LoadoutRows.copyPlan(row, to: cli, events: data?.events ?? [:]) else { return }
        perform(guardKey: "copy:\(id):\(cli.rawValue)", label: LoadoutFormat.addLabel(row: row, to: cli)) { roots in
            try Mutate.copyToOther(roots: roots, id: id)
        }
    }

    func remove(_ row: LoadoutRow, member: LoadoutMember) {
        let id = member.id
        perform(guardKey: "remove:\(id)", label: LoadoutFormat.removeLabel(row: row, member: member)) { roots in
            try Mutate.removeItem(roots: roots, id: id)
        }
    }

    func removeDeadHooks(cli: InventoryCLI, count: Int) {
        perform(guardKey: "remove-dead:\(cli.rawValue)", label: "Removed \(count) dead hooks from \(cli.uiKind.label)") { roots in
            try Mutate.removeDeadHooks(roots: roots, cli: cli)
        }
    }

    private func perform(guardKey: String, label: String, _ work: @escaping @Sendable (Roots) throws -> JournalEntry) {
        guard inFlight.insert(guardKey).inserted else { return }
        Task {
            try? await Task.sleep(for: Self.writeGuard)
            inFlight.remove(guardKey)
        }
        guard let roots = env.roots else {
            env.toasts.show(env.startupProblem ?? "The config folders could not be resolved.", tone: .danger)
            return
        }
        env.performWithUndo(label: label, afterChange: { [weak self] in self?.reload() }) { try work(roots) }
    }
}
