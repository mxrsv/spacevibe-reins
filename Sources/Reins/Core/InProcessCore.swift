import Foundation
import ReinsCore

/// `CoreService` over the Swift engine (`ReinsCore`), for as long as a screen has not cut over to the Go core (plan S.1).
/// It is the only file under `Sources/Reins/Core` that imports ReinsCore: engine types go in, DTOs come out, and no
/// screen sees the difference. Behavior is the engine's own, including what the models did around it today:
/// Rules errors and problems come back with the settings file's path replaced by the scope's label, and
/// `loadoutRows` returns the problem sentences unshortened (the shell shortens them).
///
/// Not an actor: a blocking inventory read must not queue behind a usage scan. The state the core owns in a process
/// (the discovered projects, the last scan, whether one runs) sits behind a lock.
///
/// Three things differ from the Go core, none a behavior change for today's screens:
/// - `inventoryRead` does not refresh the discovered-project list (the engine's read does not expose it); `rulesSnapshot`
///   with `refreshProjects` does, and every other rules call discovers once when the list is empty.
/// - `activityStop` cannot answer 409 "could not be verified": the engine has no such state.
/// - The Go-only members (`notReadable`, `globalNotReadable`, `skippedLines`, `unreadable`, `folderNotReadable`) are
///   false or 0: the engine has no source for them.
final class InProcessCore: CoreService, @unchecked Sendable {
    /// The poll period of `activitySubscribe`, as the Go core's.
    static let activityPoll: Duration = .seconds(3)
    /// What `initialize` reports as the version: this engine has none of its own.
    static let version = "in-process"
    /// Every method the core serves; `activity.unsubscribe` is the end of the `activitySubscribe` stream.
    static let methods = [
        "activity.read", "activity.stop", "activity.subscribe", "activity.unsubscribe", "initialize", "inventory.read",
        "journal.history", "journal.undo", "limits.read", "loadout.copyToOther", "loadout.removeDeadHooks", "loadout.removeItem",
        "loadout.rows", "rules.add", "rules.changeVerdict", "rules.check", "rules.preview", "rules.remove", "rules.setCapability",
        "rules.snapshot", "usage.scan",
    ]

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var usage: UsageResult?
        private var scanning = false
        private var projects: [String] = []

