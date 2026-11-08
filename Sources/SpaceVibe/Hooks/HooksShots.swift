import AppKit
import SwiftUI

/// The v5 Hooks shots (`SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=hooks`): the real tab on the synthetic home and the states the
/// fixture cannot hold, dark and light. The run first checks every hook's runs against what `scripts/fixture-home.mjs` writes into
/// the logs (the V5-A20 trace), then draws:
/// - `hooks-page`, `-filtered`, `-detail` (a dead hook's popover), `-detail-both`, `-warning` (the danger popover), `-menu-filter`,
///   `-nothing-matches`, `-removed` (after the real Remove of a dead hook on the synthetic home: the toast with Undo; undone after);
/// - the states from in-memory data: `-sample` (a mock-like set: shared, Claude Code-only and Codex-only events, a hook only Codex
///   has, a plugin's, two dead), `-sample-detail`, `-sample-why`, `-sample-clock`, `-healthy`, `-many` (60), `-none`, `-no-codex`,
///   `-loading`, `-read-failed`, `-narrow`, `-short`.
@MainActor
enum HooksShots {
    /// What `scripts/fixture-home.mjs` writes: event, matcher, script, Claude Code runs, dead.
    private static let fixture: [(event: String, script: String, runs: Int, dead: Bool)] = [
        ("PreToolUse", "guard-destructive.sh", 412, false), ("PreToolUse", "block-env-edit.sh", 96, false),
        ("PostToolUse", "prettier --write \"$FILE\"", 1204, false), ("SessionStart", "load-context.sh", 58, false),
        ("Stop", "notify-done.sh", 203, false), ("Stop", "notify.sh", 0, true), ("PostToolUse", "tsc-watch.sh", 0, true),
    ]

    static func run(into directory: URL) throws {
        let env = AppEnvironment.shared
        let page = AgentsPage(env: env)
        page.select(.hooks)
        page.start()
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the inventory and the usage scan", seconds: ShotHarness.settleSeconds) {
            page.loadout.isSettled && page.loadout.usageResult != nil && env.limits.readAt != nil
        }
        try check(page)
        guard let real = page.loadout.data else { throw ShotHarness.Failure("no inventory") }

