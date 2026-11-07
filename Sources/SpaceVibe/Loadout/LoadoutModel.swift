import Foundation
import Observation

/// What the table shows right now: the scope's rows before and after the chip filter, its chip counts and the bar scale.
struct LoadoutView {
    var scope: LoadoutScope
    var all: [LoadoutRow]
    var shown: [LoadoutRow]
    var counts: CoreFilterCounts
    var max: [LoadoutKind: Int]
}

/// The Loadout screen's state: the inventory, the usage scan, the chip and scope choice, and every write.
///
/// Everything goes through the Go core (`env.goCore`): reads, the scan, writes and Undo. The rows are read first and shown with pending cells; the scan then runs and the rows are read
/// again with its counts attached. After every write (and every Undo) the rows are read again; the core keeps the usage totals,
/// because a write cannot change what the logs say. A newer read or build replaces an older one, so a slow one never
/// overwrites a fresh one.
@MainActor
@Observable
final class LoadoutModel {
    /// A second click on the same button is ignored until the write has finished and at least this long has passed
    /// (the row is still on screen until the re-read lands), so one write cannot run twice.
    static let writeGuard: Duration = .milliseconds(500)

    let env: AppEnvironment

    private(set) var data: LoadoutData?
    /// The inventory could not be read at all (no config folders).
    private(set) var readFailure: String?
    private(set) var usageResult: CoreUsageResult?
    private(set) var scanProgress: CoreUsageProgress?
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
    @ObservationIgnored private var raw: CoreLoadoutRows?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var scanRunning = false
    @ObservationIgnored private var readsInFlight = 0
    @ObservationIgnored private var buildsRequested = 0
    @ObservationIgnored private var buildsApplied = 0
    @ObservationIgnored private var readGeneration = 0
    @ObservationIgnored private var buildGeneration = 0
    /// Write guard key -> ticket of the write that holds it. Only that write's completion releases it.
    @ObservationIgnored private var inFlight: [String: Int] = [:]
    @ObservationIgnored private var guardTickets = 0

    init(env: AppEnvironment) { self.env = env }

    /// Shots and tests: a model that shows `data` and never reads, for a state the fixture home cannot show (an empty category;
    /// no data at all is the loading state).
    init(env: AppEnvironment, data: LoadoutData?) {
        self.env = env
        self.data = data
        started = true
    }

    var isLoading: Bool { data == nil && readFailure == nil }

    /// Reads, scans and builds are all done. Screenshots wait for this.
    var isSettled: Bool {
        data != nil && readsInFlight == 0 && !scanRunning && buildsRequested == buildsApplied
    }

    var usageNote: String {
        LoadoutFormat.usageNote(result: usageResult, progress: scanProgress, failure: scanFailure)
    }

    var badge: Int? { data?.globalCount }

