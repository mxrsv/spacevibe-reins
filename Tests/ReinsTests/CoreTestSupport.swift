import Foundation
@testable import Reins

/// A `CoreService` that serves nothing: every method refuses with a 500. A model test subclasses it and overrides only the
/// methods its screen calls, so a stray call to another one fails loudly instead of answering with made-up data.
class UnservedCore: CoreService, @unchecked Sendable {
    func unserved() -> CoreError { CoreError("not served by this fake", status: 500) }

    func initialize() async throws -> CoreInitializeResult { throw unserved() }
    func inventoryRead() async throws -> CoreInventorySnapshot { throw unserved() }
    func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult { throw unserved() }
    func loadoutRows() async throws -> CoreLoadoutRows { throw unserved() }
    func activityRead() async throws -> CoreActivityReport { throw unserved() }
    func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> { AsyncThrowingStream { $0.finish(throwing: CoreError("not served by this fake", status: 500)) } }
    func activityStop(cli: CoreCLI, id: String) async throws -> CoreStopResult { throw unserved() }
    func loadoutCopyToOther(id: String) async throws -> CoreEntryResult { throw unserved() }
    func loadoutRemoveItem(id: String) async throws -> CoreEntryResult { throw unserved() }
    func loadoutRemoveDeadHooks(cli: CoreCLI) async throws -> CoreEntryResult { throw unserved() }
    func journalUndo(id: String) async throws -> CoreUndoResult { throw unserved() }
    func journalHistory() async throws -> CoreJournalHistory { throw unserved() }
    func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot { throw unserved() }
    func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview { throw unserved() }
    func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult { throw unserved() }
    func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw unserved() }
    func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw unserved() }
    func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult { throw unserved() }
    func rulesCheck(rule: String) async throws -> CoreRuleCheck { throw unserved() }
    func limitsRead() async throws -> CoreLimitsResult { throw unserved() }
}
