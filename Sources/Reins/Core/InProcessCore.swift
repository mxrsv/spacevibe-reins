import Foundation
import ReinsCore

/// `CoreService` over the Swift engine (`ReinsCore`), for as long as a screen has not cut over to the Go core (plan S.1).
/// It is the only file under `Sources/Reins/Core` that imports ReinsCore: engine types go in, DTOs come out, and no
/// screen sees the difference. Behavior is the engine's own, including what the models did around it today:
/// Rules errors and problems come back with the settings file's path replaced by the scope's label.
///
/// Not an actor: a blocking engine call must not queue behind another. The state the core owns in a process (the discovered
/// projects) sits behind a lock.
///
/// Activity, Stop (S.3), Limits (S.4) and Loadout (reads S.5, writes and the journal S.6) have cut over: they live in the Go core only and this adapter no longer serves them. The Rules writes still record journal
/// entries here; their Undo runs on the Go core (`AppEnvironment.performWithUndo`), which reads the same journal.
///
/// Two things differ from the Go core, none a behavior change for today's screens:
/// - `rulesSnapshot` with `refreshProjects` discovers the projects again, and every other rules call discovers once when the
///   list is empty.
/// - The Go-only members (`notReadable`, `globalNotReadable`, `skippedLines`, `unreadable`, `folderNotReadable`) are
///   false or 0: the engine has no source for them.
final class InProcessCore: CoreService, @unchecked Sendable {
    /// What `initialize` reports as the version: this engine has none of its own.
    static let version = "in-process"
    /// Every method this adapter still serves; the Go core serves these and the ones that cut over.
    static let methods = [
        "initialize", "rules.add", "rules.changeVerdict", "rules.check", "rules.preview", "rules.remove", "rules.setCapability",
        "rules.snapshot",
    ]

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var projects: [String] = []

