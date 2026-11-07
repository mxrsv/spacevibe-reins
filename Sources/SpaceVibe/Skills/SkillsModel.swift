import AppKit
import Foundation
import Observation

/// What the Skills tab holds besides the rows: the Filter and View choices, the picked rows and every write. The rows, the
/// scope, the current row and the reads are `LoadoutModel`'s (one model, F1); the sentences are `SkillsWording`'s.
@MainActor
@Observable
final class SkillsModel {
    let loadout: LoadoutModel
    var query = SkillsQuery()
    /// The keys of the picked rows (multi-select, V5-R32). A key leaves the set when its row is removed.
    private(set) var picked: Set<String> = []
    /// Whether any picked row is about to be written: the bottom bar and the toast read the pick count, not this.
    /// `<row key>:<cli>` of the logos just pressed: they play the pop once (V5-R42 drops it under reduced motion).
    private(set) var changed: Set<String> = []
    /// Bumped by `Return`: the pane puts the keyboard focus on its first action.
    private(set) var paneFocusRequest = 0
    /// Which head menu is open; `/` opens Filter.
    var isFilterOpen = false
    var isViewOpen = false
    var isScopeOpen = false

    /// A head menu holds the keyboard, so the page's plain keys are off.
    var isMenuOpen: Bool { isFilterOpen || isViewOpen || isScopeOpen }
    @ObservationIgnored var now: () -> Date = { Date() }
    /// Opens a file in its default app; a test swaps it so nothing opens.
    @ObservationIgnored var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }

    init(loadout: LoadoutModel) { self.loadout = loadout }

    private var env: AppEnvironment { loadout.env }

    // MARK: Rows

    /// The skills of the chosen scope, before any filter.
    var rows: [LoadoutRow] {
        (loadout.view()?.all ?? []).filter { $0.kind == .skill }
    }

    var layout: SkillsQuery.Layout { query.layout(rows, now: now()) }

    /// The scope control's label: "Global" or a project's folder name.
    var scopeLabel: String { loadout.view()?.scope.label ?? "Global" }

    /// True once the inventory has been read, so "empty" never shows while it loads.
    var isLoaded: Bool { loadout.data != nil }

    /// Ranks and statuses read the rows of the scope before the filter.
    func status(of row: LoadoutRow, among rows: [LoadoutRow]) -> SkillStatus {
        SkillStatus.of(row, marks: SkillRank.marks(for: rows)[row.key] ?? [])
    }

    var events: [String: [String]] { loadout.data?.events ?? [:] }

    /// The CLIs the logo strip lists, Claude Code first.
    var detected: [CoreCLI] { LoadoutRows.detectedCLIs(limits: env.limits.results, rows: rows) }

    /// The busiest skill's session count in any one CLI: the meters' scale.
    var maxSessions: Int {
        rows.flatMap { row in CoreCLI.allCases.compactMap { row.skillUsage.sessions(in: $0) } }.max() ?? 0
    }

    // MARK: Current row and picks

    /// The row the pane shows: the chosen one while it is listed, else the first listed.
    func current(in visible: [LoadoutRow]) -> LoadoutRow? {
        visible.first { $0.key == loadout.selectedKey } ?? visible.first
    }

    func select(_ key: String) { loadout.select(key) }

    /// `j` (`by: 1`) and `k` (`by: -1`) over the rows listed now, stopping at the first and the last.
    func move(by step: Int, in visible: [LoadoutRow]) {
        guard let current = current(in: visible), let index = visible.firstIndex(of: current) else { return }
        select(visible[min(max(index + step, 0), visible.count - 1)].key)
    }

    func togglePick(_ key: String) {
        if picked.contains(key) { picked.remove(key) } else { picked.insert(key) }
    }

    func clearPicks() { picked = [] }

    func focusPane() { paneFocusRequest += 1 }

    private func flash(_ keys: [String]) {
        changed = Set(keys)
        Task { [weak self] in
            try? await Task.sleep(for: Metrics.Motion.flash)
            self?.changed = []
        }
    }

    var pickedRows: [LoadoutRow] {
        let keys = picked
        return keys.isEmpty ? [] : layout.rows.filter { keys.contains($0.key) }
    }

    func setScope(_ value: String) {
        loadout.setScope(value)
        picked = []
    }

    // MARK: Filter and View

    func toggleFilter(_ field: SkillsFilterField, _ value: String) { query.filter.toggle(field, value) }

    func clearFilters() { query.filter.clear() }

    // MARK: Logos and writes (V5-R25, V5-R26, V5-R38)

    func mode(_ row: LoadoutRow, cli: CoreCLI) -> LogoToggleMode { LoadoutRows.logoMode(row, cli: cli, events: events) }

    /// Pressing a row's or the pane's logo: a lit one removes the skill from that CLI, a dim one adds it there.
    func toggle(_ row: LoadoutRow, cli: CoreCLI) {
        guard mode(row, cli: cli) == .toggles else { return }
        if row.members[cli] == nil { add([row], to: cli) } else { remove([row], from: cli) }
    }

    /// The bottom bar's logo: lit when every picked skill has that CLI.
    func isLit(_ rows: [LoadoutRow], cli: CoreCLI) -> Bool {
        !rows.isEmpty && rows.allSatisfy { $0.members[cli] != nil }
    }

    func bulkMode(_ rows: [LoadoutRow], cli: CoreCLI) -> LogoToggleMode {
        if isLit(rows, cli: cli) {
            if !LoadoutRows.removeWrites(rows, from: cli).steps.isEmpty { return .toggles }
            return rows.contains { $0.plugin != nil || $0.project != nil } ? .readOnly : .onlyCopy
        }
        return LoadoutRows.addWrites(rows, to: cli, events: events).steps.isEmpty ? .readOnly : .toggles
    }

    func toggleBulk(_ rows: [LoadoutRow], cli: CoreCLI) {
        guard !rows.isEmpty else { return }
        if isLit(rows, cli: cli) { remove(rows, from: cli) } else { add(rows, to: cli) }
    }

    func add(_ rows: [LoadoutRow], to cli: CoreCLI) {
        let plan = LoadoutRows.addWrites(rows, to: cli, events: events)
        guard !plan.steps.isEmpty else {
            if rows.contains(where: { $0.members[cli] == nil }) { env.toasts.show(SkillsWording.nothingToChange(rows, adding: true)) }
            return
        }
        let written = rows.filter { $0.members[cli] == nil && LoadoutRows.copyPlan($0, to: cli, events: events) != nil && $0.plugin == nil }
        flash(written.map { "\($0.key):\(cli.rawValue)" })
        loadout.perform(skillWrites: plan.steps, guardKey: "skills:add:\(cli.rawValue):\(written.map(\.key).sorted().joined(separator: ","))",
                        label: SkillsWording.addLabel(written, to: cli, skipped: plan.skipped))
    }

    /// Removes the rows from `cli`, or from every CLI that has them when `cli` is nil.
    func remove(_ rows: [LoadoutRow], from cli: CoreCLI? = nil) {
        let plan = LoadoutRows.removeWrites(rows, from: cli)
        guard !plan.steps.isEmpty else {
            env.toasts.show(SkillsWording.nothingToChange(rows, adding: false))
            return
        }
        let written = rows.filter { !LoadoutRows.removeWrites([$0], from: cli).steps.isEmpty }
        flash(plan.steps.compactMap { step in
            guard case .remove(let id, let from) = step, let row = written.first(where: { $0.members[from]?.id == id }) else { return nil }
            return "\(row.key):\(from.rawValue)"
        })
        loadout.perform(skillWrites: plan.steps, guardKey: "skills:remove:\(cli?.rawValue ?? "all"):\(written.map(\.key).sorted().joined(separator: ","))",
                        label: SkillsWording.removeLabel(written, from: cli, skipped: plan.skipped))
        picked.subtract(written.map(\.key))
    }

    /// `a`: add each target skill to every detected CLI that lacks it.
    func addToOtherCLI(_ rows: [LoadoutRow]) {
        for cli in detected { add(rows.filter { $0.members[cli] == nil }, to: cli) }
    }

    /// The file `Open` and `o` show: the first CLI's copy (Claude Code first).
    func openFile(of row: LoadoutRow) {
        guard let member = CoreCLI.allCases.compactMap({ row.members[$0] }).first, let url = Self.fileURL(member) else { return }
        openFile(url)
    }

    static func fileURL(_ member: LoadoutMember) -> URL? {
        switch member {
        case .item(let item): item.file.isEmpty ? nil : URL(fileURLWithPath: item.file)
        case .hook(let hook): hook.file.isEmpty ? nil : URL(fileURLWithPath: hook.file)
        }
    }

    /// The files a skill lives in, one per CLI, with the home folder shortened.
    func files(of row: LoadoutRow) -> [(cli: CoreCLI, path: String)] {
        let home = loadout.data?.home
        return CoreCLI.allCases.compactMap { cli in
            guard case .item(let item)? = row.members[cli] else { return nil }
            return (cli, LoadoutRows.shorten(item.file, home: home))
        }
    }
}
