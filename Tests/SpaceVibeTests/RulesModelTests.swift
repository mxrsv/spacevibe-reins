import Foundation
import Testing
@testable import SpaceVibe

/// A core that serves the Rules calls from canned data and records what the screen asked, so the model is tested on DTOs alone
/// (plan S.1e).
private final class FakeRulesCore: UnservedCore, @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot: CoreRulesSnapshot
    private var _calls: [String] = []
    private var _readFailure: Error?
    private var _writeFailure: Error?
    private var _undoFailure: Error?
    private var _check = CoreRuleCheck(valid: true, message: nil)
    private var _capabilityEntry: CoreJournalEntry? = FakeRulesCore.entry("Set Push and deploy to Deny (global)")

    init(snapshot: CoreRulesSnapshot) { _snapshot = snapshot }

    var calls: [String] { lock.withLock { _calls } }
    var snapshot: CoreRulesSnapshot { get { lock.withLock { _snapshot } } set { lock.withLock { _snapshot = newValue } } }
    var readFailure: Error? { get { lock.withLock { _readFailure } } set { lock.withLock { _readFailure = newValue } } }
    var writeFailure: Error? { get { lock.withLock { _writeFailure } } set { lock.withLock { _writeFailure = newValue } } }
    var undoFailure: Error? { get { lock.withLock { _undoFailure } } set { lock.withLock { _undoFailure = newValue } } }
    var check: CoreRuleCheck { get { lock.withLock { _check } } set { lock.withLock { _check = newValue } } }
    var capabilityEntry: CoreJournalEntry? { get { lock.withLock { _capabilityEntry } } set { lock.withLock { _capabilityEntry = newValue } } }

    private func record(_ call: String) { lock.withLock { _calls.append(call) } }

    static func entry(_ label: String) -> CoreJournalEntry {
        CoreJournalEntry(id: "entry-1", at: "2026-11-07T10:00:00.000Z", label: label, undone: false, count: 1)
    }

    override func rulesSnapshot(scope: CoreRuleScope, dir: String?, refreshProjects: Bool) async throws -> CoreRulesSnapshot {
        record("snapshot \(scope.rawValue) \(dir ?? "-") refresh=\(refreshProjects)")
        if let failure = readFailure { throw failure }
        return snapshot
    }

    override func rulesPreview(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreCapabilityPreview {
        record("preview \(scope.rawValue) \(dir ?? "-") \(capability.rawValue) \(verdict.rawValue)")
        return CoreCapabilityPreview(
            capability: capability, verdict: verdict, scopeLabel: "~/.claude/settings.json", current: .allow, resulting: CoreCapabilityState(rawValue: verdict.rawValue) ?? .none,
            replaces: [CoreVerdictRule(verdict: .allow, rule: "Bash(git push:*)")], writes: [CoreVerdictRule(verdict: verdict, rule: "Bash(git push:*)")]
        )
    }

    override func rulesSetCapability(scope: CoreRuleScope, dir: String?, capability: CoreCapability, verdict: CoreVerdict) async throws -> CoreSetCapabilityResult {
        record("set \(scope.rawValue) \(dir ?? "-") \(capability.rawValue) \(verdict.rawValue)")
        if let failure = writeFailure { throw failure }
        return CoreSetCapabilityResult(entry: capabilityEntry)
    }

    override func rulesAdd(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult {
        record("add \(scope.rawValue) \(dir ?? "-") \(verdict.rawValue) \(rule)")
        if let failure = writeFailure { throw failure }
        return CoreEntryResult(entry: Self.entry("Added \(verdict.rawValue) rule \(rule) (global)"))
    }

    override func rulesRemove(scope: CoreRuleScope, dir: String?, verdict: CoreVerdict, rule: String) async throws -> CoreEntryResult {
        record("remove \(scope.rawValue) \(dir ?? "-") \(verdict.rawValue) \(rule)")
        if let failure = writeFailure { throw failure }
        return CoreEntryResult(entry: Self.entry("Removed \(verdict.rawValue) rule \(rule) (global)"))
    }

    override func rulesChangeVerdict(scope: CoreRuleScope, dir: String?, rule: String, from: CoreVerdict, to: CoreVerdict) async throws -> CoreEntryResult {
        record("move \(scope.rawValue) \(dir ?? "-") \(rule) \(from.rawValue)>\(to.rawValue)")
        if let failure = writeFailure { throw failure }
        return CoreEntryResult(entry: Self.entry("Changed \(rule) from \(from.rawValue) to \(to.rawValue) (global)"))
    }

    override func rulesCheck(rule: String) async throws -> CoreRuleCheck {
        record("check \(rule)")
        return check
    }

    override func journalUndo(id: String) async throws -> CoreUndoResult {
        record("undo \(id)")
        if let failure = undoFailure { throw failure }
        return CoreUndoResult(label: "Set Push and deploy to Deny (global)")
    }
}

@MainActor
@Suite("Rules model")
struct RulesModelTests {
    private static let project = "/work/web"

    private static func rule(_ text: String, _ verdict: CoreVerdict, scope: CoreRuleScope = .global, dir: String? = nil) -> CoreRule {
        CoreRule(id: "\(scope.rawValue):\(verdict.rawValue):\(text)", scope: scope, dir: dir, file: "~/.claude/settings.json", verdict: verdict, rule: text, tool: "Bash", specifier: nil)
    }

    private static func cell(_ capability: CoreCapability, _ label: String, _ state: CoreCapabilityState, rules: [CoreRule] = []) -> CoreCapabilityCell {
        CoreCapabilityCell(capability: capability, label: label, state: state, editable: state != .mixed, rules: rules)
    }

    private static let codex = CoreCodexPermissions(
        present: true, model: .legacy, unrestricted: false, warnings: [], approvalPolicy: .mode("on-request"), sandboxMode: "workspace-write",
        sandboxWorkspaceWrite: nil, defaultPermissions: nil, approvalsReviewer: nil, profiles: [], projects: [],
        rules: CoreCodexRulesSummary(files: 0, allow: 0, prompt: 0, forbidden: 0, other: 0, unreadable: 0, folderNotReadable: false),
        notReadable: false, skippedLines: 0
    )

    private static func snapshot(scope: CoreRuleScope = .global, dir: String? = nil, notReadable: Bool = false, problems: [String] = [], codex: CoreCodexPermissions? = nil) -> CoreRulesSnapshot {
        let push = rule("Bash(git push:*)", .allow, scope: scope, dir: dir)
        return CoreRulesSnapshot(
            projectDirs: [project], globalRuleCount: 3, scope: scope, dir: dir, fileLabel: scope == .global ? "~/.claude/settings.json" : ".claude/settings.json",
            exists: true, problems: problems, rules: [push, rule("Bash(rm -rf:*)", .deny, scope: scope, dir: dir)],
            grid: [cell(.read, "Read files", .allow), cell(.run, "Run commands", .mixed), cell(.push, "Push and deploy", .allow, rules: [push])],
            codex: codex ?? Self.codex, notReadable: notReadable, globalNotReadable: false
        )
    }

    private func model(_ core: FakeRulesCore) -> RulesModel {
        let env = AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { core })
        return RulesModel(env: env)
    }

    private func settle(_ what: String, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done(), "\(what) did not happen")
    }

    private func started(_ core: FakeRulesCore) async throws -> RulesModel {
        let model = model(core)
        model.start()
        try await settle("the first read") { model.isSettled }
        return model
    }

    // MARK: Reading

    @Test("the first read asks the core to discover the projects, and a scope switch reuses its list")
    func reads() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        #expect(core.calls == ["snapshot global - refresh=true"])
        #expect(model.badge == 3)
        #expect(model.snapshot?.title == "Global")
        #expect(model.snapshot?.rules.count == 2)

        core.snapshot = Self.snapshot(scope: .project, dir: Self.project)
        model.selectProject(Self.project)
        try await settle("the scope switch") { model.isSettled && model.snapshot?.selection.dir == Self.project }
        #expect(core.calls.last == "snapshot project /work/web refresh=false")
        #expect(model.snapshot?.title == "web (shared)")

        core.snapshot = Self.snapshot(scope: .local, dir: Self.project)
        model.selectFile(.local)
        try await settle("the local file") { model.isSettled && core.calls.count == 3 }
        #expect(core.calls.last == "snapshot local /work/web refresh=false")

        model.refresh()
        try await settle("the refresh") { model.isSettled && core.calls.count == 4 }
        #expect(core.calls.last == "snapshot local /work/web refresh=true")
    }

    @Test("a project the core read as global moves the selection to Global")
    func projectGone() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        model.selectProject(Self.project)
        try await settle("the fallback") { model.isSettled && model.selection == .global }
        #expect(model.snapshot?.selection == .global)
    }

    @Test("a read the core refuses shows its sentence, and Retry reads again")
    func readFails() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        core.readFailure = CoreError("The config folders could not be resolved.", status: 500)
        let model = model(core)
        model.start()
        try await settle("the failure") { model.failure != nil }
        #expect(model.failure == "The config folders could not be resolved.")
        #expect(model.snapshot == nil && model.badge == nil)
        core.readFailure = nil
        model.retry()
        try await settle("the retry") { model.isSettled }
        #expect(model.failure == nil && model.snapshot != nil)
    }

    @Test("when the helper is missing, the page shows the fixed startup sentence and no rules")
    func helperMissing() async throws {
        let client = CoreClient(binary: URL(fileURLWithPath: "/nonexistent/spacevibe"))
        let model = RulesModel(env: AppEnvironment(toasts: ToastCenter(announce: false), makeCoreClient: { client }))
        model.start()
        try await settle("the failure") { model.failure != nil }
        #expect(model.failure == CoreWire.startFailedMessage)
        #expect(model.snapshot == nil)
    }

    @Test("a scope the core could not look at is not editable: a click on its grid asks for no preview")
    func notReadableIsNotEditable() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot(notReadable: true, problems: ["~/.claude/settings.json could not be read."]))
        let model = try await started(core)
        model.requestSet(.push, to: .deny)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.pending == nil && core.calls == ["snapshot global - refresh=true"])
    }

    @Test("an unreadable config.toml reaches the page as the fixed unknown sentence, never as the defaults, whether or not the file is present")
    func codexNotReadable() async throws {
        for present in [false, true] {
            var unreadable = Self.codex
            unreadable.present = present
            unreadable.notReadable = true
            unreadable.warnings = ["~/.codex/config.toml could not be read."]
            let core = FakeRulesCore(snapshot: Self.snapshot(codex: unreadable))
            let model = try await started(core)
            let codex = try #require(model.snapshot?.codex)
            #expect(codex.notReadable)
            let status = CodexWording.status(codex)
            #expect(status == CodexStatus(tone: .warn, sentence: CodexWording.notReadableSentence, detail: nil))
            #expect(!status.sentence.contains("defaults") && !status.sentence.contains("there is no"))
            #expect(CodexWording.rows(codex).isEmpty)
            #expect(RulesWording.codexNotices(codex) == ["~/.codex/config.toml could not be read."])
        }
    }

    // MARK: Grid writes

    @Test("a grid click asks the core for a preview and opens the confirmation with the row's own label; Confirm writes the previewed scope")
    func previewConfirmAndUndo() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        model.requestSet(.push, to: .deny)
        try await settle("the confirmation") { model.pending != nil }
        #expect(core.calls.last == "preview global - push deny")
        #expect(model.pending?.question == "Set Push and deploy to Deny?")
        #expect(model.pending?.location == "Writes to Global: ~/.claude/settings.json.")
        #expect(model.pending?.preview.replaces == [CoreVerdictRule(verdict: .allow, rule: "Bash(git push:*)")])
        #expect(model.env.toasts.current == nil)

        model.confirmPending()
        try await settle("the toast") { model.env.toasts.current != nil && model.isSettled }
        #expect(core.calls.contains("set global - push deny"))
        #expect(model.env.toasts.current?.message == "Set Push and deploy to Deny" && model.env.toasts.current?.tone == .info)
        #expect(core.calls.filter { $0.hasPrefix("snapshot") }.count == 2)

        model.env.toasts.runCurrentAction()
        try await settle("the Undo toast") { model.env.toasts.current?.message.hasPrefix("Undid") == true && model.isSettled }
        #expect(core.calls.contains("undo entry-1"))
        #expect(model.env.toasts.current?.message == "Undid Set Push and deploy to Deny (global)")
        #expect(core.calls.filter { $0.hasPrefix("snapshot") }.count == 3)
    }

    @Test("a mixed cell, and a click on the state the cell already has, ask for nothing")
    func nothingToPreview() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        model.requestSet(.run, to: .deny)
        model.requestSet(.push, to: .allow)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.pending == nil && core.calls.count == 1)
    }

    @Test("a write the core refuses shows its sentence in a danger toast and frees the model for the next write")
    func writeRefused() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        core.writeFailure = CoreError("~/.claude/settings.json is not valid JSON, so SpaceVibe left it alone.", status: 409)
        model.requestSet(.push, to: .deny)
        try await settle("the confirmation") { model.pending != nil }
        model.confirmPending()
        try await settle("the refusal") { model.env.toasts.current != nil && !model.isWriting }
        #expect(model.env.toasts.current?.message == "~/.claude/settings.json is not valid JSON, so SpaceVibe left it alone.")
        #expect(model.env.toasts.current?.tone == .danger)
        try await settle("the re-read") { model.isSettled }
        #expect(core.calls.filter { $0.hasPrefix("snapshot") }.count == 2, "a refused write reads the rules again: the file may have changed")
    }

    @Test("a setCapability that answers no entry is the 409 sentence, never a success toast")
    func nothingToChange() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        core.capabilityEntry = nil
        let model = try await started(core)
        model.requestSet(.push, to: .deny)
        try await settle("the confirmation") { model.pending != nil }
        model.confirmPending()
        try await settle("the message") { model.env.toasts.current != nil && !model.isWriting }
        #expect(model.env.toasts.current?.message == "Nothing to change: the file already holds that.")
        #expect(model.env.toasts.current?.tone == .danger)
    }

    @Test("an Undo the core refuses shows its sentence")
    func undoRefused() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        model.requestSet(.push, to: .deny)
        try await settle("the confirmation") { model.pending != nil }
        model.confirmPending()
        try await settle("the toast") { model.env.toasts.current?.message == "Set Push and deploy to Deny" }
        core.undoFailure = CoreError("That change was already undone.", status: 409)
        model.env.toasts.runCurrentAction()
        try await settle("the refusal") { model.env.toasts.current?.tone == .danger }
        #expect(model.env.toasts.current?.message == "That change was already undone.")
    }

    // MARK: Rule writes

    @Test("Add checks the rule with the core first, then writes the trimmed rule under the chosen verdict and clears the field")
    func addRule() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        model.draft = "  Bash(npm test *)  "
        model.draftVerdict = .deny
        model.submitDraft()
        try await settle("the toast") { model.env.toasts.current != nil && model.isSettled }
        #expect(core.calls.contains("check Bash(npm test *)") && core.calls.contains("add global - deny Bash(npm test *)"))
        #expect(model.env.toasts.current?.message == "Added Bash(npm test *) to Deny")
        #expect(model.draft == "" && model.addError == nil)
    }

    @Test("a rule the core calls invalid shows its sentence next to the field and writes nothing", arguments: [
        (CoreRuleCheck(valid: false, message: "Enter a rule such as Bash(npm test *)."), "Enter a rule such as Bash(npm test *)."),
        (CoreRuleCheck(valid: false, message: nil), "That is not a valid rule. Use Tool or Tool(pattern) on one line."),
    ])
    func invalidRule(check: CoreRuleCheck, shown: String) async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        core.check = check
        model.draft = "(nope)"
        model.submitDraft()
        try await settle("the message") { model.addError != nil }
        #expect(model.addError == shown)
        #expect(!core.calls.contains { $0.hasPrefix("add") } && model.draft == "(nope)" && model.env.toasts.current == nil)
    }

    @Test("a duplicate the core refuses on write shows its sentence next to the field, not a toast, and keeps the text")
    func duplicate() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        core.writeFailure = CoreError("That rule is already in .claude/settings.json.", status: 409)
        model.draft = "Bash(git push:*)"
        model.submitDraft()
        try await settle("the message") { model.addError != nil && !model.isWriting }
        #expect(model.addError == "That rule is already in .claude/settings.json.")
        #expect(model.env.toasts.current == nil && model.draft == "Bash(git push:*)")
    }

    @Test("Remove and Move send the rule's own verdict to the core and say what they did")
    func removeAndMove() async throws {
        let core = FakeRulesCore(snapshot: Self.snapshot())
        let model = try await started(core)
        let push = try #require(model.snapshot?.rules.first { $0.verdict == .allow })
        model.remove(push)
        try await settle("the removal") { model.env.toasts.current != nil && model.isSettled }
        #expect(core.calls.contains("remove global - allow Bash(git push:*)"))
        #expect(model.env.toasts.current?.message == "Removed Bash(git push:*) from Allow")

        model.env.toasts.dismiss()
        model.move(push, to: .ask)
        try await settle("the move") { model.env.toasts.current != nil && model.isSettled }
        #expect(core.calls.contains("move global - Bash(git push:*) allow>ask"))
        #expect(model.env.toasts.current?.message == "Moved Bash(git push:*) from Allow to Ask first")
    }
}

@Suite("Rules spine columns")
struct RulesColumnsTests {
    @Test("the two CLI columns are 168 while the card has room (1440 wide: 559), and give way to 72 in a narrow one")
    func widths() {
        // The card is 559 at 1440: (1440 - sidebar 220 - inset 12 - edges 2 - canvas edges 64 - gap 24) / 2.
        #expect(RulesColumns.width(card: 559) == 168)
        #expect(RulesColumns.width(card: .greatestFiniteMagnitude) == 168)
        #expect(RulesColumns.width(card: 370) == 78)
        #expect(RulesColumns.width(card: 200) == 72)
        #expect(RulesColumns.width(card: 550) == 168 && RulesColumns.width(card: 549) < 168)
    }
}
