import Foundation
import ReinsCore

/// What is left of the adapter over the Swift engine (`ReinsCore`) now that every screen has cut over to the Go core (plan S.1, S.3 to S.7):
/// the handshake the dev tools and tests read, `live` (which resolves the config folders to produce the startup problem a screen
/// shows), and a refusal for each `CoreService` method, because the protocol lists them. S.8 deletes this file together with the engine.
/// It is the only file under `Sources/Reins/Core` that imports ReinsCore.
final class InProcessCore: CoreService, @unchecked Sendable {
    /// What `initialize` reports as the version: this engine has none of its own.
    static let version = "in-process"
    /// Every method this adapter still serves; the Go core serves it and everything else.
    static let methods = ["initialize"]

    /// Kept so the call sites that build one (`AppEnvironment(roots:)`, `live`) stay as they are until S.8; the adapter reads nothing.
    init(roots: Roots?, startupProblem: String? = nil) {}

    /// The adapter the app starts with, and the startup problem when the config folders could not be resolved. `HOME`,
    /// `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` come from `environment`.
    static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> (core: InProcessCore, startupProblem: String?) {
        var problem: String?
        var roots: Roots?
        do { roots = try Roots.resolve(env: environment) } catch { problem = String(describing: error) }
        return (InProcessCore(roots: roots, startupProblem: problem), problem)
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

    // MARK: Served by the Go core only

    /// Every screen is cut over: `AppEnvironment.goCore` is the only service. These exist because `CoreService` lists them;
    /// S.8 deletes this file.
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
    func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot { throw Self.goCoreOnly }
    func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview { throw Self.goCoreOnly }
    func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult { throw Self.goCoreOnly }
    func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw Self.goCoreOnly }
    func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw Self.goCoreOnly }
    func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult { throw Self.goCoreOnly }
    func rulesCheck(rule: String) async throws -> CoreRuleCheck { throw Self.goCoreOnly }

    private static let goCoreOnly = CoreError("This is served by the Go core only.", status: 500)
}

extension AppEnvironment {
    /// An environment over the in-process stub for these roots, for the tests and dev tools that build their own (the app
    /// itself starts from `AppEnvironment.live`). `startupProblem` is what a screen shows when the config folders could not be resolved.
    convenience init(
        roots: Roots?, startupProblem: String? = nil, toasts: ToastCenter? = nil, core: (any CoreService)? = nil,
        makeCoreClient: @escaping () -> any CoreService = { CoreClient() }
    ) {
        let problem = roots == nil ? (startupProblem ?? "The config folders could not be resolved.") : startupProblem
        self.init(startupProblem: problem, toasts: toasts, core: core ?? InProcessCore(roots: roots, startupProblem: problem), makeCoreClient: makeCoreClient)
    }
}