        func knownProjects() -> [String] { lock.withLock { projects } }
        func setProjects(_ dirs: [String]) { lock.withLock { projects = dirs } }
    }

    private let roots: Roots?
    private let startupProblem: String
    private let state = State()

    /// - Parameters:
    ///   - roots: nil when the config folders could not be resolved; every method then fails with `startupProblem`.
    init(roots: Roots?, startupProblem: String? = nil) {
        self.roots = roots
        self.startupProblem = startupProblem ?? "The config folders could not be resolved."
    }

    /// The core the app runs on for the screens that have not cut over, and the startup problem when the config folders could
    /// not be resolved (every call then fails with it). `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` come from
    /// `environment`.
    static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> (core: InProcessCore, startupProblem: String?) {
        var problem: String?
        var roots: Roots?
        do { roots = try Roots.resolve(env: environment) } catch { problem = String(describing: error) }
        return (InProcessCore(roots: roots, startupProblem: problem), problem)
    }

    // MARK: Plumbing

    private func requireRoots() throws -> Roots {
        guard let roots else { throw CoreError(self.startupProblem, status: 500) }
        return roots
    }

    /// An engine error as the core reports it. A cancelled call stays a `CancellationError`.
    private static func coreError(_ error: Error) -> Error {
        switch error {
        case is CancellationError, is CoreError: return error
        case let error as ReinsError: return CoreError(error.message, status: error.status)
        default: return CoreError(CoreError.unexpectedMessage, status: 500)
        }
    }

    /// Runs blocking engine work off the caller's executor. A call cancelled before it starts never runs; one that has
    /// started finishes, so a cancel never leaves a half-applied change.
    private func run<T: Sendable>(_ priority: TaskPriority = .userInitiated, _ work: @escaping @Sendable (Roots) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let roots = try requireRoots()
        do {
            return try await Task.detached(priority: priority) { try work(roots) }.value
        } catch {
            throw Self.coreError(error)
        }
    }

    /// The same case in a DTO enum of the same raw values.
    private static func same<From: RawRepresentable, To: RawRepresentable>(_ value: From, as _: To.Type) -> To where From.RawValue == String, To.RawValue == String {
        guard let converted = To(rawValue: value.rawValue) else { preconditionFailure("\(To.self) has no case \(value.rawValue)") }
        return converted
    }

    private static func entry(_ entry: JournalEntry) -> CoreJournalEntry {
        CoreJournalEntry(id: entry.id, at: entry.at, label: entry.label, undone: entry.undone, count: entry.ops.count)
    }

    // MARK: Handshake

    func initialize() async throws -> CoreInitializeResult {
        CoreInitializeResult(
            protocolVersion: CoreProtocol.version,
            core: .init(name: ReinsCore.name, version: Self.version),
            identity: .init(envPrefix: ReinsCore.envPrefix, dataDir: ReinsCore.dataFolderName),
            methods: Self.methods
        )
    }

    // MARK: Served by the Go core only (S.3 Activity and Stop, S.4 Limits, S.5 and S.6 Loadout)

    /// The screens that cut over have no path here: `AppEnvironment.goCore` is their only service. These exist because
    /// `CoreService` lists them; S.8 deletes this file.
    func activityRead() async throws -> CoreActivityReport { throw Self.goCoreOnly }
    func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> { AsyncThrowingStream { $0.finish(throwing: Self.goCoreOnly) } }
    func activityStop(cli: CoreCLI, id: String) async throws -> CoreStopResult { throw Self.goCoreOnly }
    func limitsRead() async throws -> CoreLimitsResult { throw Self.goCoreOnly }
    func inventoryRead() async throws -> CoreInventorySnapshot { throw Self.goCoreOnly }
    func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult { throw Self.goCoreOnly }
    func loadoutRows() async throws -> CoreLoadoutRows { throw Self.goCoreOnly }
    func loadoutCopyToOther(id: String) async throws -> CoreEntryResult { throw Self.goCoreOnly }
    func loadoutRemoveItem(id: String) async throws -> CoreEntryResult { throw Self.goCoreOnly }
    func loadoutRemoveDeadHooks(cli: CoreCLI) async throws -> CoreEntryResult { throw Self.goCoreOnly }
    func journalUndo(id: String) async throws -> CoreUndoResult { throw Self.goCoreOnly }
    func journalHistory() async throws -> CoreJournalHistory { throw Self.goCoreOnly }

    private static let goCoreOnly = CoreError("This is served by the Go core only.", status: 500)

    // MARK: Rules

    func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot {
        let asked = try Self.ruleScope(scope, dir)
        let dirs = try await projectList(refresh: refreshProjects)
        return try await run { roots in try Self.readRules(roots: roots, asked: asked, projects: dirs) }
    }

    func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview {
        let target = try Self.ruleScope(scope, dir)
        let store = try await rulesStore()
        return try await run { _ in
            let preview = try Self.scrubbed(store: store, scope: target) {
                try store.previewSetCapability(scope: target, capability: Self.same(capability, as: Capability.self), verdict: Self.same(verdict, as: RuleVerdict.self))
            }
            return Self.preview(preview)
        }
    }

    func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult {
        let target = try Self.ruleScope(scope, dir)
        let store = try await rulesStore()
        return try await run { _ in
            let entry = try Self.scrubbed(store: store, scope: target) {
                try store.setCapability(scope: target, capability: Self.same(capability, as: Capability.self), verdict: Self.same(verdict, as: RuleVerdict.self))
            }
            return CoreSetCapabilityResult(entry: entry.map(Self.entry))
        }
    }

    func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult {
        try await ruleWrite(scope, dir) { store, target in
            try store.addRule(scope: target, verdict: Self.same(verdict, as: RuleVerdict.self), rule: rule)
        }
    }

    func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult {
        try await ruleWrite(scope, dir) { store, target in
            try store.removeRule(scope: target, verdict: Self.same(verdict, as: RuleVerdict.self), rule: rule)
        }
    }

    func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult {
        try await ruleWrite(scope, dir) { store, target in
            try store.changeVerdict(scope: target, rule: rule, from: Self.same(from, as: RuleVerdict.self), to: Self.same(to, as: RuleVerdict.self))
        }
    }

    func rulesCheck(rule: String) async throws -> CoreRuleCheck {
        try Task.checkCancellation()
        _ = try requireRoots()
        let problem = Self.shapeError(rule)
        return CoreRuleCheck(valid: problem == nil, message: problem)
    }

    /// Reads the asked scope, the global rule count and the Codex permissions. A project the discovered list does not hold
    /// reads as global, as the Go core does; the DTO's `scope` and `dir` say what was read.
    private static func readRules(roots: Roots, asked: RuleScope, projects dirs: [String]) throws -> CoreRulesSnapshot {
        let store = RulesStore(roots: roots, projects: { dirs })
        let scope: RuleScope = asked.dir.map { dirs.contains($0) } ?? true ? asked : .global
        return try scrubbed(store: store, scope: scope) {
            let global = try store.listRules([.global])
            let listing = scope == .global ? global : try store.listRules([scope])
            let file = try store.file(for: scope)
            return CoreRulesSnapshot(
                projectDirs: dirs, globalRuleCount: global.rules.count,
                scope: CoreRuleScope(rawValue: scope.kind) ?? .global, dir: scope.dir,
                fileLabel: scope.fileLabel, exists: FileManager.default.fileExists(atPath: file.path),
                problems: listing.problems.map { scrub($0, path: file.path, label: scope.fileLabel) }, rules: listing.rules.map(rule),
                grid: Rules.capabilityGrid(listing.rules).map { cell in
                    CoreCapabilityCell(
                        capability: same(cell.capability, as: CoreCapability.self), label: cell.label,
                        state: same(cell.state, as: CoreCapabilityState.self), editable: cell.editable, rules: cell.rules.map(rule)
                    )
                },
                codex: codex(CodexPermissions.read(roots: roots)), notReadable: false, globalNotReadable: false
            )
        }
    }

    /// The engine's messages name the absolute settings file; the core's callers only see the scope's short label.
    static func scrub(_ text: String, path: String, label: String) -> String {
        var out = text.replacingOccurrences(of: path, with: label)
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path { out = out.replacingOccurrences(of: resolved, with: label) }
        return out
    }

    /// Runs `work` and rethrows a `ReinsError` with the settings file's absolute path replaced by its label (status kept).
    /// Every rules read and write goes through it, because the engine's 409 messages name the file.
    private static func scrubbed<T>(store: RulesStore, scope: RuleScope, _ work: () throws -> T) throws -> T {
        do { return try work() } catch let error as ReinsError {
            guard let path = try? store.file(for: scope).path else { throw error }
            throw ReinsError(scrub(error.message, path: path, label: scope.fileLabel), status: error.status)
        }
    }

    /// The live check of a rule before a write: the engine stays the authority (it also refuses a duplicate with a 409).
    private static func shapeError(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a rule such as Bash(npm test *)." }
        guard trimmed.utf16.count <= Rules.maxRuleLength, !trimmed.contains(where: \.isNewline), Rules.parseRule(trimmed) != nil else {
            return "That is not a valid rule. Use Tool or Tool(pattern) on one line."
        }
        return nil
    }

    private func ruleWrite(_ scope: CoreRuleScope, _ dir: String?, _ write: @escaping @Sendable (RulesStore, RuleScope) throws -> JournalEntry) async throws -> CoreEntryResult {
        let target = try Self.ruleScope(scope, dir)
        let store = try await rulesStore()
        return try await run { _ in
            CoreEntryResult(entry: Self.entry(try Self.scrubbed(store: store, scope: target) { try write(store, target) }))
        }
    }

    /// A global scope takes no folder; a project or local scope takes an absolute one (the engine then checks that
    /// discovery found it).
    private static func ruleScope(_ kind: CoreRuleScope, _ dir: String?) throws -> RuleScope {
        switch kind {
        case .global:
            if let dir, !dir.isEmpty { throw CoreError("A global scope takes no folder.") }
            return .global
        case .project, .local:
            guard let dir, dir.hasPrefix("/") else { throw CoreError("A project scope needs an absolute folder.") }
            return kind == .project ? .project(dir) : .local(dir)
        }
    }

    /// The discovered projects of this process. Discovery runs again on `refresh`, and once when the list is empty.
    private func projectList(refresh: Bool) async throws -> [String] {
        let known = state.knownProjects()
        if !refresh, !known.isEmpty { return known }
        let found = try await run { roots in Inventory.discoverProjects(roots: roots) }
        state.setProjects(found)
        return found
    }

    private func rulesStore() async throws -> RulesStore {
        let dirs = try await projectList(refresh: false)
        return RulesStore(roots: try requireRoots(), projects: { dirs })
    }

    // MARK: Engine type to DTO

    private static func rule(_ item: RuleItem) -> CoreRule {
        CoreRule(
            id: item.id, scope: CoreRuleScope(rawValue: item.scope.kind) ?? .global,
            dir: item.scope.dir, file: item.file, verdict: same(item.verdict, as: CoreVerdict.self), rule: item.rule,
            tool: item.tool, specifier: item.specifier
        )
    }

    private static func preview(_ preview: CapabilityPreview) -> CoreCapabilityPreview {
        CoreCapabilityPreview(
            capability: same(preview.capability, as: CoreCapability.self), verdict: same(preview.verdict, as: CoreVerdict.self),
            scopeLabel: preview.scopeLabel, current: same(preview.current, as: CoreCapabilityState.self),
            resulting: same(preview.resulting, as: CoreCapabilityState.self),
            replaces: preview.replaces.map { CoreVerdictRule(verdict: same($0.verdict, as: CoreVerdict.self), rule: $0.rule) },
            writes: preview.writes.map { CoreVerdictRule(verdict: same($0.verdict, as: CoreVerdict.self), rule: $0.rule) }
        )
    }

    private static func codex(_ codex: CodexPermissions) -> CoreCodexPermissions {
        func flags(_ members: [JSONMember]) -> [CoreFlag] {
            members.compactMap { member in
                switch member.value {
                case .bool(let value): return CoreFlag(key: member.key, value: .bool(value))
                case .string(let value): return CoreFlag(key: member.key, value: .string(value))
                case .number(let text): return Double(text).map { CoreFlag(key: member.key, value: .number($0)) }
                default: return nil
                }
            }
        }
        let policy: CoreApprovalPolicy? = codex.approvalPolicy.map {
            switch $0 {
            case .mode(let mode): return .mode(mode)
            case .granular(let members): return .granular(flags(members))
            }
        }
        return CoreCodexPermissions(
            present: codex.present, model: same(codex.model, as: CoreCodexModel.self), unrestricted: codex.unrestricted,
            warnings: codex.warnings, approvalPolicy: policy, sandboxMode: codex.sandboxMode,
            sandboxWorkspaceWrite: codex.sandboxWorkspaceWrite.map { CoreWorkspaceWrite(networkAccess: $0.networkAccess, writableRoots: $0.writableRoots) },
            defaultPermissions: codex.defaultPermissions, approvalsReviewer: codex.approvalsReviewer,
            profiles: codex.profiles.map {
                CoreCodexProfile(name: $0.name, filesystemEntries: $0.filesystemEntries, networkEntries: $0.networkEntries, networkFlags: flags($0.networkFlags))
            },
            projects: codex.projects.map { CoreCodexProject(path: $0.path, trustLevel: $0.trustLevel) },
            rules: CoreCodexRulesSummary(
                files: codex.rules.files, allow: codex.rules.allow, prompt: codex.rules.prompt, forbidden: codex.rules.forbidden,
                other: codex.rules.other, unreadable: 0, folderNotReadable: false
            ),
            notReadable: false, skippedLines: 0
        )
    }
}

extension AppEnvironment {
    /// An environment over an in-process core for these roots, for the tests and dev tools that build their own (the app
    /// itself starts from `AppEnvironment.live`). Without roots the core refuses every call with `startupProblem`.
    convenience init(
        roots: Roots?, startupProblem: String? = nil, toasts: ToastCenter? = nil, core: (any CoreService)? = nil,
        routing: CoreRouting = CoreRouting(), makeCoreClient: @escaping () -> any CoreService = { CoreClient() }
    ) {
        let problem = roots == nil ? (startupProblem ?? "The config folders could not be resolved.") : startupProblem
        self.init(
            startupProblem: problem, toasts: toasts, core: core ?? InProcessCore(roots: roots, startupProblem: problem),
            routing: routing, makeCoreClient: makeCoreClient
        )
    }
}
