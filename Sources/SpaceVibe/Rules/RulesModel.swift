import AppKit
import Observation

/// The Rules screen's state: the chosen scope, what was read for it, the grid confirmation, the add-rule draft and every write.
///
/// Everything goes through the Go core (`env.goCore`), so reads and writes run off the main actor. A refresh (launch, app activation, after a write or an Undo) asks the core to discover the projects
/// again; a scope switch reuses the list the core holds. A newer read replaces an older one, so a slow read never overwrites a
/// fresh one. The core keeps settings-file paths out of its messages and checks a rule's shape (`rules.check`). Nothing here
/// reads `env` values or logs rule text.
@MainActor
@Observable
final class RulesModel {
    let env: AppEnvironment

    private(set) var snapshot: RulesSnapshot?
    /// The last read could not run. With a snapshot on screen it shows as a banner over the stale data.
    private(set) var failure: String?
    private(set) var selection = RulesSelection.global
    /// The page on screen: Claude Code's rules or Codex's settings. Both read from the same snapshot.
    private(set) var cli = InventoryCLI.claude
    /// The Codex page lists every project's trust level instead of the first few.
    private(set) var showsAllTrust = false
    /// Grid rows opened to show the rules and Codex keys behind them.
    private(set) var expanded: Set<CoreCapability> = []
    /// The grid write waiting for Confirm or Cancel.
    private(set) var pending: RulesPending?
    private(set) var isWriting = false

    static let page = "rules"

    var draft = ""
    var draftVerdict = CoreVerdict.ask
    /// The engine's (or the shape check's) message about the rule being added, shown next to the field.
    var addError: String?
    /// Bumped by the palette's "Add a Claude Code rule"; the add row takes the focus when it changes.
    private(set) var addFocusToken = 0

    /// Screenshots only: show row actions without hover.
    var revealRowActions = false

    // The v5 tab's own state (V5-R57, V5-R61, V5-R68). The tab shows the global scope only; the old page keeps the rest.
    var filter = RulesFilter()
    /// The rule the keys act on: the chosen one while it is listed, else the first listed.
    var currentID: String?
    /// The rule whose detail popover is open.
    var detailID: String?
    var isFilterOpen = false
    /// The verdict menu that is open: one rule's or a whole family's.
    var verdictMenu: VerdictTarget?

    /// The CLIs on this Mac: the shell's reading (`limits.read`), which a shot or a test replaces.
    @ObservationIgnored var limitsResults: () -> [CoreLimitsEntry]
    @ObservationIgnored weak var shell: ShellModel?
    /// The ids listed now, in order: the tab writes them, so a removal can hand the current rule to its neighbour (D2).
    @ObservationIgnored var listedKeys: [String] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0
    /// Bumped by every preview request and every scope switch, so a preview that finishes late is dropped.
    @ObservationIgnored private var previewEpoch = 0
    @ObservationIgnored private(set) var previewsInFlight = 0
    @ObservationIgnored private(set) var readsInFlight = 0

    init(env: AppEnvironment) {
        self.env = env
        limitsResults = { env.limits.results }
    }

    /// A model over a snapshot read elsewhere (a shot's in-memory state): it reads nothing.
    convenience init(env: AppEnvironment, snapshot: RulesSnapshot?) {
        self.init(env: env)
        self.snapshot = snapshot
        started = true
    }

    private var service: any CoreService { env.goCore }

    var isLoading: Bool { snapshot == nil && failure == nil }

    /// Reads are done and nothing waits for the user. Screenshots wait for this.
    var isSettled: Bool { snapshot != nil && readsInFlight == 0 && previewsInFlight == 0 && !isWriting }

    /// The rules in the global file; nil while unknown, which includes a file that does not parse or cannot be read (a count of 0 would
    /// say "no rules", and V5-R68 hides them instead).
    var badge: Int? {
        guard let snapshot, !snapshot.globalNotReadable else { return nil }
        if snapshot.selection == .global, !snapshot.problems.isEmpty { return nil }
        return snapshot.globalRuleCount
    }

    // MARK: The v5 tab

    /// Codex is on this Mac unless the shell's reading (`limits.read`) says it is not. Before a reading exists nothing says so, and a Mac
    /// with Codex but no `config.toml` must not read "not installed": the page then says there is no file.
    var codexInstalled: Bool {
        limitsResults().first { $0.cli == .codex }.map { $0.state != .notInstalled } ?? true
    }

    var page: RulesPage { RulesPage(snapshot: snapshot, failure: failure, codexInstalled: codexInstalled, filter: filter) }

    /// The tab shows the global scope: the old page (or the palette) may have left another selected.
    func showGlobal() { select(.global) }

