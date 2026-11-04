import Foundation
import Observation
import ReinsCore
import SwiftUI

/// A card's button and the panel it opens.
struct OpenPanel: Equatable, Hashable {
    let agent: AgentKind
    let panel: AgentPanel
}

/// Where leaving the panel with a draft wants to go. The footer asks first (spec, Draft and save).
enum LeaveAction: Equatable {
    case close
    case open(OpenPanel)
    case scope(RuleScope)
}

/// The Agents page's state (plan A8): the overview both cards read, the one open panel and what it shows, each panel's
/// scope remembered per agent until the app quits, the draft, the review, and every save with its Undo toast. Reads and
/// writes run off the main actor; a failed save shows an error toast and keeps the draft.
@MainActor
@Observable
final class AgentsModel {
    let env: AppEnvironment

    private(set) var overview: AgentsOverview?
    private(set) var failure: String?
    private(set) var open: OpenPanel?
    private(set) var data: PanelData?
    private(set) var leaving: LeaveAction?
    private(set) var isSaving = false
    private(set) var readsInFlight = 0
    private(set) var usageScanned = false
    var draft = AgentDraft()
    var isReviewing = false
    var panelWidth = Metrics.inspectorDefaultWidth
    var advancedWidth = Metrics.inspectorMaxWidth
    /// The hook a "Copy to the other CLI" waits to confirm.
    var pendingCopy: InventoryHook?
    var forms = AgentForms()

    // The Rules panel: Edit or Preview, and the files opened from `@path` lines (a crumb leads back).
    var isEditing = false
    private(set) var shownImport: InstructionFile?

    @ObservationIgnored private var scopes: [OpenPanel: RuleScope] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var usageResult: UsageResult?
    /// Screenshots only: the home folder `~` resolves against.
    @ObservationIgnored var home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()

    init(env: AppEnvironment) { self.env = env }

    var isSettled: Bool { overview != nil && readsInFlight == 0 && !isSaving }

    // MARK: Reading

    func start() {
        guard !started else { return }
        started = true
        reload()
        scanUsage()
    }

    func refresh() {
        guard started else { return }
        reload()
    }

    func reload() {
        guard let roots = env.roots else {
            failure = env.startupProblem ?? "The config folders could not be resolved."
            return
        }
        generation += 1
        let mine = generation
        readsInFlight += 1
        let usage = usageResult
        Task {
            let fresh = await Task.detached(priority: .userInitiated) { () -> AgentsOverview in
                var read = AgentsReader.overview(roots)
                if let usage { read.inventory = Inventory.attachUsage(read.inventory, usage: .ready(usage)) }
                return read
            }.value
            readsInFlight -= 1
            guard mine == generation else { return }
            overview = fresh
            failure = nil
            if usage != nil { usageScanned = true }
            if open != nil { loadPanel() }
        }
    }

    /// The hooks' runs come from the usage scan, which can finish before or after the first read; either way the next
    /// read attaches them.
    private func scanUsage() {
        guard let roots = env.roots else { return }
        Task {
            guard let result = try? await UsageScanner(roots: roots).scan() else { return }
            usageResult = result
            reload()
        }
    }

    // MARK: Panels and scopes

    func scope(for panel: OpenPanel) -> RuleScope { scopes[panel] ?? .global }

    var currentScope: RuleScope { open.map(scope(for:)) ?? .global }

    func scopeOptions(for panel: OpenPanel) -> [RuleScope] {
        AgentsReader.scopes(panel.agent, panel.panel, projects: overview?.projects ?? [])
    }

    /// A card button: opens its panel, or closes it when it is the open one. With a draft, the footer asks first.
    func toggle(_ panel: OpenPanel) {
        request(open == panel ? .close : .open(panel))
    }

    func close() { request(.close) }

    func select(scope: RuleScope) {
        guard scope != currentScope else { return }
        request(.scope(scope))
    }

    func request(_ action: LeaveAction) {
        if draft.isEmpty { perform(action) } else { leaving = action }
    }

    func keepEditing() { leaving = nil }

    /// Throws the draft away, then goes where leaving wanted to (or stays, from the footer's own Discard).
    func discard() {
        draft.clear()
        forms.reset()
        isEditing = false
        let action = leaving
        leaving = nil
        if let action { perform(action) } else { loadPanel() }
    }

    private func perform(_ action: LeaveAction) {
        switch action {
        case .close:
            open = nil
            data = nil
        case .open(let panel):
            open = panel
            data = nil
            loadPanel()
        case .scope(let scope):
            guard let open else { return }
            scopes[open] = scope
            loadPanel()
        }
        shownImport = nil
        isEditing = false
        forms.reset()
    }

