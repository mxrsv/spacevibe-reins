import AppKit
import SwiftUI

/// The v5 Activity shots (`SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=activity`): the real page on the synthetic home in every state
/// of V5-R62, dark and light. The run first checks every figure against what the core's report holds (the V5-A20 trace), then
/// draws:
/// - the real report: `activity-running`, `-running-filtered`, `-running-detail`, `-running-warning`, `-running-limit` (the clock on a running session), `-menu-filter`, `-stop` (the
///   confirmation), `-failed`, `-failed-detail`, `-failed-warning`, `-files`, `-files-detail`;
/// - the states from in-memory reports the fixture cannot show: `-loading`, `-error`, `-stale` (a report with a failed last read, and
///   its popover), `-healthy`, `-nothing-running`, `-many`,
///   `-no-failures`, `-no-files`, `-not-installed`; and the V5-A22 sizes;
/// - two real writes, last: `-stopped` (Stop on the Codex process the fixture can verify: its process list only edits itself, so
///   nothing real is signalled) and `-dismissed` (Dismiss passed with its Undo toast; undone after).
@MainActor
enum ActivityTabShots {
    static func run(into directory: URL) throws {
        let env = AppEnvironment.shared
        let tab = ActivityTab(env: env, isV5: true)
        let model = tab.model
        let agents = AgentsPage(env: env)
        agents.start()
        Task {
            await env.limits.readOnce()
            await model.readOnce()
        }
        try ShotHarness.wait("the Activity read, the CLI readings and the counts", seconds: ShotHarness.settleSeconds) {
            (model.report != nil || model.failure != nil) && env.limits.readAt != nil && agents.counts.total != nil
        }
        guard let real = model.report else { throw ShotHarness.Failure(model.failure ?? "the Activity read returned no report") }
        try check(model, real)

        func shoot(_ name: String, _ choice: AppearanceChoice, tab shown: ActivityTab? = nil, toasts: ToastCenter? = nil, shownSlot: String? = nil,
                   size: CGSize? = nil, limits: LimitsModel? = nil) throws {
            let size = size ?? ShotRenderer.size
            let tabs: [any SpaceVibeTab] = TabRegistry.makeTabs(isV5: true).map { registered in
                registered.id == ActivityTab.tabID ? (shown ?? tab) : (registered is AgentsPage ? agents : registered)
            }
            let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), activeID: ActivityTab.tabID, isV5: true)
            let view = ShellView()
                .environment(limits ?? env.limits)
                .spaceVibeRoot(shell: shell, toasts: toasts ?? ToastCenter(announce: false), env: env)
                .environment(\.shownWarningSlot, shownSlot.map { AnyHashable($0) })
                .environment(\.openStateStore, OpenStateStore())
                .frame(width: size.width, height: size.height)
            try ShotRenderer.write(view, name: name, choice: choice, to: directory)
        }
        func reset(_ model: ActivityModel) {
            model.pane = .running
            model.filter.clear()
            model.detailID = nil
            model.currentID = nil
            model.isFilterOpen = false
            model.pendingStop = nil
        }
        /// A page over an in-memory report: the state the fixture cannot show.
        func synthetic(_ report: CoreActivityReport?, failure: String? = nil, pane: ActivityPane = .running) -> ActivityTab {
            let other = ActivityTab(env: env, isV5: true)
            other.model.preview(report: report, failure: failure)
            other.model.pane = pane
            return other
        }
        let waiting = real.sessions.first { $0.state == .waiting }
        let toolRunning = real.sessions.first { $0.cli == .claude && $0.state == .running && $0.currentTool != nil }
        let stale = synthetic(real, failure: "The session logs could not be read.")
        let fileToShow = ActivityQuery(report: real).files.first?.id
        let failureToShow = ActivityQuery(report: real).failures.first { $0.stillFailing }
        let withoutCodex = LimitsModel(env: env, results: [Self.entry(.claude, .measured), Self.entry(.codex, .notInstalled), Self.entry(.gemini, .notInstalled)])
        let healthy = synthetic(Self.healthy(real))
        let loading = synthetic(nil)
        let error = synthetic(nil, failure: "The session logs could not be read.")
        let nothing = synthetic(Self.with(real) { $0.sessions = [] })
        let many = synthetic(Self.many(real))
        let noFailures = synthetic(Self.with(real) { $0.failures = [] }, pane: .failed)
        let noFiles = synthetic(Self.with(real) { $0.files = [] }, pane: .files)
        let notInstalled = synthetic(Self.with(real) { $0.sessions = $0.sessions.filter { $0.cli == .claude } })
        notInstalled.model.limitsResults = { withoutCodex.results }
        notInstalled.model.toggleFilter("codex")

        for choice in [AppearanceChoice.dark, .light] {
            func snap(_ name: String, tab shown: ActivityTab? = nil, toasts: ToastCenter? = nil, shownSlot: String? = nil, size: CGSize? = nil,
                      limits: LimitsModel? = nil) throws {
                try shoot(name, choice, tab: shown, toasts: toasts, shownSlot: shownSlot, size: size, limits: limits)
            }
            reset(model)
            try snap("activity-running")
            model.toggleFilter("codex")
            try snap("activity-running-filtered")
            reset(model)
            if let waiting {
                model.open("\(waiting.cli.rawValue):\(waiting.id)")
                try snap("activity-running-detail")
                model.detailID = nil
                try snap("activity-running-warning", shownSlot: "\(ActivityCanvas.page):warn:\(waiting.cli.rawValue):\(waiting.id)")
                model.requestStop(waiting)
                try snap("activity-stop")
                model.cancelStop()
            }
            if let toolRunning {
                // A running session with a tool open: the clock says the log would not show an approval wait.
                try snap("activity-running-limit", shownSlot: "\(ActivityCanvas.page):warn:\(toolRunning.cli.rawValue):\(toolRunning.id)")
            }
            reset(model)
            model.isFilterOpen = true
            try snap("activity-menu-filter")
            reset(model)
            model.select(.failed)
            try snap("activity-failed")
            if let failureToShow {
                model.open(failureToShow.id)
                try snap("activity-failed-detail")
                model.detailID = nil
                try snap("activity-failed-warning", shownSlot: "\(ActivityCanvas.page):warn:\(failureToShow.id)")
            }
            reset(model)
            model.select(.files)
            try snap("activity-files")
            if let fileToShow {
                model.open(fileToShow)
                try snap("activity-files-detail")
            }
            reset(model)
            try snap("activity-loading", tab: loading)
            try snap("activity-error", tab: error)
            try snap("activity-stale", tab: stale)
            try snap("activity-stale-popover", tab: stale, shownSlot: "\(ActivityCanvas.page):stale")
            try snap("activity-healthy", tab: healthy)
            try snap("activity-nothing-running", tab: nothing)
            try snap("activity-many", tab: many)
            try snap("activity-no-failures", tab: noFailures)
            try snap("activity-no-files", tab: noFiles)
            try snap("activity-not-installed", tab: notInstalled, limits: withoutCodex)
            // V5-A22: below 700 pt of canvas the halves stack; and a window shorter than the cards.
            try snap("activity-narrow", size: CGSize(width: 960, height: 600))
            try snap("activity-narrow-tall", size: CGSize(width: 960, height: 1600))
            try snap("activity-short", size: CGSize(width: 1062, height: 685))
            try snap("activity-many-short", tab: many, size: CGSize(width: 1062, height: 685))
        }

        try writes(model, real, shoot: { name, choice, toasts in try shoot(name, choice, toasts: toasts) }, reset: reset)
    }

    // MARK: The real writes

    /// Dismiss passed with its Undo, then Stop on the waiting session (the fixture's process list only edits itself).
    private static func writes(_ model: ActivityModel, _ real: CoreActivityReport,
                               shoot: (String, AppearanceChoice, ToastCenter?) throws -> Void,
                               reset: (ActivityModel) -> Void) throws {
        let env = model.env
        reset(model)
        model.select(.failed)
        let before = model.query().failures.count
        let passed = model.query().failures.filter { !$0.stillFailing }.count
        try ShotHarness.check(passed > 0, "the fixture has a command that passed later")
        model.dismissPassed()
        let dismissedToast = env.toasts.current
        try ShotHarness.check(dismissedToast?.message == ActivityFigures.dismissedPassedLabel(passed) && dismissedToast?.action?.title == "Undo",
                              "Dismiss passed says \(dismissedToast?.message ?? "nothing") and carries Undo")
        try ShotHarness.check(model.query().failures.count == before - passed && ActivityFigures.passedLater(model.query()) == nil,
                              "the dismissed commands leave the tab count, the list and the Passed later card")
        for choice in [AppearanceChoice.dark, .light] { try shoot("activity-dismissed", choice, env.toasts) }
        env.toasts.runCurrentAction()
        try ShotHarness.check(model.query().failures.count == before, "Undo brings every dismissed command back")
        env.toasts.dismiss()

        reset(model)
        // The fixture's Claude Code status files carry no `procStart`, so the core (rightly) cannot verify them and answers 404; the
        // one session it can verify is the Codex process with no rollout yet (its id binds the pid to a start time).
        guard let session = real.sessions.first(where: { $0.id.hasPrefix("pid:") && !$0.id.hasSuffix(":unknown") }) else {
            throw ShotHarness.Failure("no stoppable session in the fixture")
        }
        model.requestStop(session)
        model.confirmStop()
        try ShotHarness.wait("the stop and its toast") { env.toasts.current != nil && model.pendingStop == nil && !model.isStopping }
        let toast = env.toasts.current
        try ShotHarness.check(toast?.message == ActivityStopWording.toast(session, exited: true) && toast?.action == nil,
                              "the toast says \(toast?.message ?? "nothing") with no Undo")
        try ShotHarness.check(toast?.message.contains("pid \(session.pid)") == true, "the toast names the real pid \(session.pid)")
        try ShotHarness.wait("the re-read after the stop") { model.report?.sessions.contains { $0.id == session.id && $0.state != .ended } == false }
        for choice in [AppearanceChoice.dark, .light] { try shoot("activity-stopped", choice, env.toasts) }
        env.toasts.dismiss()
    }

    // MARK: Synthetic reports

    private static func entry(_ cli: CoreLimitsCLI, _ state: CoreLimitsState) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: cli, state: state, plan: nil, source: nil, at: state == .measured ? Date().timeIntervalSince1970 : nil, windows: [])
    }

    private static func with(_ report: CoreActivityReport, _ change: (inout CoreActivityReport) -> Void) -> CoreActivityReport {
        var copy = report
        change(&copy)
        return copy
    }

    /// Nothing waits and every failure has a later pass.
    private static func healthy(_ report: CoreActivityReport) -> CoreActivityReport {
        with(report) { copy in
            copy.sessions = copy.sessions.map { session in
                var session = session
                if session.state == .waiting { session.state = .running }
                return session
            }
            copy.failures = copy.failures.map { failure in
                var failure = failure
                failure.laterPass = failure.last
                return failure
            }
        }
    }

    /// Thirty-odd sessions made from the real ones: other titles and ids, every fifth idle, two waiting.
    private static func many(_ report: CoreActivityReport) -> CoreActivityReport {
        guard let base = report.sessions.first(where: { $0.state == .running }) else { return report }
        let more = (0 ..< 32).map { index -> CoreActivitySession in
            var session = base
            session.cli = index % 2 == 0 ? .claude : .codex
            session.id = "synthetic-\(index)"
            session.title = "\(index % 2 == 0 ? "Refine" : "Port") task \(String(format: "%02d", index + 1))"
            session.state = index % 5 == 3 ? .idle : (index == 7 || index == 18 ? .waiting : .running)
            session.pid = 60000 + index
            return session
        }
        return with(report) { $0.sessions += more }
    }

    // MARK: The V5-A20 trace

    /// Each figure the page shows against the report it comes from: the fixture's values, the derived values and the text shown.
    private static func check(_ model: ActivityModel, _ real: CoreActivityReport) throws {
        let query = model.query()
        let live = real.sessions.filter { $0.state != .ended }
        for session in live {
            print("trace: session \(session.cli.rawValue) pid \(session.pid) \(session.state.rawValue) cost \(session.cost.map { String($0.usd) } ?? "none") age \(session.ageMs.map { String(Int($0)) } ?? "none") ms")
        }
        try ShotHarness.check(query.count(.running) == live.count, "the Running tab counts the \(live.count) open sessions")
        try ShotHarness.check(ActivityTab(model: model).badge == nil, "the v5 sidebar shows no count beside Activity (V5-R50)")
        let limited = query.sessions.filter { $0.cannotSee != nil && !$0.isUnmeasurable }
        print("trace: approval limit shown on \(limited.map { "\($0.session.cli.rawValue) pid \($0.session.pid)" })")
        try ShotHarness.check(limited.count == live.filter { $0.cli == .claude && $0.state == .running && $0.currentTool != nil }.count + live.filter { $0.cli == .codex && $0.state == .running && $0.currentTool != nil }.count,
                              "every running session with a tool open carries its CLI's approval limit")
        let running = ActivityAnswer.running(query)
        let waiting = live.filter { $0.state == .waiting }
        print("trace: Answer running \"\(running.sentence ?? "nil")\", verdict \(running.verdict?.title ?? "none"): \(running.verdict?.text ?? "") \(running.verdict?.small ?? ""), more \(running.more)")
        try ShotHarness.check(running.sentence == "\(waiting.count) waiting for you", "the Running Answer counts the waiting sessions")
        let costs = live.compactMap { $0.cost?.usd }
        let figures = ActivityFigures.rightNow(query)
        print("trace: Right now \(figures.map { "\($0.value) \($0.label)" })")
        try ShotHarness.check(figures.first?.value == ActivityFormat.cost(costs.reduce(0, +)) && figures.first?.label.contains("\(costs.count) of \(live.count)") == (costs.count != live.count),
                              "the cost is the sum of the \(costs.count) estimates the report holds, labelled with how many sessions it covers")

        let failures = query.failures
        print("trace: failures \(failures.map { "\($0.failure.cli.rawValue) \($0.failure.title.prefix(24)) x\($0.failure.count) \($0.statusText)" })")
        try ShotHarness.check(query.count(.failed) == real.failures.count, "the Failed tab counts the \(real.failures.count) failures listed")
        let still = real.failures.filter { $0.laterPass == nil }
        try ShotHarness.check(ActivityAnswer.failed(query).sentence == "\(still.count) still failing", "the Failed Answer counts the failures with no later pass")
        print("trace: Failed count \"\(ActivityFigures.failedCount(query))\", Passed later \(ActivityFigures.passedLater(query)?.sentence ?? "none")")
        try ShotHarness.check(ActivityFigures.passedLater(query)?.count == real.failures.count - still.count, "Passed later counts the failures that have a later pass")

        let files = query.files
        let answer = ActivityAnswer.files(query)
        print("trace: Files \(files.map { "\($0.file.label) \($0.file.edits)" }); Answer \"\(answer.sentence ?? "nil")\" \(answer.verdict?.title ?? "") \(answer.verdict?.text ?? "")")
        try ShotHarness.check(query.count(.files) == real.files.count && answer.sentence == "\(files[0].name) is the most-edited file." && files[0].file.edits == real.files.map(\.edits).max(),
                              "the Files Answer names the file with the most edits")
        let busiest = ActivityFigures.busiest(query)
        print("trace: Busiest \(busiest.entries.map { "\($0.name) \($0.edits)" }), skipped \(busiest.skipped), count \"\(ActivityFigures.busiestCount(query))\"")
        let single = real.files.filter { $0.projects.count == 1 }.map(\.edits).reduce(0, +)
        try ShotHarness.check(busiest.entries.map(\.edits).reduce(0, +) == single, "Busiest projects adds the edits of the single-project files")
    }
}
