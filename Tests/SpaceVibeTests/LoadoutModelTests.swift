import Foundation
import Testing
@testable import SpaceVibe

/// Holds a fake write at the core until the test opens the gate, so a test can look at the model while the write runs
/// instead of racing it.
private final class WriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let held = waiters
        waiters = []
        lock.unlock()
        for continuation in held { continuation.resume() }
    }
}

/// A core that serves the Loadout calls from canned rows. Counts what the screen asked and answers the writes with what the
/// test sets, so the model is tested on DTOs alone (plan S.1d).
private final class FakeLoadoutCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var _rows: CoreLoadoutRows
    private var _scanned = false
    private var _calls: [String] = []
    private var _rowsReads = 0
    private var _readFailure: Error?
    private var _writeFailure: Error?
    private var _undoFailure: Error?
    private var _scanFailure: Error?
    private var _writeGate: WriteGate?
    private var _scanGate: WriteGate?

    init(rows: CoreLoadoutRows) { _rows = rows }

    var calls: [String] { lock.withLock { _calls } }
    var rowsReads: Int { lock.withLock { _rowsReads } }
    var readFailure: Error? { get { lock.withLock { _readFailure } } set { lock.withLock { _readFailure = newValue } } }
    var writeFailure: Error? { get { lock.withLock { _writeFailure } } set { lock.withLock { _writeFailure = newValue } } }
    var undoFailure: Error? { get { lock.withLock { _undoFailure } } set { lock.withLock { _undoFailure = newValue } } }
    var scanFailure: Error? { get { lock.withLock { _scanFailure } } set { lock.withLock { _scanFailure = newValue } } }
    /// While set, `loadoutCopyToOther` waits at the gate after it is recorded.
    var writeGate: WriteGate? { get { lock.withLock { _writeGate } } set { lock.withLock { _writeGate = newValue } } }

    /// While set, `usageScan` waits at the gate after it is recorded.
    var scanGate: WriteGate? { get { lock.withLock { _scanGate } } set { lock.withLock { _scanGate = newValue } } }
    /// What a core restart does: the new core has no scan result, so its rows say `scanning` again.
    func forgetScan() { lock.withLock { _scanned = false } }

    private func record(_ call: String) { lock.withLock { _calls.append(call) } }

    static func entry(_ label: String) -> CoreEntryResult {
        CoreEntryResult(entry: CoreJournalEntry(id: "entry-1", at: "2026-11-07T10:00:00.000Z", label: label, undone: false, count: 1))
    }

    static let usage = CoreUsageResult(
        totals: CoreUsageTotals(claude: CoreCLITotals(skill: [:], agent: [:], hook: [:]), codex: CoreCLITotals(skill: [:], agent: [:], hook: [:])),
        sessions: CoreUsageSessions(claude: 1_234, codex: 56),
        windows: CoreUsageWindows(claude: CoreLogWindow(files: 3, oldest: "2026-10-01", newest: nil), codex: CoreLogWindow(files: 1, oldest: "2026-10-09", newest: nil)),
        files: 4
    )

    override func loadoutRows() async throws -> CoreLoadoutRows {
        record("rows")
        return try lock.withLock {
            _rowsReads += 1
            if let _readFailure { throw _readFailure }
            var rows = _rows
            rows.usage = _scanned ? .ready : .scanning
            return rows
        }
    }

    override func usageScan(progress: (@Sendable (CoreUsageProgress) -> Void)?) async throws -> CoreUsageResult {
        record("scan")
        progress?(CoreUsageProgress(done: 4, total: 4))
        if let gate = scanGate { await gate.wait() }
        if let failure = scanFailure { throw failure }
        lock.withLock { _scanned = true }
        return Self.usage
    }

    override func loadoutCopyToOther(id: String) async throws -> CoreEntryResult {
        record("copy \(id)")
        if let gate = writeGate { await gate.wait() }
        if let failure = writeFailure { throw failure }
        return Self.entry("Copied skill one to Codex")
    }

    override func loadoutRemoveItem(id: String) async throws -> CoreEntryResult {
        record("remove \(id)")
        if let failure = writeFailure { throw failure }
        return Self.entry("Removed skill one from Claude Code")
    }

    override func loadoutRemoveDeadHooks(cli: CoreCLI) async throws -> CoreEntryResult {
        record("removeDead \(cli.rawValue)")
        if let failure = writeFailure { throw failure }
        return Self.entry("Removed 2 dead hooks from Claude Code")
    }

    override func journalUndo(id: String) async throws -> CoreUndoResult {
        record("undo \(id)")
        if let failure = undoFailure { throw failure }
        return CoreUndoResult(label: "Removed skill one from Claude Code")
    }
}