    var isMenuOpen: Bool { isFilterOpen || verdictMenu != nil }

    func current(in visible: [CoreRule]) -> CoreRule? { visible.first { $0.id == currentID } ?? visible.first }

    /// A click on a row: it becomes current and its detail opens (V5-R57).
    func open(_ rule: CoreRule) {
        currentID = rule.id
        detailID = rule.id
    }

    /// `j` (`by: 1`) and `k` (`by: -1`) over the rows listed now, stopping at the first and the last; the detail closes.
    func move(by step: Int, in visible: [CoreRule]) {
        guard let current = current(in: visible), let index = visible.firstIndex(of: current) else { return }
        currentID = visible[min(max(index + step, 0), visible.count - 1)].id
        detailID = nil
    }

    /// `Return`: the detail of the current row, closed when it is open already.
    func toggleDetail(of rule: CoreRule?) {
        guard let rule else { return }
        currentID = rule.id
        detailID = detailID == rule.id ? nil : rule.id
    }

    /// A small card's row: clear the Filter, open the rule's band, make it current and open its detail.
    func reveal(_ rule: CoreRule, store: OpenStateStore) {
        filter.clear()
        store.setOpen(true, page: Self.page, id: RuleFamily.of(tool: rule.tool).id)
        open(rule)
    }

    func toggleFilter(_ value: String) {
        filter.toggle(.verdict, value)
        detailID = nil
    }

    func clearFilters() {
        filter.clear()
        detailID = nil
    }

    func toggleVerdictMenu(_ target: VerdictTarget) {
        verdictMenu = verdictMenu == target ? nil : target
    }

    // MARK: Reading

    /// The first read. Safe to call again.
    func start() {
        guard !started else { return }
        started = true
        reload()
    }

    /// The app became active again: the files may have changed outside.
    func refresh() {
        guard started else { return }
        reload()
    }

    func retry() {
        failure = nil
        reload()
    }

    /// `rediscover: false` reuses the project list the core holds (a scope switch); a refresh always discovers again.
    func reload(rediscover: Bool = true) {
        generation += 1
        let mine = generation
        let wanted = selection.scope
        readsInFlight += 1
        Task {
            let outcome = await attempt { try await service.rulesSnapshot(scope: wanted.kind, dir: wanted.dir, refreshProjects: rediscover) }
            readsInFlight -= 1
            guard mine == generation else { return }
            switch outcome {
            case .success(let dto):
                let fresh = RulesSnapshot(dto)
                snapshot = fresh
                if selection != fresh.selection { previewEpoch += 1 }
                selection = fresh.selection
                failure = nil
                // The confirmation was made for one scope; a refresh that moved the selection (the project is gone) closes it.
                if let pending, pending.scope != fresh.selection.scope { self.pending = nil }
            case .failure(let error):
                failure = AppEnvironment.message(error)
            }
        }
    }

    private func attempt<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    // MARK: Choices

    func select(_ choice: RulesSelection) {
        guard choice != selection else { return }
        selection = choice
        previewEpoch += 1
        pending = nil
        addError = nil
        reload(rediscover: false)
    }

    func selectProject(_ dir: String?) { select(RulesSelection(dir: dir, file: selection.file)) }

    func selectFile(_ file: RulesFileKind) {
        guard selection.dir != nil else { return }
        select(RulesSelection(dir: selection.dir, file: file))
    }

    /// Shows one CLI's page. A grid confirmation belongs to the Claude Code page, so leaving it closes the confirmation.
    func selectCLI(_ choice: InventoryCLI) {
        guard choice != cli else { return }
        cli = choice
        pending = nil
    }

    func showAllTrust() { showsAllTrust = true }

    /// From the palette: the Codex page, brought forward.
    func jumpToCodex() {
        selectCLI(.codex)
        shell?.select(RulesTab.tabID)
    }