        var lastUsage: UsageResult? { lock.withLock { usage } }
        func setUsage(_ result: UsageResult) { lock.withLock { usage = result } }
        /// False when a scan already runs.
        func beginScan() -> Bool { lock.withLock { if scanning { return false }; scanning = true; return true } }
        func endScan() { lock.withLock { scanning = false } }
        func knownProjects() -> [String] { lock.withLock { projects } }
        func setProjects(_ dirs: [String]) { lock.withLock { projects = dirs } }
    }

    private let roots: Roots?
    private let startupProblem: String
    private let proc: any ProcessAdapter
    private let engine = ActivityEngine()
    private let state = State()

    /// - Parameters:
    ///   - roots: nil when the config folders could not be resolved; every method then fails with `startupProblem`.
    ///   - proc: how Activity looks at, and stops, processes.
    init(roots: Roots?, startupProblem: String? = nil, proc: any ProcessAdapter) {
        self.roots = roots
        self.startupProblem = startupProblem ?? "The config folders could not be resolved."
        self.proc = proc
    }

    /// The core the app runs on, and the startup problem when the config folders could not be resolved (every call then fails
    /// with it). `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` come from `environment`. Under `SPACEVIBE_TEST=1`
    /// the process adapter is never the real one: it replays the file named by `SPACEVIBE_PROC_FIXTURE`, or an empty list.
    static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> (core: InProcessCore, startupProblem: String?) {
        var problems: [String] = []
        var roots: Roots?
        do { roots = try Roots.resolve(env: environment) } catch { problems.append(String(describing: error)) }
        let proc: any ProcessAdapter
        if environment[ReinsCore.env("TEST")] == "1" {
            if let path = environment[ReinsCore.env("PROC_FIXTURE")], !path.isEmpty {
                do { proc = try FixtureProcessAdapter.load(path: path) } catch {
                    problems.append(String(describing: error))
                    proc = FixtureProcessAdapter.empty
                }
            } else {
                proc = FixtureProcessAdapter.empty
            }
        } else {
            proc = SystemProcessAdapter()
        }
        let problem = problems.isEmpty ? nil : problems.joined(separator: " ")
        return (InProcessCore(roots: roots, startupProblem: problem, proc: proc), problem)
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

    /// The engine's Codable types write the core's JSON (the goldens hold them to it), so the DTO is read from it.
    private static func bridge<DTO: Decodable>(_ value: some Encodable) throws -> DTO {
        do {
            return try JSONDecoder().decode(DTO.self, from: JSONEncoder().encode(value))
        } catch {
            throw CoreError(CoreError.unexpectedMessage, status: 500)
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

    // MARK: Inventory, usage, loadout

    func inventoryRead() async throws -> CoreInventorySnapshot {
        try await run { roots in try Self.bridge(Inventory.read(roots: roots)) }
    }

    func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult {
        try Task.checkCancellation()
        let roots = try requireRoots()
        guard state.beginScan() else { throw CoreError("A usage scan is already running.", status: 409) }
        defer { state.endScan() }
        do {
            let forward: (@Sendable (UsageProgress) -> Void)? = progress.map { report in { @Sendable (p: UsageProgress) in report(CoreUsageProgress(done: p.done, total: p.total)) } }
            let result = try await UsageScanner(roots: roots).scan(progress: forward)
            state.setUsage(result)
            return try Self.bridge(result)
        } catch {
            throw Self.coreError(error)
        }
    }

    func loadoutRows() async throws -> CoreLoadoutRows {
        let usage = state.lastUsage
        return try await run { roots in
            let input = usage.map(UsageInput.ready) ?? .scanning
            let attached = Inventory.attachUsage(Inventory.read(roots: roots), usage: input)
            let snapshot: CoreInventorySnapshot = try Self.bridge(attached)

            let projects = Set(attached.items.compactMap(\.project) + attached.hooks.compactMap(\.project)).sorted()
            var counts: [String: CoreFilterCounts] = [:]
            for scope in ["global"] + projects {
                let project: String? = scope == "global" ? nil : scope
                let filtered = Inventory.filterCounts(
                    items: attached.items.filter { $0.project == project },
                    hooks: attached.hooks.filter { $0.project == project }
                )
                counts[scope] = try Self.bridge(filtered)
            }

            var rows: [String: [FilterRow]] = [:]
            for item in attached.items { rows[item.key, default: []].append(FilterRow(item)) }
            for hook in attached.hooks { rows[hook.key, default: []].append(FilterRow(hook)) }
            let flags = rows.mapValues { group -> CoreRowFlags in
                let c = Inventory.filterCounts(group)
                return CoreRowFlags(one: c.only.claude + c.only.codex > 0, neverRan: c.neverRan > 0, dead: c.dead > 0)
            }

            return CoreLoadoutRows(
                usage: usage == nil ? .scanning : .ready, items: snapshot.items, hooks: snapshot.hooks, problems: snapshot.problems,
                events: snapshot.events, roots: snapshot.roots, countsByScope: counts, rowFlags: flags
            )
        }
    }

    // MARK: Activity

    func activityRead() async throws -> CoreActivityReport {
        try Task.checkCancellation()
        let roots = try requireRoots()
        return Self.activity(await engine.readActivity(roots: roots, now: Date(), proc: proc))
    }

    func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var last: CoreActivityReport?
                    while !Task.isCancelled {
                        let report = try await self.activityRead()
                        // A report replaces the last whole; one equal to the last is not sent.
                        if report != last { continuation.yield(report) }
                        last = report
                        try await Task.sleep(for: Self.activityPoll)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func activityStop(cli: CoreCLI, id: String) async throws -> CoreStopResult {
        try Task.checkCancellation()
        let roots = try requireRoots()
        do {
            let result = try await stopSession(roots: roots, cli: Self.engineCLI(cli), id: id, proc: proc)
            return CoreStopResult(exited: result.exited)
        } catch {
            throw Self.coreError(error)
        }
    }

    // MARK: Loadout writes and the journal

    func loadoutCopyToOther(id: String) async throws -> CoreEntryResult {
        try await run { roots in CoreEntryResult(entry: Self.entry(try Mutate.copyToOther(roots: roots, id: id))) }
    }

    func loadoutRemoveItem(id: String) async throws -> CoreEntryResult {
        try await run { roots in CoreEntryResult(entry: Self.entry(try Mutate.removeItem(roots: roots, id: id))) }
    }

    func loadoutRemoveDeadHooks(cli: CoreCLI) async throws -> CoreEntryResult {
        return try await run { roots in CoreEntryResult(entry: Self.entry(try Mutate.removeDeadHooks(roots: roots, cli: Self.engineCLI(cli)))) }
    }

    func journalUndo(id: String) async throws -> CoreUndoResult {
        try await run { roots in CoreUndoResult(label: try Journal.undo(roots, id: id)) }
    }

    func journalHistory() async throws -> CoreJournalHistory {
        try await run { roots in
            CoreJournalHistory(entries: Journal.history(roots).map {
                CoreJournalEntry(id: $0.id, at: $0.at, label: $0.label, undone: $0.undone, count: $0.count)
            })
        }
    }

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

    // MARK: Limits

    func limitsRead() async throws -> CoreLimitsResult {
        try await run(.utility) { roots in
            let now = Date()
            return CoreLimitsResult(limits: Limits.read(roots, now: now).map { Self.limits($0, now: now) })
        }
    }

    // MARK: Engine type to DTO

    /// The engine's own CLI type, named by the call it is passed to: the app's `InventoryCLI` is the DTO's, so this file cannot
    /// spell the engine's (and `ReinsCore.InventoryCLI` does not parse: the module has a type of its own name).
    private static func engineCLI<Engine: RawRepresentable>(_ cli: CoreCLI) -> Engine where Engine.RawValue == String {
        guard let converted = Engine(rawValue: cli.rawValue) else { preconditionFailure("\(Engine.self) has no case \(cli.rawValue)") }
        return converted
    }

    private static func activity(_ report: ActivityReport) -> CoreActivityReport {
        CoreActivityReport(
            sessions: report.sessions.map { s in
                CoreActivitySession(
                    cli: same(s.cli, as: CoreCLI.self), id: s.id, title: s.title, project: s.project, pid: s.pid,
                    state: same(s.state, as: CoreSessionState.self), stateReason: s.stateReason, reasonCode: s.reasonCode?.rawValue,
                    currentTool: s.currentTool.map { CoreActivityTool(name: $0.name, target: $0.target) },
                    ageMs: s.ageMs, lastWriteAgoMs: s.lastWriteAgoMs,
                    cost: s.cost.map { CoreActivityCost(usd: $0.usd, estimated: $0.estimated) }, costNote: s.costNote
                )
            },
            failures: report.failures.map { f in
                CoreActivityFailure(
                    kind: same(f.kind, as: CoreFailureKind.self), cli: same(f.cli, as: CoreCLI.self), key: f.key, title: f.title,
                    count: f.count, exit: f.exit, reason: f.reason, projects: f.projects, sessions: f.sessions, first: f.first,
                    last: f.last, laterPass: f.laterPass, hook: f.hook.map { CoreActivityHookRef(hash: $0.hash, event: $0.event) }
                )
            },
            files: report.files.map { f in
                CoreActivityFile(path: f.path, label: f.label, edits: f.edits, sessions: f.sessions, last: f.last, clis: f.clis.map { same($0, as: CoreCLI.self) }, projects: f.projects)
            },
            unmeasurable: report.unmeasurable.map { CoreActivityLimit(cli: same($0.cli, as: CoreCLI.self), code: $0.code.rawValue, text: $0.text) },
            stats: CoreActivityStats(logs: report.stats.logs, truncated: report.stats.truncated)
        )
    }

    private static func limits(_ entry: CLILimits, now: Date) -> CoreLimitsEntry {
        var state = CoreLimitsState.notInstalled
        var at: Double?
        var windows: [CoreLimitWindow] = []
        switch entry.state {
        case .measured(let taken, let found):
            state = .measured
            at = taken.timeIntervalSince1970
            windows = found.map { w in
                CoreLimitWindow(
                    id: w.id, minutes: w.minutes, scope: w.scope, usedPercent: w.usedPercent,
                    resetsAt: w.resetsAt.timeIntervalSince1970, active: w.active, current: w.isCurrent(at: now)
                )
            }
        case .notRecorded: state = .notRecorded
        case .unreadable: state = .unreadable
        case .notMeasurable: state = .notMeasurable
        case .notInstalled: state = .notInstalled
        }
        return CoreLimitsEntry(
            cli: same(entry.cli, as: CoreLimitsCLI.self), state: state, plan: entry.plan,
            source: entry.source.map { $0 == .claudeCache ? CoreLimitsSource.claudeCache : .claudeStatusline }, at: at, windows: windows
        )
    }

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
        roots: Roots?, startupProblem: String? = nil, proc: any ProcessAdapter, toasts: ToastCenter? = nil, core: (any CoreService)? = nil,
        routing: CoreRouting = CoreRouting(), makeCoreClient: @escaping () -> any CoreService = { CoreClient() }
    ) {
        let problem = roots == nil ? (startupProblem ?? "The config folders could not be resolved.") : startupProblem
        self.init(
            startupProblem: problem, toasts: toasts, core: core ?? InProcessCore(roots: roots, startupProblem: problem, proc: proc),
            routing: routing, makeCoreClient: makeCoreClient
        )
    }
}
