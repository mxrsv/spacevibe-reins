import Foundation
@testable import SpaceVibe

/// A `CoreService` that serves nothing: every method refuses with a 500. A model test subclasses it and overrides only the
/// methods its screen calls, so a stray call to another one fails loudly instead of answering with made-up data.
class UnservedCore: CoreService, @unchecked Sendable {
    func unserved() -> CoreError { CoreError("not served by this fake", status: 500) }

    func initialize() async throws -> CoreInitializeResult { throw unserved() }
    func clisList() async throws -> CoreCLIsList { throw unserved() }
    func inventoryRead() async throws -> CoreInventorySnapshot { throw unserved() }
    func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult { throw unserved() }
    func loadoutRows() async throws -> CoreLoadoutRows { throw unserved() }
    func activityRead() async throws -> CoreActivityReport { throw unserved() }
    func activitySubscribe() -> AsyncThrowingStream<CoreActivityReport, Error> { AsyncThrowingStream { $0.finish(throwing: CoreError("not served by this fake", status: 500)) } }
    func activityStop(cli: CLIID, id: String) async throws -> CoreStopResult { throw unserved() }
    func loadoutCopyToOther(id: String, target: CLIID) async throws -> CoreEntryResult { throw unserved() }
    func loadoutRemoveItem(id: String) async throws -> CoreEntryResult { throw unserved() }
    func loadoutRemoveDeadHooks(cli: CLIID) async throws -> CoreEntryResult { throw unserved() }
    func journalUndo(id: String) async throws -> CoreUndoResult { throw unserved() }
    func journalHistory() async throws -> CoreJournalHistory { throw unserved() }
    func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot { throw unserved() }
    func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview { throw unserved() }
    func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult { throw unserved() }
    func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw unserved() }
    func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult { throw unserved() }
    func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult { throw unserved() }
    func rulesChangeVerdicts(scope: CoreRuleScope, dir: String?, to: CoreVerdict, rules: [CoreRuleMove]) async throws -> CoreEntryResult { throw unserved() }
    func rulesCheck(rule: String) async throws -> CoreRuleCheck { throw unserved() }
    func limitsRead() async throws -> CoreLimitsResult { throw unserved() }
}

// MARK: Wire arrays from literals

/// The per-CLI arrays of the wire (`[{cli, ...}]`) from a literal in the order written, for the DTOs the tests build by hand.
extension Array where Element == CoreCLIEvents {
    static func of(_ pairs: KeyValuePairs<CLIID, [String]>) -> Self { pairs.map { CoreCLIEvents(cli: $0.key, events: $0.value) } }
    /// In the fixture catalog's order, then any other CLI by id.
    static func of(_ map: [CLIID: [String]]) -> Self { inFixtureOrder(map).map { CoreCLIEvents(cli: $0.0, events: $0.1) } }
}

extension Array where Element == CoreCLIRoot {
    static func of(_ pairs: KeyValuePairs<CLIID, String>) -> Self { pairs.map { CoreCLIRoot(cli: $0.key, root: $0.value) } }
}

extension Array where Element == CoreCLICount {
    static func of(_ pairs: KeyValuePairs<CLIID, Int>) -> Self { pairs.map { CoreCLICount(cli: $0.key, count: $0.value) } }
}

func inFixtureOrder<Value>(_ map: [CLIID: Value]) -> [(CLIID, Value)] {
    let order = CLICatalogFixture.list.map(\.id)
    return map.sorted { a, b in
        let x = order.firstIndex(of: a.key) ?? order.count, y = order.firstIndex(of: b.key) ?? order.count
        return x != y ? x < y : a.key.rawValue < b.key.rawValue
    }.map { ($0.key, $0.value) }
}
