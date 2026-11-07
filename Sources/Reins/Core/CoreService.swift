import Foundation

/// The seam between the screens and the engine (plan S.1; docs/internals/core-protocol.md). One method per RPC method,
/// taking and returning the DTOs of `CoreTypes*.swift`. `InProcessCore` backs it today with `ReinsCore`; `CoreClient`
/// (S.2) backs it with the Go core over stdio. Screens must not tell the two apart.
///
/// Errors: a refusal from the engine is a `CoreError` (`status`, safe `message`). A cancelled call throws
/// `CancellationError`, which the wire reports as -32800. Every method fails with a `CoreError` of status 500 and the
/// startup sentence when the config folders could not be resolved.
protocol CoreService: Sendable {
    /// `initialize`: the core's name, version, env prefix and data folder (SV12).
    func initialize() async throws -> CoreInitializeResult

    func inventoryRead() async throws -> CoreInventorySnapshot
    /// `progress` is called after every 20 files and once at the end, from a background executor. A second scan while one
    /// runs is a 409. The result is kept as the usage state `loadoutRows` attaches.
    func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult
    func loadoutRows() async throws -> CoreLoadoutRows

    func activityRead() async throws -> CoreActivityReport
    /// `activity.subscribe` and `activity.unsubscribe` as one stream: the first element is the full snapshot, later ones
    /// are full reports pushed when the report changed (a poll every 3 s), and ending or cancelling the iteration
    /// unsubscribes. A failed subscription ends the stream with the error.
    func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error>
    /// Asks one running session to end. Not undoable: the screen confirms first. The pid is never a parameter.
    func activityStop(cli: CoreCLI, id: String) async throws -> CoreStopResult

    func loadoutCopyToOther(id: String) async throws -> CoreEntryResult
    func loadoutRemoveItem(id: String) async throws -> CoreEntryResult
    func loadoutRemoveDeadHooks(cli: CoreCLI) async throws -> CoreEntryResult

    func journalUndo(id: String) async throws -> CoreUndoResult
    func journalHistory() async throws -> CoreJournalHistory

    /// `dir` is nil for the global scope and an absolute project folder otherwise.
    func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot
    func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview
    func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult
    func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult
    func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult
    func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult
    func rulesCheck(rule: String) async throws -> CoreRuleCheck

    func limitsRead() async throws -> CoreLimitsResult
}