    private var core: any CoreService { env.goCore }

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
        let generation = beginRead()
        Task { await fetch(generation) }
    }

    /// Counted before the task starts, so `isSettled` is false from the moment a read is asked for.
    private func beginRead() -> Int {
        readGeneration += 1
        readsInFlight += 1
        return readGeneration
    }

    /// One `loadout.rows`, then the build. Nothing is read while the core cannot resolve the config folders: its refusal is
    /// the failure shown.
    private func fetch(_ generation: Int) async {
        do {
            let rows = try await core.loadoutRows()
            readsInFlight -= 1
            guard generation == readGeneration else { return }
            raw = rows
            readFailure = nil
            // A core that has no scan result (it restarted, so the old one is gone) answers `scanning` until someone scans.
            // The old note and counts describe a core that is gone, so they are dropped and the scan is asked for again.
            if rows.usage == .scanning, !scanRunning {
                usageResult = nil
                scanFailure = nil
                scan()
            }
            await rebuild()
        } catch {
            readsInFlight -= 1
            guard generation == readGeneration, !(error is CancellationError) else { return }
            readFailure = AppEnvironment.message(error)
        }
    }

    private func scan() {
        guard !scanRunning else { return }
        scanRunning = true
        Task {
            do {
                let result = try await core.usageScan(progress: { [weak self] progress in
                    Task { @MainActor in self?.scanProgress = progress }
                })
                usageResult = result
                scanFailure = nil
            } catch is CancellationError {
                // Nothing to report; the next refresh scans again.
            } catch {
                // The core's own sentence or a fixed one, never a raw description (S-R3).
                scanFailure = AppEnvironment.message(error)
            }
            scanProgress = nil
            // The core attaches the finished scan to the rows it sends next, so the cells are read again.
            await fetch(beginRead())
            scanRunning = false
        }
    }

    private func rebuild() async {
        guard let snapshot = raw else { return }
        buildsRequested += 1
        buildGeneration += 1
        let generation = buildGeneration
        let built = await Task.detached(priority: .userInitiated) { LoadoutData.build(raw: snapshot) }.value
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
            counts: data.countsByScope[effective.value] ?? CoreFilterCounts(all: 0, only: .init(claude: 0, codex: 0), neverRan: 0, dead: 0),
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

    func add(_ row: LoadoutRow, to cli: CoreCLI) {
        guard let id = LoadoutRows.copyPlan(row, to: cli, events: data?.events ?? [:]) else { return }
        perform(guardKey: "copy:\(id):\(cli.rawValue)", label: LoadoutFormat.addLabel(row: row, to: cli)) { core in
            try await core.loadoutCopyToOther(id: id).entry
        }
    }

    func remove(_ row: LoadoutRow, member: LoadoutMember) {
        let id = member.id
        perform(guardKey: "remove:\(id)", label: LoadoutFormat.removeLabel(row: row, member: member)) { core in
            try await core.loadoutRemoveItem(id: id).entry
        }
    }

    /// Writes that hold their double-click guard right now. Screenshots check it.
    var guardedWrites: Int { inFlight.count }

    /// The dead hooks `loadout.removeDeadHooks` removes for this CLI: every one, not one per row (two files can share a row).
    func deadHookCount(cli: CoreCLI) -> Int {
        raw?.hooks.filter { $0.cli == cli && $0.dead && $0.removable }.count ?? 0
    }

    func removeDeadHooks(cli: CoreCLI) {
        let count = deadHookCount(cli: cli)
        let label = "Removed \(count) dead \(count == 1 ? "hook" : "hooks") from \(cli.label)"
        perform(guardKey: "remove-dead:\(cli.rawValue)", label: label) { core in
            try await core.loadoutRemoveDeadHooks(cli: cli).entry
        }
    }

    // MARK: Skill writes (V5-R25, V5-R26, V5-R38)

    /// Runs the writes of a skill toggle, a bulk add or a removal one after the other and shows ONE toast whose Undo undoes
    /// every one of them, newest first, then reads the rows again once. No bulk call exists in the core, so each step is its own
    /// journal entry; a step that fails undoes the ones already written before the danger toast, so a bulk write is all or
    /// nothing. `label` names the whole change ("Added 3 skills to Codex"); `note` is a sentence only the success toast adds after it
    /// (what the copy leaves out), never the Undo toast. Returns at once; the write runs in a task.
    func perform(skillWrites steps: [LoadoutRows.SkillWrites.Step], guardKey: String, label: String, note: String? = nil) {
        guard !steps.isEmpty, inFlight[guardKey] == nil else { return }
        guardTickets += 1
        let ticket = guardTickets
        inFlight[guardKey] = ticket
        let started = ContinuousClock.now
        let core = self.core
        Task { [weak self] in
            var entries: [CoreJournalEntry] = []
            do {
                for step in steps { entries.append(try await Self.run(step, on: core)) }
            } catch {
                let reverted = await AppEnvironment.undoAll(entries, on: core)
                guard let self else { return }
                self.release(guardKey, ticket: ticket, since: started)
                let message = AppEnvironment.message(error)
                self.env.toasts.show(reverted ? message : "\(message) Some earlier changes could not be undone.", tone: .danger)
                if !entries.isEmpty { self.reload() }
                return
            }
            guard let self else { return }
            self.release(guardKey, ticket: ticket, since: started)
            self.env.toasts.show(note.map { "\(label). \($0)" } ?? label, undo: { [weak self] in self?.undoSkillWrites(entries, label: label) })
            self.reload()
        }
    }

    private nonisolated static func run(_ step: LoadoutRows.SkillWrites.Step, on core: any CoreService) async throws -> CoreJournalEntry {
        switch step {
        case .copy(let id, _): try await core.loadoutCopyToOther(id: id).entry
        case .remove(let id, _): try await core.loadoutRemoveItem(id: id).entry
        }
    }

    private func undoSkillWrites(_ entries: [CoreJournalEntry], label: String) {
        let core = self.core
        Task { [weak self] in
            let done = await AppEnvironment.undoAll(entries, on: core)
            guard let self else { return }
            self.env.toasts.show(done ? "Undid \(label)" : "Could not undo all of \(label)", tone: done ? .info : .danger)
            self.reload()
        }
    }

    private func perform(guardKey: String, label: String, _ work: @escaping @Sendable (any CoreService) async throws -> CoreJournalEntry) {
        guard inFlight[guardKey] == nil else { return }
        guardTickets += 1
        let ticket = guardTickets
        inFlight[guardKey] = ticket
        let started = ContinuousClock.now
        env.performWithUndo(
            label: label,
            via: core,
            afterChange: { [weak self] in
                self?.release(guardKey, ticket: ticket, since: started)
                self?.reload()
            },
            onFailure: { [weak self] message in
                self?.release(guardKey, ticket: ticket, since: started)
                self?.env.toasts.show(message, tone: .danger)
            }
        ) { try await work($0) }
    }

    /// Frees the guard once the write finished, but not before `writeGuard` has passed. Undo reuses `afterChange`; its stale
    /// ticket makes that a no-op.
    private func release(_ key: String, ticket: Int, since started: ContinuousClock.Instant) {
        Task {
            let rest = Self.writeGuard - (ContinuousClock.now - started)
            if rest > .zero { try? await Task.sleep(for: rest) }
            if inFlight[key] == ticket { inFlight[key] = nil }
        }
    }
}