    /// Selects `~/.codex/config.toml` (or the Codex folder when there is none) in the Finder. Editing stays in the user's
    /// editor; SpaceVibe starts no other app (AGENTS.md S-R4).
    func revealCodexConfig() {
        let root = Self.codexFolder()
        let file = root.appendingPathComponent("config.toml")
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: file.path) ? file : root])
    }

    /// `CODEX_HOME`, else `.codex` in the home folder: where the core reads Codex from.
    private static func codexFolder(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        func value(_ key: String) -> String? { environment[key].flatMap { $0.isEmpty ? nil : $0 } }
        let home = value("HOME") ?? NSHomeDirectory()
        return URL(fileURLWithPath: value("CODEX_HOME") ?? (home as NSString).appendingPathComponent(".codex"), isDirectory: true)
    }

    func toggle(_ capability: CoreCapability) {
        if expanded.contains(capability) { expanded.remove(capability) } else { expanded.insert(capability) }
    }

    func setExpanded(_ capabilities: Set<CoreCapability>) { expanded = capabilities }

    /// From the palette: show a scope and bring the tab forward.
    /// The scope jumps name Claude Code settings files, so they open the Claude Code page.
    func jump(to choice: RulesSelection) {
        selectCLI(.claude)
        select(choice)
        shell?.select(RulesTab.tabID)
    }

    func focusAddRule() {
        selectCLI(.claude)
        shell?.select(RulesTab.tabID)
        addFocusToken += 1
    }

    // MARK: Grid writes

    /// A click on Allow, Ask or Deny. Nothing is written: this asks the core what the write would replace, then opens the confirmation.
    func requestSet(_ capability: CoreCapability, to verdict: CoreVerdict) {
        guard let snapshot, pending == nil else { return }
        guard let cell = snapshot.grid.first(where: { $0.capability == capability }), snapshot.isEditable(cell),
              cell.state != CoreCapabilityState(rawValue: verdict.rawValue) else { return }
        let scope = snapshot.selection.scope
        let title = snapshot.title
        let capabilityLabel = cell.label
        previewEpoch += 1
        let epoch = previewEpoch
        previewsInFlight += 1
        Task {
            let outcome = await attempt { try await service.rulesPreview(scope: scope.kind, dir: scope.dir, capability: capability, verdict: verdict) }
            previewsInFlight -= 1
            // The user switched scope (or asked again) while the core was working: this answer is for a different page.
            guard epoch == previewEpoch, selection.scope == scope else { return }
            switch outcome {
            case .success(let preview):
                let change = RulesPending(preview: preview, scope: scope, scopeTitle: title, capabilityLabel: capabilityLabel)
                if change.isNoOp {
                    env.toasts.show(change.noOpMessage)
                } else {
                    pending = change
                }
            case .failure(let error): env.toasts.show(AppEnvironment.message(error), tone: .danger)
            }
        }
    }

    func cancelPending() { pending = nil }

    /// Writes what the confirmation listed, to the scope it was previewed for, through `performWithUndo`. A write that would
    /// change nothing never opens the confirmation (`requestSet` says so in a toast instead).
    func confirmPending() {
        guard let change = pending, !isWriting else { return }
        pending = nil
        guard change.scope == selection.scope else { return }
        let (capability, verdict) = (change.capability, change.verdict)
        write(label: RulesWording.setLabel(change.capabilityLabel, verdict), scope: change.scope) { core, scope in
            try await core.rulesSetCapability(scope: scope.kind, dir: scope.dir, capability: capability, verdict: verdict).entry
        }
    }

    // MARK: Rule writes

    /// Adds the draft under `draftVerdict`. The core checks the shape first (`rules.check`); its 400, 404 and 409 messages show
    /// next to the field.
    func submitDraft() {
        let rule = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let submitted = draft
        let verdict = draftVerdict
        Task {
            switch await attempt({ try await service.rulesCheck(rule: rule) }) {
            case .success(let check) where check.valid:
                addError = nil
            case .success(let check):
                addError = check.message ?? Self.invalidRule
                return
            case .failure(let error):
                addError = AppEnvironment.message(error)
                return
            }
            write(
                label: "Added \(rule) to \(RulesWording.groupTitle(verdict))",
                clears: submitted,
                onFailure: { [weak self] in self?.addError = $0 }
            ) { core, scope in
                try await core.rulesAdd(scope: scope.kind, dir: scope.dir, verdict: verdict, rule: rule).entry
            }
        }
    }

    /// The sentence for a check that answers "not valid" with no message of its own.
    private static let invalidRule = "That is not a valid rule. Use Tool or Tool(pattern) on one line."

    func remove(_ item: CoreRule) {
        let (verdict, rule) = (item.verdict, item.rule)
        write(label: "Removed \(rule) from \(RulesWording.groupTitle(verdict))") { core, scope in
            try await core.rulesRemove(scope: scope.kind, dir: scope.dir, verdict: verdict, rule: rule).entry
        }
    }

    func move(_ item: CoreRule, to verdict: CoreVerdict) {
        let (from, rule) = (item.verdict, item.rule)
        write(label: "Moved \(rule) from \(RulesWording.groupTitle(from)) to \(RulesWording.groupTitle(verdict))") { core, scope in
            try await core.rulesChangeVerdict(scope: scope.kind, dir: scope.dir, rule: rule, from: from, to: verdict).entry
        }
    }

    // MARK: The v5 tab's writes (V5-R68)

    /// A rule's verdict: one `rules.changeVerdict`, one toast with Undo.
    func set(_ rule: CoreRule, to verdict: CoreVerdict) {
        guard rule.verdict != verdict, page.state == .ready else { return }
        detailID = nil
        write(label: RulesTabWording.ruleChanged(rule.rule, to: verdict), undone: RulesTabWording.undone, [Self.changeStep(rule, to: verdict)])
    }

    /// A whole family's verdict. The core has no call for it (`rules.setCapability` replaces a capability's wide rules with canonical
    /// ones and refuses a mixed cell), so it is one `rules.changeVerdict` per rule that differs: one Journal entry each, ONE toast,
    /// and one Undo that reverts them all, newest first. Nothing differs: a message, no toast with Undo.
    func set(_ family: RuleFamily, to verdict: CoreVerdict) {
        guard page.state == .ready else { return }
        let changing = RulesLayout.unique(page.rules).filter { RuleFamily.of(tool: $0.tool) == family && $0.verdict != verdict }
        detailID = nil
        guard !changing.isEmpty else {
            env.toasts.show(RulesTabWording.familyUnchanged(family, to: verdict))
            return
        }
        write(label: RulesTabWording.familyChanged(family, to: verdict, count: changing.count), undone: RulesTabWording.undone,
              changing.map { Self.changeStep($0, to: verdict) })
    }

    func removeRule(_ rule: CoreRule) {
        guard page.state == .ready else { return }
        detailID = nil
        let (verdict, text) = (rule.verdict, rule.rule)
        let before = currentID
        let after = CurrentRow.neighbour(of: [rule.id], current: before, in: listedKeys)
        let taken = write(
            label: RulesTabWording.removed(text), undone: RulesTabWording.undone,
            onFailure: { [weak self] message in
                guard let self else { return }
                env.toasts.show(message, tone: .danger)
                if currentID == after { currentID = before }
            },
            [{ core, scope in try await core.rulesRemove(scope: scope.kind, dir: scope.dir, verdict: verdict, rule: text).entry }]
        )
        if taken, after != before { currentID = after }
    }

    private static func changeStep(_ rule: CoreRule, to verdict: CoreVerdict) -> @Sendable (any CoreService, RulesScope) async throws -> CoreJournalEntry? {
        let (from, text) = (rule.verdict, rule.rule)
        return { core, scope in try await core.rulesChangeVerdict(scope: scope.kind, dir: scope.dir, rule: text, from: from, to: verdict).entry }
    }

    /// One write for every control: through the core, a toast with Undo, and a reload after the write and after an Undo. A nil
    /// result ("nothing to change", `rules.setCapability` only) is a message, never a success toast. Several `works` are one change
    /// (a family's verdicts): one toast, one Undo that reverts them all (`AppEnvironment.performBatchWithUndo`).
    /// Returns false when the write was not taken (no snapshot, or one is running).
    @discardableResult
    func write(
        label: String,
        undone: String? = nil,
        scope target: RulesScope? = nil,
        clears submitted: String? = nil,
        onFailure: (@MainActor (String) -> Void)? = nil,
        _ works: [@Sendable (any CoreService, RulesScope) async throws -> CoreJournalEntry?]
    ) -> Bool {
        guard let snapshot else {
            env.toasts.show("The config folders could not be resolved.", tone: .danger)
            return false
        }
        guard !isWriting else { return false }
        isWriting = true
        let scope = target ?? snapshot.selection.scope
        env.performBatchWithUndo(
            label: label,
            undone: undone,
            via: service,
            afterChange: { [weak self] in
                guard let self else { return }
                isWriting = false
                if let submitted, draft == submitted { draft = "" }
                reload()
            },
            onFailure: { [weak self] message in
                guard let self else { return }
                isWriting = false
                if let onFailure { onFailure(message) } else { env.toasts.show(message, tone: .danger) }
                // A refused or failed write may still have changed the file (a restarted helper), so the list is read again.
                reload()
            },
            works.map { work in
                { core in
                    guard let entry = try await work(core, scope) else { throw CoreError("Nothing to change: the file already holds that.", status: 409) }
                    return entry
                }
            }
        )
        return true
    }

    @discardableResult
    private func write(
        label: String,
        scope target: RulesScope? = nil,
        clears submitted: String? = nil,
        onFailure: (@MainActor (String) -> Void)? = nil,
        _ work: @escaping @Sendable (any CoreService, RulesScope) async throws -> CoreJournalEntry?
    ) -> Bool {
        write(label: label, scope: target, clears: submitted, onFailure: onFailure, [work])
    }
}
