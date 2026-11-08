import AppKit
import SwiftUI

/// The v5 Subagents shots (`SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=subagents`): the real tab on the synthetic home, in every
/// state of V5-R62, dark and light. The run first checks every subagent's sessions against what `scripts/fixture-home.mjs`
/// writes into the logs (the V5-A20 trace), then draws:
/// - `subagents-page`, `-filtered`, `-flat` (Group: None), `-detail` (a row's popover open), `-warning` (the never-ran popover),
///   `-menu-filter`, `-menu-group`, `-nothing-matches`;
/// - the states from in-memory data the fixture cannot show: `-none`, `-loading`, `-no-codex`, `-many` (40, one plugin-owned),
///   `-healthy`, `-several` (three never ran), `-read-failed`;
/// - `-added` (after the real add to Codex on the synthetic home: the toast with Undo and Codex lit; undone after).
@MainActor
enum SubagentsShots {
    /// What `scripts/fixture-home.mjs` writes: Claude Code sessions and Codex sessions (nil: not in Codex) per subagent.
    /// `architect` is a 60 days old file with no session, so it reads `Never ran` with the triangle.
    private static let fixture: [(name: String, claude: Int, codex: Int?)] = [
        ("typescript-reviewer", 34, nil), ("react-reviewer", 19, nil), ("database-reviewer", 6, nil), ("security-reviewer", 3, 1),
        ("architect", 0, nil),
    ]

    static func run(into directory: URL) throws {
        let env = AppEnvironment.shared
        let page = AgentsPage(env: env)
        page.select(.subagents)
        page.start()
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the inventory and the usage scan", seconds: ShotHarness.settleSeconds) {
            page.loadout.isSettled && page.loadout.usageResult != nil && env.limits.readAt != nil
        }
        try check(page, env: env)
        guard let real = page.loadout.data else { throw ShotHarness.Failure("no inventory") }

