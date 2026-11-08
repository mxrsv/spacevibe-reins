import Foundation
import Testing
@testable import SpaceVibe

/// V5-A18 for Activity: each tab's Answer, its cards, the Today-labels and the lists come from one derivation (`ActivityQuery`,
/// `ActivityAnswer`, `ActivityFigures`) on the core's DTOs, against a fixed clock. Plus the Stop confirmation's words and the
/// in-memory dismissal with its Undo.
@Suite("Activity answers")
@MainActor
struct ActivityAnswersTests {
    /// Sunday 2026-11-08 12:00 UTC, with a UTC calendar so "today" does not depend on the machine.
    private static let now = Date(timeIntervalSince1970: 1_794_139_200)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func iso(_ hoursAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Self.now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func session(_ id: String, cli: CoreCLI = .claude, state: CoreSessionState = .running, title: String? = nil, project: String? = "spacevibe-api",
                         pid: Int = 4100, tool: CoreActivityTool? = nil, age: Double? = 600_000, cost: Double? = nil,
                         reason: String = "A reason.") -> CoreActivitySession {
        CoreActivitySession(cli: cli, id: id, title: title ?? "Task \(id)", project: project, pid: pid, state: state, stateReason: reason, reasonCode: nil,
                            currentTool: tool, ageMs: age, lastWriteAgoMs: nil, cost: cost.map { CoreActivityCost(usd: $0, estimated: true) }, costNote: nil)
    }

    private func failure(_ key: String, cli: CoreCLI = .claude, title: String? = nil, count: Int = 2, reason: String = "Exit 2", later: Bool = false,
                         first: Double = 30, last: Double = 3) -> CoreActivityFailure {
        CoreActivityFailure(kind: .command, cli: cli, key: key, title: title ?? "cmd \(key)", count: count, exit: 2, reason: reason, projects: ["spacevibe-api"],
                            sessions: 1, first: iso(first), last: iso(last), laterPass: later ? iso(1) : nil, hook: nil)
    }

    private func file(_ path: String, edits: Int, hoursAgo: Double = 30, projects: [String] = ["spacevibe-api"], clis: [CoreCLI] = [.claude]) -> CoreActivityFile {
        CoreActivityFile(path: "/work/\(path)", label: path, edits: edits, sessions: edits, last: iso(hoursAgo), clis: clis, projects: projects)
    }

    private func report(sessions: [CoreActivitySession] = [], failures: [CoreActivityFailure] = [], files: [CoreActivityFile] = [],
                        limits: [CoreActivityLimit] = []) -> CoreActivityReport {
        CoreActivityReport(sessions: sessions, failures: failures, files: files, unmeasurable: limits, stats: CoreActivityStats(logs: 74, truncated: 0))
    }

    private static let claudeLimit = CoreActivityLimit(cli: .claude, code: "claude-prompt-vs-busy",
                                                       text: "Claude Code does not record permission prompts, so a long tool run and a wait for approval look the same.")
    private static let codexLimit = CoreActivityLimit(cli: .codex, code: "codex-tool-silent",
                                                      text: "Codex logs nothing while a tool runs and does not record approval waits.")

    private func query(_ report: CoreActivityReport?, filter: ActivityFilter = ActivityFilter(), dismissed: Set<String> = [], limits: [CoreLimitsEntry] = []) -> ActivityQuery {
        ActivityQuery(report: report, filter: filter, dismissed: dismissed, limits: limits, readAt: Self.now, now: Self.now, calendar: Self.calendar)
    }

    private func filter(_ values: String...) -> ActivityFilter {
        var filter = ActivityFilter()
        for value in values { filter.toggle(.cli, value) }
        return filter
    }

    private func entry(_ cli: CoreLimitsCLI, _ state: CoreLimitsState) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: state, plan: nil, source: nil, at: nil, windows: [])
    }

    // MARK: Running

    @Test("a waiting session is the Answer: its title, the CLI's question sentence, the project, and no invented question")
    func waitingProblem() {
        let answer = ActivityAnswer.running(query(report(sessions: [session("a", state: .waiting, title: "Fix the rank tie"), session("b")])))
        #expect(answer.sentence == "1 waiting for you")
        #expect(answer.verdict?.title == "Fix the rank tie")
        #expect(answer.verdict?.text == "Claude Code is waiting for your answer to a question.")
        #expect(answer.verdict?.small == "In spacevibe-api. Answer it in the terminal. The log does not hold the question.")
        #expect(answer.verdict?.targetID == "claude:a" && answer.more == 0)
    }

    @Test("several waiting: the first is named and the rest are counted for the card's note")
    func severalWaiting() {
        let answer = ActivityAnswer.running(query(report(sessions: [
            session("a", state: .waiting), session("b", cli: .codex, state: .waiting), session("c", state: .waiting), session("d"),
        ])))
        #expect(answer.sentence == "3 waiting for you" && answer.more == 2)
        #expect(answer.verdict?.targetID == "claude:a")
    }

    @Test("nothing waiting: the plain sentence and no verdict, so no fix button")
    func nothingWaiting() {
        let answer = ActivityAnswer.running(query(report(sessions: [session("a"), session("b", state: .idle)])))
        #expect(answer.sentence == "Nothing is waiting for you." && answer.verdict == nil && answer.more == 0)
        #expect(ActivityAnswer.running(query(report())).sentence == "Nothing is waiting for you.")
    }

    @Test("sessions the core cannot read mean 'nothing' is not known: it says so, with the core's own sentence")
    func unmeasurableMeansUnknown() {
        let sentence = "Codex logs nothing while a tool runs."
        let answer = ActivityAnswer.running(query(report(sessions: [session("a", cli: .codex, state: .unmeasurable, reason: sentence), session("b", cli: .codex, state: .unmeasurable)])))
        #expect(answer.sentence == "Nothing is known to be waiting for you.")
        #expect(answer.verdict?.title == "Task a" && answer.verdict?.text == sentence)
        #expect(answer.verdict?.small == "2 of 2 open sessions cannot be measured." && answer.more == 1)
        let mixed = ActivityAnswer.running(query(report(sessions: [session("a", cli: .codex, state: .unmeasurable, reason: sentence), session("b"), session("c")])))
        #expect(mixed.verdict?.small == "1 of 3 open sessions cannot be measured." && mixed.more == 0)
    }

    @Test("a running session with a tool open shows the CLI's approval limit in the core's words; one that was measured, idle or has no tool shows none")
    func approvalLimit() {
        let tool = CoreActivityTool(name: "Bash", target: "pnpm test")
        let q = query(report(sessions: [
            session("run", tool: tool), session("bare"), session("idle", state: .idle, tool: tool), session("nm", cli: .codex, state: .unmeasurable, reason: "Why not."),
            session("cx", cli: .codex, tool: tool),
        ], limits: [Self.claudeLimit, Self.codexLimit]))
        func item(_ id: String) -> ActivitySessionItem { q.sessions.first { $0.session.id == id }! }
        #expect(item("run").cannotSee == Self.claudeLimit.text && item("run").cannotSeeLabel == "Approval waits not visible")
        #expect(item("cx").cannotSee == Self.codexLimit.text, "each CLI gets its own limit")
        #expect(item("bare").cannotSee == nil && item("idle").cannotSee == nil)
        #expect(item("nm").cannotSee == "Why not." && item("nm").cannotSeeLabel == "Not measurable")
        // The detail says it once: an unmeasurable session's reason is already its first line.
        let lines = ActivityWording.sessionLines(item("run"), elapsedMs: 0)
        #expect(lines.contains(Self.claudeLimit.text))
        #expect(ActivityWording.sessionLines(item("nm"), elapsedMs: 0).filter { $0 == "Why not." }.count == 1)
        // No limit in the report: nothing is claimed.
        #expect(query(report(sessions: [session("run", tool: tool)])).sessions.first?.cannotSee == nil)
    }

        @Test("no report yet: the Answer is loading, on every tab")
    func loading() {
        let loading = query(nil)
        #expect(loading.isLoading)
        #expect(ActivityAnswer.running(loading).sentence == nil && ActivityAnswer.failed(loading).sentence == nil && ActivityAnswer.files(loading).sentence == nil)
    }

    @Test("an ended session is not running: not counted, listed, costed or waited for")
    func endedIsGone() {
        let q = query(report(sessions: [session("a", state: .ended, cost: 5), session("b", cost: 1)]))
        #expect(q.count(.running) == 1 && q.sessions.map(\.id) == ["claude:b"])
        #expect(ActivityFigures.rightNow(q).first?.value == "~$1.00")
    }

    @Test("a filter is named in the Answer, and a CLI the Limits reading calls not installed is said plainly")
    func filterAndNotInstalled() {
        let sessions = [session("a", state: .waiting), session("b", cli: .codex, state: .waiting, title: "Codex task")]
        let codex = query(report(sessions: sessions), filter: filter("codex"))
        #expect(ActivityAnswer.running(codex).sentence == "1 waiting for you in Codex" && codex.count(.running) == 1)
        let none = query(report(sessions: [session("a")]), filter: filter("codex"))
        #expect(ActivityAnswer.running(none).sentence == "Nothing in Codex is waiting for you.")
        let both = query(report(sessions: [session("a")]), filter: filter("claude", "codex"))
        #expect(ActivityAnswer.running(both).sentence == "Nothing in Claude Code or Codex is waiting for you.")
        let missing = query(report(sessions: [session("a")]), filter: filter("codex"), limits: [entry(.claude, .measured), entry(.codex, .notInstalled)])
        #expect(ActivityAnswer.running(missing).sentence == "Codex is not installed.")
        #expect(missing.sessionBands.first?.extra == "not installed" && missing.sessionBands.first?.items.isEmpty == true)
    }

    @Test("bands: a band holding a waiting session comes first; Gemini CLI follows its reading and goes with a filter")
    func bands() {
        let q = query(report(sessions: [session("a"), session("b", cli: .codex, state: .waiting)]), limits: [entry(.gemini, .notMeasurable)])
        #expect(q.sessionBands.map(\.id) == ["codex", "claude", "gemini"])
        #expect(q.sessionBands.last?.extra == "no log")
        let gone = query(report(), limits: [entry(.gemini, .notInstalled)])
        #expect(gone.sessionBands.last?.extra == "not installed")
        #expect(!query(report(sessions: [session("a")]), filter: filter("claude")).sessionBands.contains { $0.cli == .gemini })
    }

    @Test("sessions rank waiting, not measurable, running, idle; the row's state words are the core's state")
    func rankAndWords() {
        let q = query(report(sessions: [
            session("idle", state: .idle), session("run", tool: CoreActivityTool(name: "Bash", target: "ls")), session("nm", state: .unmeasurable), session("wait", state: .waiting),
        ]))
        #expect(q.sessions.map(\.stateText) == ["waiting", "not measurable", "running Bash", "idle"])
        #expect(ActivitySessionItem(session: session("x")).stateText == "running")
    }

    @Test("Stop is offered only for a session the core can name again: an id ending :unknown cannot authorize it")
    func canStop() {
        #expect(ActivitySessionItem(session: session("pid:52003:1794094352000", cli: .codex)).canStop)
        #expect(!ActivitySessionItem(session: session("pid:52003:unknown", cli: .codex)).canStop)
    }

    // MARK: Today

    @Test("Right now: the cost is the sum of the estimates held, labelled with how many sessions it covers; the age is the oldest plus the time since the read")
    func rightNow() {
        let sessions = [session("a", age: 60_000, cost: 0.5), session("b", age: 3_600_000, cost: 1.25), session("c", age: nil)]
        let read = Self.now.addingTimeInterval(-120)
        let q = ActivityQuery(report: report(sessions: sessions), readAt: read, now: Self.now, calendar: Self.calendar)
        let figures = ActivityFigures.rightNow(q)
        #expect(figures.map(\.value) == ["~$1.75", "1 h 2 min"])
        #expect(figures.map(\.label) == ["estimated cost, 2 of 3 open sessions", "longest-open session"])
        let all = query(report(sessions: [session("a", cost: 2)]))
        #expect(ActivityFigures.rightNow(all).first?.label == "estimated cost, open sessions")
    }

    @Test("Right now has no figure to show without a session, and no cost figure when no session has an estimate")
    func rightNowEmpty() {
        #expect(ActivityFigures.rightNow(query(report())).isEmpty)
        #expect(ActivityFigures.rightNow(query(report(sessions: [session("a", age: nil)]))).isEmpty)
        #expect(ActivityFigures.rightNow(query(report(sessions: [session("a")]))).map(\.label) == ["longest-open session"])
    }

    // MARK: Failed

    @Test("a failure with no later pass is the Answer: the command, the reason, the CLI and what is true of the log")
    func stillFailing() {
        let q = query(report(failures: [failure("1", title: "pnpm test", reason: "2 tests failed"), failure("2", later: true)]))
        let answer = ActivityAnswer.failed(q)
        #expect(answer.sentence == "1 still failing" && answer.more == 0)
        #expect(answer.verdict?.title == "pnpm test" && answer.verdict?.text == "2 tests failed")
        #expect(answer.verdict?.small == "Claude Code. No later run has passed.")
        #expect(q.count(.failed) == 2)
    }

    @Test("several still failing: the one with the most repeats is named; the others are counted")
    func severalFailing() {
        let q = query(report(failures: [failure("1", count: 2), failure("2", count: 9), failure("3", count: 4), failure("4", count: 20, later: true)]))
        let answer = ActivityAnswer.failed(q)
        #expect(answer.sentence == "3 still failing" && answer.more == 2 && answer.verdict?.targetID == "claude:command:2")
        #expect(q.failureBands.first?.stillFailing == 3)
    }

    @Test("nothing still failing: the plain sentence; a passed-later command is a fact about the log and never 'fixed'")
    func nothingFailing() {
        let q = query(report(failures: [failure("1", later: true)]))
        let answer = ActivityAnswer.failed(q)
        #expect(answer.sentence == "No command is still failing." && answer.verdict == nil)
        #expect(ActivityFigures.passedLater(q)?.sentence == "1 command failed, then passed on a later run. One pass is not proof of a fix.")
        #expect(ActivityAnswer.failed(query(report())).sentence == "No command is still failing.")
        #expect(ActivityFigures.passedLater(query(report(failures: [failure("1")]))) == nil)
    }

    @Test("the Failed Answer names the filter, and the filter changes the tab count")
    func failedFilter() {
        let q = query(report(failures: [failure("1"), failure("2", cli: .codex)]), filter: filter("codex"))
        #expect(ActivityAnswer.failed(q).sentence == "1 still failing in Codex" && q.count(.failed) == 1)
        let clean = query(report(failures: [failure("1")]), filter: filter("codex"))
        #expect(ActivityAnswer.failed(clean).sentence == "No command in Codex is still failing.")
    }

    @Test("a dismissal hides the failure from the count, the Answer and Passed later until it fails again")
    func dismissal() {
        let one = failure("1"), two = failure("2", later: true)
        let key1 = ActivityFailureItem(failure: one).dismissKey, key2 = ActivityFailureItem(failure: two).dismissKey
        let q = query(report(failures: [one, two]), dismissed: [key1, key2])
        #expect(q.count(.failed) == 0 && ActivityFigures.passedLater(q) == nil)
        #expect(ActivityAnswer.failed(q).sentence == "No command is still failing.")
        // The same command fails once more: its last time moves on, so the old dismissal does not hold.
        var again = one
        again.last = iso(0.5)
        #expect(query(report(failures: [again, two]), dismissed: [key1, key2]).count(.failed) == 1)
    }

    @Test("the Failed spine's range is read from the failures' own first and last times, never from a window the core does not report")
    func failedRange() {
        let items = [ActivityFailureItem(failure: failure("1", first: 24 * 13, last: 5)), ActivityFailureItem(failure: failure("2", first: 3, last: 2))]
        #expect(ActivityFigures.failedRange(items, calendar: Self.calendar) == "Oct 26 to Nov 8")
        #expect(ActivityFigures.failedRange([ActivityFailureItem(failure: failure("1", first: 3, last: 2))], calendar: Self.calendar) == "Nov 8")
        var untimed = failure("1")
        untimed.first = nil
        untimed.last = nil
        #expect(ActivityFigures.failedRange([ActivityFailureItem(failure: untimed)], calendar: Self.calendar) == nil)
        let q = query(report(failures: [failure("1", first: 24 * 13, last: 5), failure("2")]))
        #expect(ActivityFigures.failedCount(q, calendar: Self.calendar) == "2 commands, Oct 26 to Nov 8")
    }

    @Test("a title the core cut at 120 characters is not whole")
    func cutTitle() {
        let cut = String(repeating: "a", count: 119) + "\u{2026}"
        #expect(ActivityFailureItem(failure: failure("1", title: cut)).isCut)
        #expect(!ActivityFailureItem(failure: failure("1", title: "short\u{2026}")).isCut)
    }

    // MARK: Files

    @Test("the Answer names the file with the most edits over the logs read; no 'today' claim the core cannot support")
    func mostEdited() {
        let q = query(report(files: [file("a.ts", edits: 5), file("src/b.ts", edits: 23), file("c.ts", edits: 23, hoursAgo: 1)]))
        let answer = ActivityAnswer.files(q)
        #expect(answer.sentence == "c.ts is the most-edited file.")
        #expect(q.files.first?.id == "/work/c.ts", "a tie goes to the later edit")
        #expect(answer.verdict?.title == "Edited 23 times" && answer.verdict?.small == "/work/c.ts")
        #expect(ActivityAnswer.files(query(report())).sentence == "No file edits are in the session logs.")
    }

    @Test("files split into 'Edited today' (the last edit is today) and 'Earlier'; with none today the one band is 'Edited files'")
    func fileBands() {
        let q = query(report(files: [file("old.ts", edits: 9, hoursAgo: 60), file("new.ts", edits: 2, hoursAgo: 2)]))
        #expect(q.fileBands.map(\.title) == ["Edited today", "Earlier"] && q.fileBands.first?.items.map(\.name) == ["new.ts"])
        let none = query(report(files: [file("old.ts", edits: 9, hoursAgo: 60)]))
        #expect(none.fileBands.map(\.title) == ["Edited files"])
        #expect(none.files.first?.folder == "" && file("src/x/y.ts", edits: 1).label == "src/x/y.ts")
        #expect(ActivityFileItem(file: file("src/x/y.ts", edits: 1)).folder == "src/x/" && ActivityFileItem(file: file("src/x/y.ts", edits: 1)).name == "y.ts")
    }

    @Test("Busiest projects counts the edits of files one project touched; a file two projects touched is counted nowhere and said so")
    func busiest() {
        let q = query(report(files: [
            file("a.ts", edits: 10, projects: ["spacevibe-api"]), file("b.ts", edits: 4, projects: ["spacevibe-api"]),
            file("c.ts", edits: 30, projects: ["spacevibe-bench"]), file("d.ts", edits: 99, projects: ["spacevibe-api", "spacevibe-bench"]), file("e.ts", edits: 7, projects: []),
        ]))
        let busiest = ActivityFigures.busiest(q)
        #expect(busiest.entries.map(\.name) == ["spacevibe-bench", "spacevibe-api"] && busiest.entries.map(\.edits) == [30, 14] && busiest.skipped == 1)
        #expect(ActivityFigures.skippedNote(1) == "1 file edited in more than one project is not counted here.")
        #expect(ActivityFigures.skippedNote(0) == nil)
        #expect(ActivityFigures.busiestCount(q) == "file edits in 74 logs read")
    }

    // MARK: Stop

    @Test("the Stop confirmation names the real pid, the CLI and the project, and says it cannot be undone")
    func stopConfirmation() {
        let session = session("a", cli: .claude, title: "Fix leaderboard 500", project: "spacevibe-api", pid: 41002)
        #expect(ActivityStopWording.title(session) == "Stop \u{201C}Fix leaderboard 500\u{201D}?")
        #expect(ActivityStopWording.plainMessage(session) == "Sends SIGTERM to pid 41002 (Claude Code, spacevibe-api). Unsaved work in that session may be lost. This cannot be undone.")
        #expect(ActivityStopWording.note == "SpaceVibe checks that the pid still belongs to this session before it sends anything.")
        #expect(ActivityStopWording.confirmTitle == "Stop session")
        let bare = self.session("b", cli: .codex, project: nil, pid: 52003)
        #expect(ActivityStopWording.plainMessage(bare).hasPrefix("Sends SIGTERM to pid 52003 (Codex)."))
    }

    @Test("after a stop the toast says what was sent; a process that outlived the signal is not called stopped")
    func stopToast() {
        let session = session("a", title: "Fix leaderboard 500", pid: 41002)
        #expect(ActivityStopWording.toast(session, exited: true) == "Sent SIGTERM to pid 41002. \u{201C}Fix leaderboard 500\u{201D} is stopped.")
        #expect(ActivityStopWording.toast(session, exited: false) == "Sent SIGTERM to pid 41002, but \u{201C}Fix leaderboard 500\u{201D} is still running.")
    }

    @Test("the v5 tab shows the confirmation over the window while a stop is pending, and the old tab never does")
    func modal() {
        let env = AppEnvironment(toasts: ToastCenter(announce: false))
        let v5 = ActivityTab(env: env, isV5: true)
        #expect(v5.modal == nil)
        v5.model.requestStop(session("a"))
        #expect(v5.modal != nil && v5.model.isMenuOpen)
        let old = ActivityTab(env: env)
        old.model.requestStop(session("a"))
        #expect(old.modal == nil)
    }

    // MARK: Dismissal and its Undo

    private func model(_ report: CoreActivityReport?) -> ActivityModel {
        let model = ActivityModel(env: AppEnvironment(toasts: ToastCenter(announce: false)), isV5: true)
        model.preview(report: report)
        return model
    }

    @Test("Dismiss passed removes the commands that passed later in one step, and one Undo brings them all back")
    func dismissPassedAndUndo() {
        let model = model(report(failures: [failure("1"), failure("2", later: true), failure("3", later: true)]))
        model.dismissPassed()
        #expect(model.query().count(.failed) == 1 && ActivityFigures.passedLater(model.query()) == nil)
        #expect(model.env.toasts.current?.message == "Dismissed 2 commands that passed later" && model.env.toasts.current?.action?.title == "Undo")
        model.env.toasts.runCurrentAction()
        #expect(model.query().count(.failed) == 3 && ActivityFigures.passedLater(model.query())?.count == 2)
    }

    @Test("Dismiss on one failure has its own Undo; Dismiss passed with nothing passed does nothing")
    func dismissOneAndUndo() {
        let model = model(report(failures: [failure("1", title: "pnpm test")]))
        model.dismissPassed()
        #expect(model.env.toasts.current == nil)
        model.dismiss(model.query().failures[0])
        #expect(model.query().count(.failed) == 0 && model.env.toasts.current?.message == "Dismissed \u{201C}pnpm test\u{201D}")
        model.env.toasts.runCurrentAction()
        #expect(model.query().count(.failed) == 1)
    }

    @Test("the v5 sidebar gives Activity no count (V5-R50); the old sidebar keeps its recent-failures badge")
    func badge() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var recent = failure("1")
        recent.last = formatter.string(from: Date().addingTimeInterval(-3600))
        let env = AppEnvironment(toasts: ToastCenter(announce: false))
        let v5 = ActivityTab(env: env, isV5: true)
        v5.model.preview(report: report(failures: [recent]))
        #expect(v5.badge == nil)
        let old = ActivityTab(env: env)
        old.model.preview(report: report(failures: [recent]))
        #expect(old.badge?.value == 1)
    }

    @Test("Copy puts the whole command on the pasteboard; a cut one is refused with a sentence")
    func copy() {
        var copied: [String] = []
        let model = model(report(failures: [failure("1", title: "pnpm test"), failure("2", title: String(repeating: "b", count: 119) + "\u{2026}")]))
        model.copyToPasteboard = { copied.append($0) }
        model.copy(model.query().failures[0])
        #expect(copied == ["pnpm test"] && model.env.toasts.current?.message == "Copied the command.")
        model.copy(model.query().failures[1])
        #expect(copied == ["pnpm test"], "the cut command is not copied")
        #expect(model.env.toasts.current?.message.contains("only has its start") == true)
    }

    @Test("Open on a file shows it in Finder; a file that is gone is said plainly, and nothing is opened")
    func reveal() {
        var shown: [URL] = []
        let model = model(report(files: [file("src/a.ts", edits: 3)]))
        model.revealFile = { url in shown.append(url); return url.path == "/work/src/a.ts" }
        model.reveal(model.query().files[0])
        #expect(shown.map(\.path) == ["/work/src/a.ts"] && model.env.toasts.current == nil)
        model.revealFile = { _ in false }
        model.reveal(model.query().files[0])
        #expect(model.env.toasts.current?.message == "a.ts is no longer at /work/src/a.ts." && model.env.toasts.current?.tone == .danger)
    }

    @Test("keys 1 to 3 pick the tab; a tab change closes the detail and the filter menu")
    func tabs() {
        let model = model(report())
        model.detailID = "x"
        model.isFilterOpen = true
        model.select(index: 1)
        #expect(model.pane == .failed && model.detailID == nil && !model.isFilterOpen)
        model.select(index: 7)
        #expect(model.pane == .failed)
        #expect(ActivityPane.allCases.map(\.hasFilter) == [true, true, false], "Files has no filter (V5-R61)")
    }

    @Test("j and k stop at the first and last row, and a click opens its detail")
    func moving() {
        let model = model(report())
        let rows = ["a", "b", "c"]
        model.move(by: 1, in: rows)
        #expect(model.currentID == "b")
        model.move(by: 5, in: rows)
        model.move(by: -9, in: rows)
        #expect(model.currentID == "a")
        model.open("c")
        #expect(model.currentID == "c" && model.detailID == "c")
        model.toggleDetail(of: "c")
        #expect(model.detailID == nil)
    }
}
