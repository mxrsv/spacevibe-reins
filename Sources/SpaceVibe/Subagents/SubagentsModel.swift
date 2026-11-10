import Foundation
import Observation

/// What the Subagents tab holds besides the rows: the Filter and Group choices, the current row, the open detail popover and
/// every write. The rows, the reads and the writes' plumbing are `LoadoutModel`'s (one model, F1); the sentences are
/// `SubagentsWording`'s and the derived facts `SubagentsQuery`'s. The tab shows the global scope only (V5-R61: no scope control).
@MainActor
@Observable
final class SubagentsModel {
    static let page = "subagents"

    let loadout: LoadoutModel
    var query = SubagentsQuery()
    /// The row the keys act on: the chosen one while it is listed, else the first listed.
    var currentKey: String?
    /// The row whose detail popover is open (V5-R57).
    var detailKey: String?
    /// `<row key>:<cli>` of the logos just pressed: they play the pop once (V5-R42 drops it under reduced motion).
    private(set) var changed: Set<String> = []
    var isFilterOpen = false
    var isGroupOpen = false

    /// A head menu holds the keyboard, so the page's plain keys are off.
    var isMenuOpen: Bool { isFilterOpen || isGroupOpen }

    /// The keys listed now, in order: the tab writes them, so a removal can hand the current row to its neighbour (D2).
    @ObservationIgnored var listedKeys: [String] = []
    @ObservationIgnored var now: () -> Date = { Date() }
    /// The CLIs on this Mac: the shell's reading (`limits.read`), which a shot or a test replaces.
    @ObservationIgnored var limitsResults: () -> [CoreLimitsEntry]

    init(loadout: LoadoutModel) {
        self.loadout = loadout
        let env = loadout.env
        limitsResults = { env.limits.results }
    }

    private var env: AppEnvironment { loadout.env }

    // MARK: Rows

    /// The global subagents, before any filter.
    var rows: [LoadoutRow] {
        LoadoutRows.inScope(loadout.data?.rows ?? [], scope: LoadoutRows.globalScope).filter { $0.kind == .agent }
    }

    /// True once the inventory has been read, so "empty" never shows while it loads.
    var isLoaded: Bool { loadout.data != nil }

    var layout: SubagentsQuery.Layout { query.layout(rows) }

    /// The CLIs the logo strip lists, Claude Code first (V5-R24): one that is not installed has no logo.
    var detected: [CoreCLI] { LoadoutRows.detectedCLIs(limits: limitsResults(), rows: rows) }

    var answer: SubagentsAnswer {
        SubagentsAnswer.of(rows, isLoaded: isLoaded, detected: detected, since: LoadoutFormat.usageSince(loadout.usageResult))
    }

    var addable: SubagentsAddable { SubagentsAddable(rows, detected: detected) }

    private var events: [String: [String]] { loadout.data?.events ?? [:] }

    // MARK: Current row and the detail

    func current(in visible: [LoadoutRow]) -> LoadoutRow? {
        visible.first { $0.key == currentKey } ?? visible.first
    }

    /// A click on a row: it becomes current and its detail opens (V5-R57).
    func open(_ key: String) {
        currentKey = key
        detailKey = key
    }

    /// `j` (`by: 1`) and `k` (`by: -1`) over the rows listed now, stopping at the first and the last; the detail closes.
    func move(by step: Int, in visible: [LoadoutRow]) {
        guard let current = current(in: visible), let index = visible.firstIndex(of: current) else { return }
        currentKey = visible[min(max(index + step, 0), visible.count - 1)].key
        detailKey = nil
    }

    /// `Return`: the detail of the current row, closed when it is open already.
    func toggleDetail(of row: LoadoutRow?) {
        guard let row else { return }
        currentKey = row.key
        detailKey = detailKey == row.key ? nil : row.key
    }

    /// The Answer's `Review`: clear the filters, open the row's band, make it current and open its detail (V5-R63).
    func review(_ key: String, store: OpenStateStore) {
        query.filter.clear()
        if let group = layout.groups.first(where: { $0.rows.contains { $0.key == key } }), layout.isGrouped {
            store.setOpen(true, page: Self.page, id: group.id)
        }
        open(key)
    }

    // MARK: Filter and Group

    func toggleFilter(_ field: SubagentsFilterField, _ value: String) {
        query.filter.toggle(field, value)
        detailKey = nil
    }

    func clearFilters() {
        query.filter.clear()
        detailKey = nil
    }

    // MARK: Logos and writes (V5-R25, V5-R38, V5-R64)

    func mode(_ row: LoadoutRow, cli: CoreCLI) -> LogoToggleMode { LoadoutRows.logoMode(row, cli: cli, events: events) }

    /// Pressing a logo: a lit one removes that copy, a dim one adds the subagent there.
    func toggle(_ row: LoadoutRow, cli: CoreCLI) {
        guard mode(row, cli: cli) == .toggles else { return }
        if row.members[cli] == nil { add(row, to: cli) } else { remove(row, from: cli) }
    }

    /// Copies the subagent into `cli`: one write, one toast with Undo that says what the copy left out (G10).
    func add(_ row: LoadoutRow, to cli: CoreCLI) {
        detailKey = nil
        let plan = LoadoutRows.addWrites([row], to: cli, events: events)
        guard !plan.steps.isEmpty else {
            if row.members[cli] == nil { env.toasts.show(SubagentsWording.nothingToChange(row, adding: true)) }
            return
        }
        changed = ["\(row.key):\(cli.rawValue)"]
        Task { [weak self] in
            try? await Task.sleep(for: Metrics.Motion.flash)
            self?.changed = []
        }
        loadout.perform(skillWrites: plan.steps, guardKey: "subagents:add:\(row.key)>\(cli.rawValue)",
                        label: SubagentsWording.addLabel(row, to: cli), note: SubagentsWording.addNote(to: cli))
    }

    /// Removes the subagent from `cli`, or from every CLI that has it when `cli` is nil. A plugin's is never written.
    func remove(_ row: LoadoutRow, from cli: CoreCLI? = nil) {
        detailKey = nil
        let plan = LoadoutRows.removeWrites([row], from: cli)
        guard !plan.steps.isEmpty else {
            env.toasts.show(SubagentsWording.nothingToChange(row, adding: false))
            return
        }
        // Only a removal from every CLI takes the row off the list; one CLI's copy leaves it listed.
        let leaving: Set<String> = cli == nil && row.members.values.allSatisfy(\.removable) ? [row.key] : []
        let before = currentKey
        let after = CurrentRow.neighbour(of: leaving, current: before, in: listedKeys)
        let taken = loadout.perform(skillWrites: plan.steps, guardKey: LoadoutModel.removalGuardKey, label: SubagentsWording.removeLabel(row, from: cli),
                                    onFailure: { [weak self] in
                                        if self?.currentKey == after { self?.currentKey = before }
                                    })
        if taken, after != before { currentKey = after }
    }

    /// `a`: the CLI the subagent is not in, when it is on this Mac.
    func addToOtherCLI(_ row: LoadoutRow?) {
        guard let row else { return }
        guard row.presentCLIs.count == 1, let here = row.presentCLIs.first else {
            env.toasts.show("\(row.name) is already in both CLIs")
            return
        }
        let target = here.other
        guard detected.contains(target) else {
            env.toasts.show("\(target.label) is not installed on this Mac.")
            return
        }
        add(row, to: target)
    }
}