        let model = page.subagents
        func shoot(_ name: String, _ choice: AppearanceChoice, toasts: ToastCenter? = nil, shownSlot: String? = nil,
                   page shown: AgentsPage? = nil, store: OpenStateStore = OpenStateStore(), size: CGSize? = nil,
                   limits: LimitsModel? = nil, _ configure: () -> Void = {}) throws {
            configure()
            let size = size ?? ShotRenderer.size
            let used = shown ?? page
            let tabs = TabRegistry.makeTabs(isV5: true).map { $0 is AgentsPage ? used : $0 }
            let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), isV5: true)
            // A state with its own CLI reading (Codex not installed) puts it in the environment, so the sidebar says what the page does.
            let view = ShellView()
                .environment(limits ?? env.limits)
                .spaceVibeRoot(shell: shell, toasts: toasts ?? ToastCenter(announce: false), env: env)
                .environment(\.shownWarningSlot, shownSlot.map { AnyHashable($0) })
                .environment(\.openStateStore, store)
                .frame(width: size.width, height: size.height)
            try ShotRenderer.write(view, name: name, choice: choice, to: directory)
        }
        func reset() {
            model.query = SubagentsQuery()
            model.detailKey = nil
            model.isFilterOpen = false
            model.isGroupOpen = false
            model.currentKey = nil
            model.detailKey = nil
        }
        /// A page over in-memory rows: the state the fixture cannot show.
        func synthetic(_ rows: [LoadoutRow]?, limits: LimitsModel? = nil) -> AgentsPage {
            let others = real.rows.filter { $0.kind != .agent && $0.project == nil }.count
            let data = rows.map { LoadoutData(rows: real.rows.filter { $0.kind != .agent } + $0, scopes: real.scopes, countsByScope: [:], problems: [], events: real.events,
                                              globalCount: $0.count + others, home: real.home) }
            let synthetic = AgentsPage(env: env, loadout: LoadoutModel(env: env, data: data))
            synthetic.select(.subagents)
            if let limits { synthetic.subagents.limitsResults = { limits.results } }
            return synthetic
        }
        let agents = real.rows.filter { $0.kind == .agent && $0.project == nil }
        let none = synthetic([])
        let loading = synthetic(nil)
        let failed = AgentsPage(env: env, loadout: LoadoutModel(env: env, data: nil, readFailure: "No ~/.claude or ~/.codex folder could be read."))
        failed.select(.subagents)
        let withoutCodex = LimitsModel(env: env, results: [Self.entry(.claude, installed: true), Self.entry(.codex, installed: false),
                                                          CoreLimitsEntry(cli: .gemini, state: .notMeasurable, plan: nil, source: nil, at: nil, windows: [])])
        let noCodex = synthetic(Self.claudeOnly(agents), limits: withoutCodex)
        let many = synthetic(Self.many(agents, count: 40))
        let healthy = synthetic(Self.healthy(agents))
        let several = synthetic(Self.several(agents))

        for choice in [AppearanceChoice.dark, .light] {
            func snap(_ name: String, toasts: ToastCenter? = nil, shownSlot: String? = nil, page shown: AgentsPage? = nil,
                      store: OpenStateStore = OpenStateStore(), size: CGSize? = nil, limits: LimitsModel? = nil,
                      _ configure: () -> Void = {}) throws {
                try shoot(name, choice, toasts: toasts, shownSlot: shownSlot, page: shown, store: store, size: size, limits: limits, configure)
            }

            reset()
            try snap("subagents-page")
            try snap("subagents-filtered") { model.toggleFilter(.status, "neverRan") }
            reset()
            try snap("subagents-flat") { model.query.group = .none }
            reset()
            try snap("subagents-detail") { model.open("agent::typescript-reviewer") }
            reset()
            let bothOpen = OpenStateStore()
            bothOpen.setOpen(true, page: SubagentsModel.page, id: "presence:both")
            try snap("subagents-detail-both", store: bothOpen) { model.open("agent::security-reviewer") }
            reset()
            try snap("subagents-warning", shownSlot: SubagentsCanvas.slotID(agents.first { $0.name == "architect" } ?? agents[0])) {
                model.open("agent::architect")
                model.detailKey = nil
            }
            reset()
            try snap("subagents-menu-filter") { model.isFilterOpen = true }
            reset()
            try snap("subagents-menu-group") { model.isGroupOpen = true }
            reset()
            try snap("subagents-nothing-matches") { model.toggleFilter(.owner, "plugin") }
            reset()
            try snap("subagents-none", page: none)
            try snap("subagents-loading", page: loading)
            try snap("subagents-read-failed", page: failed)
            try snap("subagents-no-codex", page: noCodex, limits: withoutCodex)
            try snap("subagents-many", page: many)
            try snap("subagents-healthy", page: healthy)
            try snap("subagents-several", page: several)
            // The toast of an add into Claude Code (the synthetic home has no Codex-only subagent to write from): its words are the
            // wording function's, the same as the write's.
            let claudeToast = ToastCenter(announce: false)
            claudeToast.show("Added codex-helper to Claude Code. \(SubagentsWording.addNote(to: .claude))", undo: {})
            try snap("subagents-toast-claude", toasts: claudeToast)
            // V5-A22: a window below 700 pt of canvas (the halves stack), and one shorter than the cards.
            try snap("subagents-narrow", size: CGSize(width: 960, height: 600))
            try snap("subagents-narrow-tall", size: CGSize(width: 960, height: 1600))
            try snap("subagents-short", size: CGSize(width: 1062, height: 685))
            try snap("subagents-many-short", page: many, size: CGSize(width: 1062, height: 685))
        }

        // The real add on the synthetic home, once, then the state it leaves in both appearances: Codex lit, the toast with Undo.
        // Undone straight after, so the home ends as it began.
        reset()
        guard let row = model.rows.first(where: { $0.name == "typescript-reviewer" }) else { throw ShotHarness.Failure("no typescript-reviewer") }
        try ShotHarness.check(row.members[.codex] == nil && model.mode(row, cli: .codex) == .toggles, "Codex is dim and can be switched on")
        model.toggle(row, cli: .codex)
        try ShotHarness.wait("the add's toast") { env.toasts.current != nil }
        let message = env.toasts.current?.message
        try ShotHarness.check(message == "Added typescript-reviewer to Codex. \(SubagentsWording.addNote(to: .codex))", "the toast says \(message ?? "nothing")")
        try ShotHarness.wait("the re-read after the add") {
            page.loadout.isSettled && model.rows.first { $0.name == "typescript-reviewer" }?.members[.codex] != nil
        }
        try ShotHarness.check(env.toasts.current?.action != nil, "the toast carries Undo")
        // The row moved to `In both`; its band is open here, as it is for a user who had opened it.
        let opened = OpenStateStore()
        opened.setOpen(true, page: SubagentsModel.page, id: "presence:both")
        for choice in [AppearanceChoice.dark, .light] { try shoot("subagents-added", choice, toasts: env.toasts, store: opened) }
        env.toasts.runCurrentAction()
        try ShotHarness.wait("Undo and its re-read") {
            env.toasts.current?.message == "Undid Added typescript-reviewer to Codex" && page.loadout.isSettled
                && model.rows.first { $0.name == "typescript-reviewer" }?.members[.codex] == nil
        }
        try ShotHarness.check(true, "Undo put typescript-reviewer back to Claude Code only")
        env.toasts.dismiss()
        reset()
    }

    // MARK: Synthetic states

    private static func entry(_ cli: CoreCLI, installed: Bool) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: CoreLimitsCLI(cli), state: installed ? .measured : .notInstalled, plan: nil, source: nil,
                         at: installed ? Date().timeIntervalSince1970 : nil, windows: [])
    }

    /// The same subagents as if Codex was not installed: its copies and cells are gone.
    private static func claudeOnly(_ rows: [LoadoutRow]) -> [LoadoutRow] {
        rows.compactMap { row in
            guard row.members[.claude] != nil else { return nil }
            var row = row
            row.members[.codex] = nil
            row.cells.codex = .missing
            return row
        }
    }

    /// Every subagent has run.
    private static func healthy(_ rows: [LoadoutRow]) -> [LoadoutRow] {
        rows.map { row in
            var row = row
            if case .counted(0, let last, let errors) = row.cells.claude { row.cells.claude = .counted(runs: 3, last: last ?? "2026-11-05", errors: errors) }
            return row
        }
    }

    /// Three never ran (the Answer says so and names the first; the other two are marked in the list).
    private static func several(_ rows: [LoadoutRow]) -> [LoadoutRow] {
        rows.map { row in
            var row = row
            if row.name == "database-reviewer" || row.name == "react-reviewer" { row.cells.claude = .counted(runs: 0, last: nil, errors: nil) }
            return row
        }
    }

    /// `count` subagents made from the real ones: other names and counts, every fourth in both CLIs, one owned by a plugin.
    private static func many(_ rows: [LoadoutRow], count: Int) -> [LoadoutRow] {
        guard let one = rows.first(where: { $0.presentCLIs == [.claude] }), let both = rows.first(where: { $0.presentCLIs.count == 2 }) else { return rows }
        return (0 ..< count).map { index in
            var row = index % 4 == 3 ? both : one
            let name = index < rows.count ? rows[index].name : "\(rows[index % rows.count].name)-\(index / rows.count + 1)"
            row.name = name
            row.key = "agent::\(name)"
            let sessions = index % 9 == 5 ? 0 : (index * 7 + 3) % 47
            row.cells.claude = .counted(runs: sessions, last: sessions == 0 ? nil : "2026-11-0\(index % 8 + 1)", errors: nil)
            if row.presentCLIs.count == 2 { row.cells.codex = .counted(runs: index % 5, last: "2026-11-02", errors: nil) }
            if index == 6 { row.plugin = "neon" }
            return row
        }
    }

    // MARK: The V5-A20 trace

    /// Per subagent and CLI: the sessions the fixture writes, the core's own total (`usage.scan`), the row's cell and the text the
    /// row shows; they must agree. Then the Answer, the list order, the slot and the `In one CLI only` card.
    private static func check(_ page: AgentsPage, env: AppEnvironment) throws {
        let model = page.subagents
        guard let usage = page.loadout.usageResult else { throw ShotHarness.Failure("no usage scan result") }
        let rows = model.rows
        for entry in fixture {
            guard let row = rows.first(where: { $0.name == entry.name }) else { throw ShotHarness.Failure("no row for \(entry.name)") }
            let cells = row.skillUsage
            for (cli, expected) in [(CoreCLI.claude, entry.claude as Int?), (CoreCLI.codex, entry.codex)] {
                let scanned = (cli == .claude ? usage.totals.claude : usage.totals.codex).agent[entry.name]?.sessions ?? 0
                let cell = cells.cells[cli] ?? .missing
                print("trace: \(entry.name) \(cli.rawValue): fixture \(expected.map(String.init) ?? "not installed"), usage.scan \(scanned), cell \(cell)")
                guard let expected else {
                    try ShotHarness.check(cell == .missing, "\(entry.name) is not in \(cli.label): a missing cell, never a zero")
                    continue
                }
                try ShotHarness.check(scanned == expected, "\(entry.name) \(cli.label): usage.scan says \(expected) sessions")
                switch cell {
                case .sessions(let n, _): try ShotHarness.check(n == expected, "\(entry.name) \(cli.label): the cell shows \(expected)")
                case .added: try ShotHarness.check(expected == 0, "\(entry.name) \(cli.label): newly added shows 0 with the clock")
                default: throw ShotHarness.Failure("\(entry.name) \(cli.label): cell \(cell) is neither counted nor newly added")
                }
            }
            print("trace: \(entry.name) row text \"\(SubagentsWording.sessionsText(row))\", slot \(SubagentsWording.slot(for: row)?.mark.label ?? "none")")
        }
        let answer = model.answer
        print("trace: Answer \"\(answer.sentence ?? "nil")\", verdict \(answer.verdict?.name ?? "none"): \(answer.verdict?.text ?? "") \(answer.verdict?.small ?? ""), more \(answer.more)")
        try ShotHarness.check(answer.sentence == "1 subagent never ran." && answer.verdict?.name == "architect" && answer.more == 0,
                              "the Answer names the one subagent that never ran")
        let order = model.layout.groups.map { "\($0.title): \($0.rows.map(\.name).joined(separator: ", "))" }
        print("trace: bands \(order.joined(separator: " | "))")
        try ShotHarness.check(order == ["Claude Code only: architect, typescript-reviewer, react-reviewer, database-reviewer", "In both: security-reviewer"],
                              "the band holding the never-ran subagent comes first; rows by sessions")
        let addable = model.addable
        print("trace: In one CLI only \(addable.entries.map(\.row.name).joined(separator: ", ")); not listed \(addable.leftOut.joined(separator: ", "))")
        try ShotHarness.check(addable.entries.map(\.row.name) == ["typescript-reviewer", "react-reviewer", "database-reviewer"]
                              && addable.leftOut == ["architect (never ran)"], "In one CLI only lists the three that ran; the never-ran one is named as left out")
        try ShotHarness.check(model.detected == [.claude, .codex], "the logo strip lists the detected CLIs")
        try ShotHarness.check(page.counts.subagents == rows.count, "the tab's count is the number of subagents listed")
        print("trace: usage note \(page.loadout.usageNote)")
    }
}
