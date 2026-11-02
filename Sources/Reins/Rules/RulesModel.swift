import Foundation
import Observation
import ReinsCore

/// The Rules screen's state: the chosen scope, what was read for it, the grid confirmation, the add-rule draft and every write.
///
/// Reads and writes run off the main actor. A read discovers the projects once and keeps that list in the snapshot; a scope
/// switch reuses it, and every refresh (launch, app activation, after a write or an Undo) discovers again. A newer read
/// replaces an older one, so a slow read never overwrites a fresh one. Nothing here reads `env` values or logs rule text.
@MainActor
@Observable
final class RulesModel {
    let env: AppEnvironment

    private(set) var snapshot: RulesSnapshot?
    /// The last read could not run. With a snapshot on screen it shows as a banner over the stale data.
    private(set) var failure: String?
    private(set) var selection = RulesSelection.global
    /// Grid rows opened to show the rules and Codex keys behind them.
    private(set) var expanded: Set<Capability> = []
    /// The grid write waiting for Confirm or Cancel.
    private(set) var pending: RulesPending?
    private(set) var isWriting = false

    var draft = ""
    var draftVerdict = RuleVerdict.ask
    /// The engine's (or the shape check's) message about the rule being added, shown next to the field.
    var addError: String?
    /// Bumped by the palette's "Add a Claude Code rule"; the add row takes the focus when it changes.
    private(set) var addFocusToken = 0

    /// Screenshots only: show row actions without hover.
    var revealRowActions = false

    @ObservationIgnored weak var shell: ShellModel?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private(set) var readsInFlight = 0

    init(env: AppEnvironment) { self.env = env }

    var isLoading: Bool { snapshot == nil && failure == nil }

    /// Reads are done and nothing waits for the user. Screenshots wait for this.
    var isSettled: Bool { snapshot != nil && readsInFlight == 0 && !isWriting }

    var badge: Int? { snapshot?.globalRuleCount }

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

    /// `rediscover: false` reuses the project list of the last read (a scope switch); a refresh always discovers again.
    func reload(rediscover: Bool = true) {
        guard let roots = env.roots else {
            failure = env.startupProblem ?? "The config folders could not be resolved."
            return
        }
        generation += 1
        let mine = generation
        let wanted = selection
        let cached = rediscover ? nil : snapshot?.projectDirs
        readsInFlight += 1
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try RulesReader.read(roots: roots, selection: wanted, projects: cached) }
            }.value
            readsInFlight -= 1
            guard mine == generation else { return }
            switch outcome {
            case .success(let fresh):
                snapshot = fresh
                selection = fresh.selection
                failure = nil
            case .failure(let error):
                failure = AppEnvironment.message(error)
            }
        }
    }

    // MARK: Choices

    func select(_ choice: RulesSelection) {
        guard choice != selection else { return }
        selection = choice
        pending = nil
        addError = nil
        reload(rediscover: false)
    }

    func selectProject(_ dir: String?) { select(RulesSelection(dir: dir, file: selection.file)) }

    func selectFile(_ file: RulesFileKind) {
        guard selection.dir != nil else { return }
        select(RulesSelection(dir: selection.dir, file: file))
    }

    func toggle(_ capability: Capability) {
        if expanded.contains(capability) { expanded.remove(capability) } else { expanded.insert(capability) }
    }

    func setExpanded(_ capabilities: Set<Capability>) { expanded = capabilities }

    /// From the palette: show a scope and bring the tab forward.
    func jump(to choice: RulesSelection) {
        select(choice)
        shell?.select(RulesTab.tabID)
    }

    func focusAddRule() {
        shell?.select(RulesTab.tabID)
        addFocusToken += 1
    }

    // MARK: Grid writes

    /// A click on Allow, Ask or Deny. Nothing is written: this asks the engine what the write would replace, then opens the confirmation.
    func requestSet(_ capability: Capability, to verdict: RuleVerdict) {
        guard let snapshot, let roots = env.roots, pending == nil else { return }
        guard let cell = snapshot.grid.first(where: { $0.capability == capability }), snapshot.isEditable(cell),
              cell.state != CapabilityState(rawValue: verdict.rawValue) else { return }
        let scope = snapshot.selection.scope
        let store = snapshot.store(roots: roots)
        let title = snapshot.title
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try RulesScopes.scrubbed(store: store, scope: scope) { try store.previewSetCapability(scope: scope, capability: capability, verdict: verdict) } }
            }.value
            switch outcome {
            case .success(let preview): pending = RulesPending(preview: preview, scopeTitle: title)
            case .failure(let error): env.toasts.show(AppEnvironment.message(error), tone: .danger)
            }
        }
    }

    func cancelPending() { pending = nil }

    /// Writes what the confirmation listed, through `performWithUndo`. A write that would change nothing shows no success toast.
    func confirmPending() {
        guard let change = pending, !isWriting else { return }
        pending = nil
        if change.isNoOp {
            env.toasts.show("\(change.capability.label) already reads \(RulesWording.title(change.verdict)) here.")
            return
        }
        let (capability, verdict) = (change.capability, change.verdict)
        write(label: RulesWording.setLabel(capability, verdict)) { store, scope in
            try store.setCapability(scope: scope, capability: capability, verdict: verdict)
        }
    }

    // MARK: Rule writes

    /// Adds the draft under `draftVerdict`. The shape is checked first; the engine's 400, 404 and 409 messages show next to the field.
    func submitDraft() {
        let text = draft
        if let problem = RulesScopes.shapeError(text) {
            addError = problem
            return
        }
        addError = nil
        let verdict = draftVerdict
        let rule = text.trimmingCharacters(in: .whitespacesAndNewlines)
        write(
            label: "Added \(rule) to \(RulesWording.groupTitle(verdict))",
            clears: text,
            onFailure: { [weak self] in self?.addError = $0 }
        ) { store, scope in
            try store.addRule(scope: scope, verdict: verdict, rule: rule)
        }
    }

    func remove(_ item: RuleItem) {
        let (verdict, rule) = (item.verdict, item.rule)
        write(label: "Removed \(rule) from \(RulesWording.groupTitle(verdict))") { store, scope in
            try store.removeRule(scope: scope, verdict: verdict, rule: rule)
        }
    }

    func move(_ item: RuleItem, to verdict: RuleVerdict) {
        let (from, rule) = (item.verdict, item.rule)
        write(label: "Moved \(rule) from \(RulesWording.groupTitle(from)) to \(RulesWording.groupTitle(verdict))") { store, scope in
            try store.changeVerdict(scope: scope, rule: rule, from: from, to: verdict)
        }
    }

    /// One write for every control: the scope's store (with the cached project list), a scrubbed error, a toast with Undo,
    /// and a reload after the write and after an Undo. A nil result from the engine ("nothing to change") is a message,
    /// never a success toast.
    private func write(
        label: String,
        clears submitted: String? = nil,
        onFailure: (@MainActor (String) -> Void)? = nil,
        _ work: @escaping @Sendable (RulesStore, RuleScope) throws -> JournalEntry?
    ) {
        guard let snapshot, let roots = env.roots else {
            env.toasts.show(env.startupProblem ?? "The config folders could not be resolved.", tone: .danger)
            return
        }
        guard !isWriting else { return }
        isWriting = true
        let scope = snapshot.selection.scope
        let store = snapshot.store(roots: roots)
        env.performWithUndo(
            label: label,
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
            }
        ) {
            try RulesScopes.scrubbed(store: store, scope: scope) {
                guard let entry = try work(store, scope) else { throw ReinsError("Nothing to change: the file already holds that.", status: 409) }
                return entry
            }
        }
    }
}
