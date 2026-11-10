import Foundation
import Observation

/// What the Hooks tab holds besides the rows: the Filter choice, the current row, the open detail popover and every write. The
/// rows, the reads and the writes' plumbing are `LoadoutModel`'s (one model, F1); the sentences are `HooksWording`'s and the
/// derived facts `HooksQuery`'s. The tab shows the global scope only (V5-R61: no scope control).
@MainActor
@Observable
final class HooksModel {
    static let page = "hooks"

    let loadout: LoadoutModel
    var query = HooksQuery()
    /// The row the keys act on: the chosen one while it is listed, else the first listed.
    var currentKey: String?
    /// The row whose detail popover is open (V5-R57).
    var detailKey: String?
    /// The `Why` popover of `Can't copy to Codex` is open.
    var isWhyOpen = false
    /// `<row key>:<cli>` of the logos just pressed: they play the pop once (V5-R42 drops it under reduced motion).
    private(set) var changed: Set<String> = []
    var isFilterOpen = false

    /// A head menu holds the keyboard, so the page's plain keys are off.
    var isMenuOpen: Bool { isFilterOpen }

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

    /// The global hooks, before any filter.
    var rows: [LoadoutRow] {
        LoadoutRows.inScope(loadout.data?.rows ?? [], scope: LoadoutRows.globalScope).filter { $0.kind == .hook }
    }

    /// True once the inventory has been read, so "empty" never shows while it loads.
    var isLoaded: Bool { loadout.data != nil }

    /// The CLIs the logo strip lists, Claude Code first (V5-R24): one that is not installed has no logo.
    var detected: [CoreCLI] { LoadoutRows.detectedCLIs(limits: limitsResults(), rows: rows) }

    var events: [String: [String]] { loadout.data?.events ?? [:] }

    var home: String? { loadout.data?.home }

    var context: HooksContext { HooksContext(events: events, detected: detected) }

    var layout: HooksQuery.Layout { query.layout(rows, context: context) }

    var answer: HooksAnswer { HooksAnswer.of(rows, isLoaded: isLoaded, context: context, notShown: !notShown.isEmpty) }

    var missing: HooksMissing { HooksMissing(rows, context: context) }

    var cantCopy: HooksCantCopy { HooksCantCopy(rows, context: context) }

    /// The values of the Filter's `Event` field: the events that have a hook.
    var eventValues: [FilterValue] { HooksQuery.eventValues(events: events, rows: rows) }

    /// The core's lines about hooks it does not list (a handler other than `command`), so the tab's count is not read as all of them.
    var notShown: [String] { (loadout.data?.problems ?? []).filter(HooksWording.isOtherTypesProblem) }

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

    /// A small card's row: clear the filters, open the row's band, make it current and open its detail.
    func reveal(_ key: String, store: OpenStateStore) {
        query.filter.clear()
        if let band = layout.bands.first(where: { $0.rows.contains { $0.key == key } }) {
            store.setOpen(true, page: Self.page, id: band.id)
        }
        open(key)
    }

    // MARK: Filter

    func toggleFilter(_ field: HooksFilterField, _ value: String) {
        query.filter.toggle(field, value)
        detailKey = nil
    }

    func clearFilters() {
        query.filter.clear()
        detailKey = nil
    }

    // MARK: Logos and writes (V5-R25, V5-R38, V5-R66)

    /// What pressing a logo does. A CLI that cannot take the hook has no toggle at all (the strip draws nothing there).
    func mode(_ row: LoadoutRow, cli: CoreCLI) -> LogoToggleMode { LoadoutRows.logoMode(row, cli: cli, events: events) }

    /// Whether the strip draws a logo for `cli`: it has the hook, or the one rule lets it take it.
    func showsToggle(_ row: LoadoutRow, cli: CoreCLI) -> Bool { row.members[cli] != nil || context.block(row, to: cli) == nil }

    /// Pressing a logo: a lit one removes that copy, a dim one copies the hook there.
    func toggle(_ row: LoadoutRow, cli: CoreCLI) {
        guard mode(row, cli: cli) == .toggles else { return }
        if row.members[cli] == nil { copy(row, to: cli) } else { remove(row, from: cli) }
    }

    /// Copies the hook into `cli`: one write, one toast with Undo.
    func copy(_ row: LoadoutRow, to cli: CoreCLI) {
        detailKey = nil
        if let block = context.block(row, to: cli) {
            env.toasts.show(HooksWording.long(block))
            return
        }
        let plan = LoadoutRows.addWrites([row], to: cli, events: events)
        guard !plan.steps.isEmpty else {
            if row.members[cli] == nil { env.toasts.show(HooksWording.nothingToChange(row, adding: true)) }
            return
        }
        changed = ["\(row.key):\(cli.rawValue)"]
        Task { [weak self] in
            try? await Task.sleep(for: Metrics.Motion.flash)
            self?.changed = []
        }
        loadout.perform(skillWrites: plan.steps, guardKey: "hooks:copy:\(row.key)>\(cli.rawValue)",
                        label: HooksWording.copyLabel(row, to: cli), note: row.hookMatcher == nil ? nil : HooksWording.matcherNote)
    }

    /// The Answer's `Copy M to Codex`: every hook the rule lets Codex take, in one toast with one Undo.
    func copyMissing(_ rows: [LoadoutRow]) {
        let plan = LoadoutRows.addWrites(rows, to: .codex, events: events)
        guard !plan.steps.isEmpty else { return }
        loadout.perform(skillWrites: plan.steps, guardKey: "hooks:copy-all>codex", label: HooksWording.copyAllLabel(plan.rows, to: .codex),
                        note: rows.contains { $0.hookMatcher != nil } ? HooksWording.matcherNote : nil)
    }

    /// Removes the hook from `cli`, or from every CLI that has it when `cli` is nil. A plugin's is never written.
    func remove(_ row: LoadoutRow, from cli: CoreCLI? = nil) {
        detailKey = nil
        let plan = LoadoutRows.removeWrites([row], from: cli)
        guard !plan.steps.isEmpty else {
            env.toasts.show(HooksWording.nothingToChange(row, adding: false))
            return
        }
        // Only a removal from every CLI takes the row off the list; one CLI's copy leaves it listed.
        let leaving: Set<String> = cli == nil && row.members.values.allSatisfy(\.removable) ? [row.key] : []
        let before = currentKey
        let after = CurrentRow.neighbour(of: leaving, current: before, in: listedKeys)
        let taken = loadout.perform(skillWrites: plan.steps, guardKey: LoadoutModel.removalGuardKey, label: HooksWording.removeLabel(row, from: cli),
                                    onFailure: { [weak self] in
                                        if self?.currentKey == after { self?.currentKey = before }
                                    })
        if taken, after != before { currentKey = after }
    }

    /// `a`: the CLI the hook is not in.
    func copyToOtherCLI(_ row: LoadoutRow?) {
        guard let row else { return }
        guard row.presentCLIs.count == 1, let here = row.presentCLIs.first else {
            env.toasts.show("\(row.hookTitle) is already in both CLIs")
            return
        }
        copy(row, to: here.other)
    }
}