        let model = page.hooks
        func shoot(_ name: String, _ choice: AppearanceChoice, toasts: ToastCenter? = nil, shownSlot: String? = nil,
                   page shown: AgentsPage? = nil, store: OpenStateStore = OpenStateStore(), size: CGSize? = nil,
                   limits: LimitsModel? = nil, _ configure: () -> Void = {}) throws {
            configure()
            let size = size ?? ShotRenderer.size
            let used = shown ?? page
            let tabs = TabRegistry.makeTabs(isV5: true).map { $0 is AgentsPage ? used : $0 }
            let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), isV5: true)
            let view = ShellView()
                .environment(limits ?? env.limits)
                .spaceVibeRoot(shell: shell, toasts: toasts ?? ToastCenter(announce: false), env: env)
                .environment(\.shownWarningSlot, shownSlot.map { AnyHashable($0) })
                .environment(\.openStateStore, store)
                .frame(width: size.width, height: size.height)
            try ShotRenderer.write(view, name: name, choice: choice, to: directory)
        }
        func reset() {
            model.query = HooksQuery()
            model.detailKey = nil
            model.isFilterOpen = false
            model.isWhyOpen = false
            model.currentKey = nil
        }
        /// A page over in-memory rows: the state the fixture cannot show.
        func synthetic(_ rows: [LoadoutRow]?, limits: LimitsModel? = nil) -> AgentsPage {
            let others = real.rows.filter { $0.kind != .hook && $0.project == nil }.count
            let data = rows.map { LoadoutData(rows: real.rows.filter { $0.kind != .hook } + $0, scopes: real.scopes, countsByScope: [:], problems: [],
                                              events: real.events, globalCount: $0.count + others, home: real.home) }
            let synthetic = AgentsPage(env: env, loadout: LoadoutModel(env: env, data: data))
            synthetic.select(.hooks)
            if let limits { synthetic.hooks.limitsResults = { limits.results } }
            return synthetic
        }
        let sampleRows = HooksSynthetic.rows(HooksSynthetic.sample, events: real.events)
        let sample = synthetic(sampleRows)
        let healthy = synthetic(HooksSynthetic.rows(HooksSynthetic.sample.filter { !$0.dead }, events: real.events))
        let many = synthetic(HooksSynthetic.rows(HooksSynthetic.many, events: real.events))
        let none = synthetic([])
        let loading = synthetic(nil)
        let failed = AgentsPage(env: env, loadout: LoadoutModel(env: env, data: nil, readFailure: "No ~/.claude or ~/.codex folder could be read."))
        failed.select(.hooks)
        let withoutCodex = LimitsModel(env: env, results: [Self.entry(.claude, installed: true), Self.entry(.codex, installed: false),
                                                          CoreLimitsEntry(cli: .gemini, state: .notMeasurable, plan: nil, source: nil, at: nil, windows: [])])
        let noCodex = synthetic(HooksSynthetic.rows(HooksSynthetic.sample.filter { $0.clis == [.claude] }, events: real.events), limits: withoutCodex)
        let deadKey = model.rows.first { $0.isDeadHook }?.key ?? ""
        let bothKey = model.rows.first { $0.presentCLIs.count == 2 }?.key ?? ""

        for choice in [AppearanceChoice.dark, .light] {
            func snap(_ name: String, toasts: ToastCenter? = nil, shownSlot: String? = nil, page shown: AgentsPage? = nil,
                      store: OpenStateStore = OpenStateStore(), size: CGSize? = nil, limits: LimitsModel? = nil,
                      _ configure: () -> Void = {}) throws {
                try shoot(name, choice, toasts: toasts, shownSlot: shownSlot, page: shown, store: store, size: size, limits: limits, configure)
            }

            reset()
            try snap("hooks-page")
            try snap("hooks-filtered") { model.toggleFilter(.status, "cantRun") }
            reset()
            try snap("hooks-detail") { model.open(deadKey) }
            reset()
            let bothOpen = OpenStateStore()
            bothOpen.setOpen(true, page: HooksModel.page, id: "event:Stop")
            try snap("hooks-detail-both", store: bothOpen) { model.open(bothKey) }
            reset()
            try snap("hooks-warning", shownSlot: model.rows.first { $0.isDeadHook }.map(HooksCanvas.slotID)) {}
            reset()
            try snap("hooks-menu-filter") { model.isFilterOpen = true }
            reset()
            try snap("hooks-nothing-matches") { model.toggleFilter(.cli, "codex") }
            reset()
            try snap("hooks-sample", page: sample)
            let sampleModel = sample.hooks
            // `auto-allow-read` is a hook only Codex has, on an event both CLIs have: Codex's runs read Unmeasurable (the clock), and
            // Claude Code can take it. Its band is closed by default, so these shots open it.
            let codexOnly = sampleRows.first { $0.hookTitle == "auto-allow-read.sh" }
            let openBand = OpenStateStore()
            openBand.setOpen(true, page: HooksModel.page, id: "event:PermissionRequest")
            try snap("hooks-sample-detail", page: sample, store: openBand) { if let codexOnly { sampleModel.open(codexOnly.key) } }
            sampleModel.detailKey = nil
            try snap("hooks-sample-why", page: sample) { sampleModel.isWhyOpen = true }
            sampleModel.isWhyOpen = false
            try snap("hooks-sample-clock", shownSlot: codexOnly.map(HooksCanvas.slotID), page: sample, store: openBand)
            // Every band of the sample open.
            let allOpen = OpenStateStore()
            for event in Set(sampleRows.map(\.hookEvent)) { allOpen.setOpen(true, page: HooksModel.page, id: "event:\(event)") }
            // `Codex only` leaves the Codex-only events, short enough to show: `Interrupt` carries Codex's logo, `PermissionRequest` none.
            try snap("hooks-sample-codex-only", page: sample, store: allOpen) { sampleModel.toggleFilter(.cli, "codex") }
            sampleModel.clearFilters()
            try snap("hooks-healthy", page: healthy)
            try snap("hooks-many", page: many)
            try snap("hooks-none", page: none)
            try snap("hooks-no-codex", page: noCodex, limits: withoutCodex)
            try snap("hooks-loading", page: loading)
            try snap("hooks-read-failed", page: failed)
            // A copy into Claude Code carries the matcher note; its words are the wording function's, the same as the write's.
            let copyToast = ToastCenter(announce: false)
            copyToast.show("\(HooksWording.copyLabel(sampleRows[0], to: .claude)). \(HooksWording.matcherNote)", undo: {})
            try snap("hooks-toast", toasts: copyToast, page: sample)
            // V5-A22: a window below 700 pt of canvas (the halves stack), and one shorter than the cards.
            try snap("hooks-narrow", size: CGSize(width: 960, height: 600))
            try snap("hooks-short", size: CGSize(width: 1062, height: 685))
            try snap("hooks-many-short", page: many, size: CGSize(width: 1062, height: 685))
        }

        // The real Remove of a dead hook on the synthetic home, once, then the state it leaves in both appearances: the hook gone and
        // the toast with Undo. Undone straight after, and the settings file compared byte for byte.
        reset()
        let settings = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? "").appendingPathComponent("settings.json")
        let before = try Data(contentsOf: settings)
        guard let dead = model.rows.first(where: { $0.hookTitle == "notify.sh" }) else { throw ShotHarness.Failure("no dead notify.sh") }
        model.remove(dead)
        try ShotHarness.wait("the remove's toast") { env.toasts.current != nil }
        try ShotHarness.check(env.toasts.current?.message == HooksWording.removeLabel(dead, from: nil) && env.toasts.current?.action != nil,
                              "the toast says \"\(env.toasts.current?.message ?? "nothing")\" and carries Undo")
        try ShotHarness.wait("the re-read after the remove") { page.loadout.isSettled && !model.rows.contains { $0.key == dead.key } }
        let opened = OpenStateStore()
        opened.setOpen(true, page: HooksModel.page, id: "event:Stop")
        for choice in [AppearanceChoice.dark, .light] { try shoot("hooks-removed", choice, toasts: env.toasts, store: opened) }
        env.toasts.runCurrentAction()
        try ShotHarness.wait("Undo and its re-read") {
            env.toasts.current?.message == "Undid \(HooksWording.removeLabel(dead, from: nil))" && page.loadout.isSettled
                && model.rows.contains { $0.key == dead.key }
        }
        try ShotHarness.check(try Data(contentsOf: settings) == before, "Undo put settings.json back byte for byte")
        env.toasts.dismiss()
        reset()
    }

    private static func entry(_ cli: CoreCLI, installed: Bool) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: CoreLimitsCLI(cli), state: installed ? .measured : .notInstalled, plan: nil, source: nil,
                         at: installed ? Date().timeIntervalSince1970 : nil, windows: [])
    }

    // MARK: The V5-A20 trace

    /// Per hook: the runs the fixture writes, the core's own total (`usage.scan`), the row's cell and the text the detail shows;
    /// they must agree. Codex's cell is `Unmeasurable`, never a number. Then the Answer, the bands and the two small cards.
    private static func check(_ page: AgentsPage) throws {
        let model = page.hooks
        guard let usage = page.loadout.usageResult else { throw ShotHarness.Failure("no usage scan result") }
        let rows = model.rows
        for entry in fixture {
            guard let row = rows.first(where: { $0.hookTitle == entry.script && $0.hookEvent == entry.event }),
                  let hook = row.hookMembers[.claude] else { throw ShotHarness.Failure("no row for \(entry.script)") }
            let scanned = usage.totals.claude.hook[hook.hash]?.runs ?? 0
            let run = row.hookRun(in: .claude)
            print("trace: \(entry.script) claude: fixture \(entry.runs), usage.scan \(scanned), cell \(run), detail \"\(HooksWording.runs(run))\"")
            try ShotHarness.check(scanned == entry.runs, "\(entry.script): usage.scan says \(entry.runs) runs")
            try ShotHarness.check(entry.runs == 0 ? run == .neverRan : run == .ran(entry.runs, last: run.lastDay), "\(entry.script): the cell shows \(entry.runs)")
            try ShotHarness.check(HooksWording.runs(run) == (entry.runs == 0 ? "never ran" : "\(entry.runs) runs"), "\(entry.script): the detail reads \"\(HooksWording.runs(run))\"")
            try ShotHarness.check(row.isDeadHook == entry.dead, "\(entry.script): dead is \(entry.dead)")
        }
        guard let stop = rows.first(where: { $0.hookTitle == "notify-done.sh" }) else { throw ShotHarness.Failure("no notify-done.sh") }
        print("trace: notify-done.sh codex: cell \(stop.hookRun(in: .codex)), detail \"\(HooksWording.runs(stop.hookRun(in: .codex)))\"")
        try ShotHarness.check(stop.presentCLIs.count == 2 && stop.hookRun(in: .codex) == .unmeasurable, "Codex's Stop hook reads Unmeasurable, no number")
        let answer = model.answer
        print("trace: Answer \"\(answer.sentence ?? "nil")\", dead \(answer.dead.map(\.hookTitle)), more \(answer.more), missing \(answer.missing.map(\.hookTitle))")
        try ShotHarness.check(answer.sentence == "2 hooks can't run." && answer.more == 0 && answer.missing.isEmpty, "the Answer counts the two dead hooks")
        let bands = model.layout.bands.map { "\($0.event)\($0.lead.map { " (\($0.label) only)" } ?? ""): \($0.rows.map(\.hookTitle).joined(separator: ", "))" }
        print("trace: bands \(bands.joined(separator: " | "))")
        let cant = model.cantCopy.entries.map { "\($0.row.hookTitle) (\(HooksWording.short($0.block)))" }
        print("trace: Can't copy to Codex \(cant.joined(separator: ", ")); Missing in Codex \(model.missing.rows.map(\.hookTitle))")
        try ShotHarness.check(model.missing.isEmpty, "SpaceVibe writes no hook into Codex, so nothing is \"missing in Codex\" that it could copy")
        try ShotHarness.check(page.counts.hooks == rows.count, "the tab's count is the number of hooks listed")
        try ShotHarness.check(model.detected == [.claude, .codex], "the logo strip lists the detected CLIs")
    }
}

private extension HookRun {
    var lastDay: String? {
        if case .ran(_, let last) = self { last } else { nil }
    }
}