    func loadPanel() {
        guard let roots = env.roots, let open, let overview else { return }
        let scope = scope(for: open)
        let home = home
        readsInFlight += 1
        Task {
            let fresh = await Task.detached(priority: .userInitiated) {
                AgentsReader.panel(roots, open.agent, open.panel, scope, overview: overview, home: home)
            }.value
            readsInFlight -= 1
            guard self.open == open, self.scope(for: open) == scope else { return }
            data = fresh
        }
    }

    /// Opens a file the Rules panel's file imports; `nil` goes back to the panel's own file.
    func showImport(_ path: String?) {
        guard let path, case .instructions(let base) = data else { shownImport = nil; return }
        guard let found = (shownImport ?? base).imports.first(where: { $0.raw == path }) else { return }
        shownImport = InstructionFile.read(found.url, home: home)
    }

    // MARK: Save

    var saveContext: AgentsSavePlan.Context? {
        guard let roots = env.roots, let open, let overview else { return nil }
        var context = AgentsSavePlan.Context(roots: roots, projects: overview.projects, agent: open.agent, panel: open.panel, scope: currentScope)
        if case .advanced(let masked, _) = data { context.masked = masked }
        return context
    }

    /// The Advanced editor's syntax problem; Save is blocked while it is set.
    var advancedProblem: String? {
        guard let text = draft.advancedText, let open else { return nil }
        do {
            if open.agent == .claude { try AgentsSavePlan.checkJSON(text) } else { try CodexConfigEdit.check(text) }
            return nil
        } catch {
            return AppEnvironment.message(error)
        }
    }

    func review() {
        guard !draft.isEmpty, advancedProblem == nil, !isSaving else { return }
        isReviewing = true
    }

    /// Writes the draft: one journal entry, a toast with Undo. A failure shows an error toast naming the reason, and the
    /// draft stays so nothing typed is lost.
    func save() {
        guard let context = saveContext, !draft.isEmpty else { return }
        let changes: [AgentFileChange]
        do { changes = try AgentsSavePlan.changes(draft, context) } catch {
            isReviewing = false
            env.toasts.show(AppEnvironment.message(error), tone: .danger)
            return
        }
        let label = AgentsReview.label(draft, context)
        isSaving = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Result { try AgentSave.save(context.roots, label: label, changes: changes) } }.value
            isSaving = false
            isReviewing = false
            switch outcome {
            case .success(let entry):
                draft.clear()
                forms.reset()
                isEditing = false
                if let entry {
                    env.toasts.show(label, undo: { [weak self] in self?.undo(entry, roots: context.roots, label: label) })
                } else {
                    env.toasts.show("Nothing changed in the files.")
                }
                reload()
            case .failure(let error):
                env.toasts.show(AppEnvironment.message(error), tone: .danger)
            }
        }
    }

    private func undo(_ entry: JournalEntry, roots: Roots, label: String) {
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Result { try Journal.undo(roots, id: entry.id) } }.value
            switch outcome {
            case .success: env.toasts.show("Undid \(label)")
            case .failure(let error): env.toasts.show(AppEnvironment.message(error), tone: .danger)
            }
            reload()
        }
    }

    /// "Copy to <other CLI>": its own confirmed write with a toast, outside the draft (spec, Interface: Hooks).
    func confirmCopy() {
        guard let hook = pendingCopy, let roots = env.roots else { return }
        pendingCopy = nil
        let target = hook.cli == .claude ? AgentKind.codex : .claude
        let change: AgentFileChange = target == .codex
            ? CodexHooksFile.fileChange(roots, [.add(event: hook.event, matcher: hook.matcher, command: hook.command)])
            : ClaudeSettingsEdit.fileChange(roots.claude.hookFile, [.addHook(event: hook.event, matcher: hook.matcher, command: hook.command)])
        let label = "Copied the \(hook.event) hook to \(target.name)"
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Result { try AgentSave.save(roots, label: label, changes: [change]) } }.value
            switch outcome {
            case .success(let entry?): env.toasts.show(label, undo: { [weak self] in self?.undo(entry, roots: roots, label: label) })
            case .success(nil): env.toasts.show("\(target.name) already runs that hook.")
            case .failure(let error): env.toasts.show(AppEnvironment.message(error), tone: .danger)
            }
            reload()
        }
    }

    /// Screenshots only: the draft and the panel, set without a click.
    func showForShot(_ panel: OpenPanel, scope: RuleScope = .global) {
        draft.clear()
        forms.reset()
        shownImport = nil
        isEditing = false
        leaving = nil
        scopes[panel] = scope
        open = panel
        data = nil
        loadPanel()
    }
}