@MainActor
@Suite("Loadout model")
struct LoadoutModelTests {
    // MARK: Rows

    private static let events = ["claude": ["PreToolUse", "Stop"], "codex": ["Stop"]]

    private static func skill(_ name: String, cli: CoreCLI = .claude, inOther: Bool = false) -> CoreInventoryItem {
        CoreInventoryItem(
            id: "\(cli.rawValue):skill:global:\(name)", cli: cli, kind: .skill, name: name, entry: name, description: "", owner: "user",
            path: "/home/demo/.\(cli.rawValue)/skills/\(name)", file: "/home/demo/.\(cli.rawValue)/skills/\(name)/SKILL.md", removable: true,
            scope: .global, project: nil, inOther: inOther, key: "skill::\(name)",
            cells: CoreCells(claude: cli == .claude ? .counted(runs: 3, last: nil, errors: nil) : .missing, codex: cli == .codex ? .counted(runs: 1, last: nil, errors: nil) : .missing)
        )
    }

    private static func hook(_ hash: String, dead: Bool, removable: Bool = true) -> CoreInventoryHook {
        CoreInventoryHook(
            id: "claude:hook:\(hash)", cli: .claude, kind: .hook, event: "Stop", matcher: nil, command: "/home/demo/.claude/scripts/\(hash).sh", timeout: nil,
            async: false, owner: "user", removable: removable, dead: dead, paths: [], hash: hash, file: "/home/demo/.claude/settings.json",
            scope: .global, project: nil, key: "hook::\(hash)", cells: CoreCells(claude: .counted(runs: 0, last: nil, errors: 0), codex: .missing), usage: nil
        )
    }

    private static func rows() -> CoreLoadoutRows {
        CoreLoadoutRows(
            usage: .scanning, items: [skill("one"), skill("both", cli: .claude, inOther: true), skill("both", cli: .codex, inOther: true)],
            hooks: [hook("h1", dead: true), hook("h2", dead: true), hook("h3", dead: false), hook("h4", dead: true, removable: false)],
            problems: ["Could not read /home/demo/.claude/skills/x"], events: events, roots: ["claude": "/home/demo/.claude", "codex": "/home/demo/.codex"],
            countsByScope: ["global": CoreFilterCounts(all: 6, only: .init(claude: 4, codex: 0), neverRan: 4, dead: 3)],
            rowFlags: [
                "skill::one": CoreRowFlags(one: true, neverRan: false, dead: false), "skill::both": CoreRowFlags(one: false, neverRan: false, dead: false),
                "hook::h1": CoreRowFlags(one: true, neverRan: true, dead: true), "hook::h2": CoreRowFlags(one: true, neverRan: true, dead: true),
                "hook::h3": CoreRowFlags(one: true, neverRan: true, dead: false), "hook::h4": CoreRowFlags(one: true, neverRan: true, dead: true),
            ]
        )
    }

    /// Every call goes to the fake Go core (`core`).
    private func model(_ core: FakeLoadoutCore) -> LoadoutModel {
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core })
        return LoadoutModel(env: env)
    }

    private func settle(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done(), "\(what) did not happen")
    }

    private func started(_ core: FakeLoadoutCore) async throws -> LoadoutModel {
        let model = model(core)
        model.start()
        try await settle("the first read and scan") { model.isSettled }
        return model
    }

    private func row(_ model: LoadoutModel, _ name: String) throws -> LoadoutRow {
        try #require(model.data?.rows.first { $0.name == name })
    }

    // MARK: Reading

    @Test("the rows are read, the usage scan runs, and the rows are read again with its counts")
    func readScanRead() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        // The first read and the scan start together, so their order is not promised; the read that carries the counts follows the scan.
        let calls = core.calls
        #expect(core.rowsReads == 2 && calls.filter { $0 == "rows" }.count == 2)
        #expect(calls.firstIndex(of: "scan").map { scan in calls.lastIndex(of: "rows").map { $0 > scan } ?? false } == true)
        #expect(model.usageNote == "Counted from 1,234 Claude Code and 56 Codex sessions since 2026-10-01")
        #expect(model.scanProgress == nil && model.scanFailure == nil)
        #expect(model.badge == 6)
        #expect(model.data?.problems == ["Could not read ~/.claude/skills/x"])
        #expect(model.data?.rows.count == 6)
    }

    @Test("a read counts as unsettled from the moment it is asked for, before its task has started")
    func unsettledAtOnce() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        #expect(model.isSettled)
        model.reload()
        #expect(!model.isSettled)
        try await settle("the re-read") { model.isSettled }
    }

    @Test("rows that say scanning after a finished scan (the core restarted) ask for a new scan and drop the old note")
    func restartedCoreScansAgain() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        #expect(model.usageNote.hasPrefix("Counted from") && core.calls.filter { $0 == "scan" }.count == 1)
        core.forgetScan()
        let gate = WriteGate()
        core.scanGate = gate
        // A write's re-read sends only `loadout.rows`.
        model.reload()
        try await settle("the second scan") { core.calls.filter { $0 == "scan" }.count == 2 }
        #expect(model.usageResult == nil && model.usageNote.hasPrefix("Counting usage"))
        gate.open()
        try await settle("the second scan to finish") { model.isSettled }
        #expect(model.usageNote.hasPrefix("Counted from"))
        #expect(model.data?.rows.count == 6)
        // The rows now say `ready`: a further read does not scan again.
        model.reload()
        try await settle("the re-read") { model.isSettled }
        #expect(core.calls.filter { $0 == "scan" }.count == 2)
    }

    @Test("a failed scan is the banner, and the rows are still read")
    func scanFails() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        core.scanFailure = CoreError("The usage scan could not run.", status: 500)
        let model = try await started(core)
        #expect(model.scanFailure == "The usage scan could not run.")
        #expect(model.usageNote == "Usage could not be counted")
        #expect(model.data != nil)
    }

    @Test("a read the core refuses shows its sentence, and Retry reads again")
    func readFails() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        core.readFailure = CoreError("The config folders could not be resolved.", status: 500)
        let model = model(core)
        model.start()
        try await settle("the failure") { model.readFailure != nil }
        #expect(model.readFailure == "The config folders could not be resolved.")
        #expect(model.data == nil)
        core.readFailure = nil
        model.retry()
        try await settle("the retry") { model.isSettled }
        #expect(model.readFailure == nil && model.data != nil)
    }

    @Test("when the helper is missing, the screen shows the fixed startup sentence and no rows")
    func helperMissing() async throws {
        let client = CoreClient(binary: URL(fileURLWithPath: "/nonexistent/spacevibe"))
        let model = LoadoutModel(env: AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client }))
        model.start()
        try await settle("the failure") { model.readFailure != nil }
        #expect(model.readFailure == CoreWire.startFailedMessage)
        #expect(model.data == nil)
    }

    // MARK: Writes

    @Test("Add to Codex copies the Claude item, says so, and reads again; Undo goes through the journal and reads again")
    func copyAndUndo() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        let one = try row(model, "one")
        #expect(LoadoutRows.copyPlan(one, to: .codex, events: model.data?.events ?? [:]) == "claude:skill:global:one")
        let reads = core.rowsReads
        model.add(one, to: .codex)
        try await settle("the toast") { model.env.toasts.current != nil }
        #expect(core.calls.contains("copy claude:skill:global:one"))
        #expect(model.env.toasts.current?.message == "Added skill one to Codex" && model.env.toasts.current?.tone == .info)
        try await settle("the re-read") { core.rowsReads == reads + 1 && model.isSettled }

        model.env.toasts.runCurrentAction()
        try await settle("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
        #expect(core.calls.contains("undo entry-1"))
        #expect(model.env.toasts.current?.message == "Undid Removed skill one from Claude Code")
        try await settle("the re-read after Undo") { core.rowsReads == reads + 2 && model.isSettled }
    }

    @Test("Remove sends the member's id and names the CLI")
    func remove() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        let both = try row(model, "both")
        let member = try #require(both.members[.codex])
        model.remove(both, member: member)
        try await settle("the toast") { model.env.toasts.current != nil }
        #expect(core.calls.contains("remove codex:skill:global:both"))
        #expect(model.env.toasts.current?.message == "Removed skill both from Codex")
    }

    @Test("Remove dead hooks counts every removable dead hook of the CLI, not one per row")
    func removeDeadHooks() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        #expect(model.deadHookCount(cli: .claude) == 2 && model.deadHookCount(cli: .codex) == 0)
        model.removeDeadHooks(cli: .claude)
        try await settle("the toast") { model.env.toasts.current != nil }
        #expect(core.calls.contains("removeDead claude"))
        #expect(model.env.toasts.current?.message == "Removed 2 dead hooks from Claude Code")
    }

    @Test("a second click while the write runs is ignored, and the guard outlives the write")
    func doubleClick() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        let one = try row(model, "one")
        // The write waits at the gate, so the guard is held for as long as the test looks at it: nothing here depends on timing.
        let gate = WriteGate()
        core.writeGate = gate
        let clicked = ContinuousClock.now
        model.add(one, to: .codex)
        model.add(one, to: .codex)
        try await settle("the write reaching the core") { core.calls.contains { $0.hasPrefix("copy") } }
        #expect(model.guardedWrites == 1)
        #expect(core.calls.filter { $0.hasPrefix("copy") }.count == 1)
        gate.open()
        try await settle("the toast") { model.env.toasts.current != nil }
        try await settle("the guard release") { model.guardedWrites == 0 }
        // Released no sooner than `writeGuard` after the click, however fast the write was.
        #expect(ContinuousClock.now - clicked >= LoadoutModel.writeGuard)
        #expect(core.calls.filter { $0.hasPrefix("copy") }.count == 1)
    }

    @Test("a refusal shows the core's own sentence in a danger toast, releases the guard and does not read again",
          arguments: [
              (409, "A skill named one already exists in Codex."), (404, "That item is no longer installed."),
              (403, "That item belongs to a plugin."), (413, "That skill is too large to copy."),
          ])
    func refusals(status: Int, message: String) async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        core.writeFailure = CoreError(message, status: status)
        let reads = core.rowsReads
        model.add(try row(model, "one"), to: .codex)
        try await settle("the toast") { model.env.toasts.current != nil }
        #expect(model.env.toasts.current?.message == message && model.env.toasts.current?.tone == .danger)
        #expect(model.env.toasts.current?.action == nil)
        try await settle("the guard release") { model.guardedWrites == 0 }
        #expect(core.rowsReads == reads)
    }

    @Test("an error that is not the core's gets a fixed sentence, never its description")
    func unexpectedFailure() async throws {
        struct Leaky: Error, CustomStringConvertible { var description: String { "/Users/someone/secret" } }
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        core.writeFailure = Leaky()
        model.remove(try row(model, "one"), member: try #require(try row(model, "one").members[.claude]))
        try await settle("the toast") { model.env.toasts.current != nil }
        #expect(model.env.toasts.current?.message == CoreError.unexpectedMessage)
    }

    @Test("an Undo the core refuses shows its sentence and does not read again")
    func undoRefused() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        model.add(try row(model, "one"), to: .codex)
        try await settle("the toast") { model.env.toasts.current?.action != nil }
        try await settle("the re-read") { model.isSettled }
        core.undoFailure = CoreError("Something changed since: Undo would overwrite it.", status: 409)
        let reads = core.rowsReads
        model.env.toasts.runCurrentAction()
        try await settle("the refusal") { model.env.toasts.current?.tone == .danger }
        #expect(model.env.toasts.current?.message == "Something changed since: Undo would overwrite it.")
        #expect(core.rowsReads == reads)
    }

    // MARK: Routing

    @Test("reads, the scan, writes and Undo all use the Go core; the in-process core is never asked")
    func routing() async throws {
        let core = FakeLoadoutCore(rows: Self.rows())
        let model = try await started(core)
        model.remove(try row(model, "one"), member: try #require(try row(model, "one").members[.claude]))
        try await settle("the toast") { model.env.toasts.current?.action != nil }
        #expect(model.env.toasts.current?.tone == .info)
        model.env.toasts.runCurrentAction()
        try await settle("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true }
        #expect(core.calls.contains("scan") && core.calls.contains("remove claude:skill:global:one") && core.calls.contains("undo entry-1"))
        #expect(model.env.toasts.current?.tone != .danger)
    }
}
