import AppKit
import SwiftUI

/// The v5 Skills shots (`SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=skills`): the real tab on the synthetic home, in every state the
/// plan names, dark and light. The run first checks every skill's sessions against what `scripts/fixture-home.mjs` writes into
/// the logs (the V5-A20 trace), then draws:
/// - `skills-page`, `-filtered`, `-grouped` (by status), `-multi` (two rows picked and the bottom bar, before any write), `-multi-added` (after the real bulk add on the synthetic home: Codex lit, the toast with Undo above the bar; undone after), `-warning`
///   (the popover of a never-ran skill open), `-menu-filter`, `-menu-view`, `-nothing-matches`, `-empty` (an in-memory scope with
///   no skills), `-read-failed` (the inventory could not be read);
/// - the pane states `-pane-heavy`, `-pane-both`, `-pane-one`, `-pane-never`, `-pane-never-both`, `-pane-new`, `-pane-plugin`.
@MainActor
enum SkillsShots {
    /// What `scripts/fixture-home.mjs` writes: Claude Code sessions, Codex sessions (nil: not in Codex) per skill, in the order
    /// the list must show them (sessions desc, then name). `neon-postgres` is the plugin's skill. `skill-creator` keeps a fresh
    /// file, so it reads `Never ran` with the neutral clock.
    private static let fixture: [(name: String, claude: Int, codex: Int?)] = [
        ("ponytail", 142, nil), ("impeccable", 87, 31), ("diagnosing-bugs", 23, nil), ("explain", 17, 6), ("kyant-kanban", 9, 2),
        ("neon-postgres", 11, nil), ("tdd", 4, nil), ("review-change", 0, nil), ("skill-creator", 0, nil), ("webapp-testing", 0, 0),
    ]
    /// Total sessions descending, ties by name.
    private static let expectedOrder = ["ponytail", "impeccable", "diagnosing-bugs", "explain", "kyant-kanban", "neon-postgres", "tdd",
                                        "review-change", "skill-creator", "webapp-testing"]

    static func run(into directory: URL) throws {
        let env = AppEnvironment.shared
        let page = AgentsPage(env: env)
        page.select(.skills)
        page.start()
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the inventory and the usage scan", seconds: ShotHarness.settleSeconds) {
            page.loadout.isSettled && page.loadout.usageResult != nil && env.limits.readAt != nil
        }
        try check(page, env: env)

        let model = page.skills
        func shoot(_ name: String, _ choice: AppearanceChoice, toasts: ToastCenter? = nil, shownSlot: String? = nil,
                   page shown: AgentsPage? = nil, _ configure: () -> Void = {}) throws {
            configure()
            let used = shown ?? page
            let tabs = TabRegistry.makeTabs(isV5: true).map { $0 is AgentsPage ? used : $0 }
            let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), isV5: true)
            let view = ShellView()
                .spaceVibeRoot(shell: shell, toasts: toasts ?? ToastCenter(announce: false), env: env)
                .environment(\.shownWarningSlot, shownSlot.map { AnyHashable($0) })
                .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
            try ShotRenderer.write(view, name: name, choice: choice, to: directory)
        }
        func reset() {
            model.query = SkillsQuery()
            model.clearPicks()
            model.isFilterOpen = false
            model.isViewOpen = false
            model.isScopeOpen = false
            model.select("skill::ponytail")
        }

        for choice in [AppearanceChoice.dark, .light] {
            func snap(_ name: String, toasts: ToastCenter? = nil, shownSlot: String? = nil, page shown: AgentsPage? = nil,
                      _ configure: () -> Void = {}) throws {
                try shoot(name, choice, toasts: toasts, shownSlot: shownSlot, page: shown, configure)
            }

            reset()
            try snap("skills-page")

            try snap("skills-filtered") { model.toggleFilter(.status, "neverRan") }
            try snap("skills-filtered-two") { model.toggleFilter(.cli, "one") }
            reset()
            try snap("skills-grouped") { model.query.group = .status }
            try snap("skills-grouped-tier") { model.query.group = .tier }
            reset()

            // Two rows picked and the bar over them, before any write: both are in Claude Code only, so Codex is dim everywhere.
            try snap("skills-multi") {
                model.togglePick("skill::ponytail")
                model.togglePick("skill::diagnosing-bugs")
            }
            reset()
            try snap("skills-warning", shownSlot: "skills:warn:skill::review-change") { model.select("skill::review-change") }
            reset()
            try snap("skills-menu-filter") { model.isFilterOpen = true }
            reset()
            try snap("skills-menu-view") { model.isViewOpen = true }
            reset()

            for (name, key) in [("heavy", "ponytail"), ("both", "impeccable"), ("one", "diagnosing-bugs"), ("never", "review-change"),
                                ("never-both", "webapp-testing"), ("new", "skill-creator"), ("plugin", "neon-postgres")] {
                try snap("skills-pane-\(name)") { model.select("skill::\(key)") }
            }
            reset()

            try snap("skills-nothing-matches") {
                model.toggleFilter(.status, "heavy")
                model.toggleFilter(.owner, "plugin")
            }
            reset()
            let empty = AgentsPage(env: env, loadout: LoadoutModel(env: env, data: LoadoutData(
                rows: [], scopes: [LoadoutScope(value: LoadoutRows.globalScope, label: "Global")], countsByScope: [:], problems: [],
                events: [:], globalCount: 0, home: nil)))
            empty.select(.skills)
            try snap("skills-empty", page: empty) {}
            // The inventory could not be read at all: the core's sentence and `Try again`, never a skeleton that does not end.
            let failed = AgentsPage(env: env, loadout: LoadoutModel(env: env, data: nil, readFailure: "No ~/.claude or ~/.codex folder could be read."))
            failed.select(.skills)
            try snap("skills-read-failed", page: failed) {}
        }

        // The real bulk add on the synthetic home, once, then the state it leaves in both appearances: Codex lit on both rows and
        // in the bar, the toast with Undo above the bar. Undone straight after, so the home ends as it began.
        reset()
        model.togglePick("skill::ponytail")
        model.togglePick("skill::diagnosing-bugs")
        let before = model.pickedRows
        try ShotHarness.check(before.count == 2 && !model.isLit(before, cli: .codex), "two skills picked, Codex dim on both before the write")
        model.toggleBulk(before, cli: .codex)
        try ShotHarness.wait("the bulk add's toast") { env.toasts.current != nil }
        try ShotHarness.check(env.toasts.current?.message == "Added 2 skills to Codex", "the toast says \(env.toasts.current?.message ?? "nothing")")
        try ShotHarness.wait("the re-read after the add") { page.loadout.isSettled && model.isLit(model.pickedRows, cli: .codex) }
        try ShotHarness.check(env.toasts.current?.action != nil, "the toast carries Undo")
        if let ponytail = model.rows.first(where: { $0.name == "ponytail" }) {
            let verdict = SkillsWording.verdict(for: ponytail, status: model.status(of: ponytail, among: model.rows), detected: model.detected)
            print("trace: ponytail in Claude Code and Codex, sessions \(ponytail.skillUsage.sessions(in: .claude) ?? -1) and \(ponytail.skillUsage.sessions(in: .codex) ?? -1): \(verdict?.text ?? "none"); \(verdict?.small ?? "")")
            try ShotHarness.check(verdict?.text == "Ran only in Claude Code. One of the busiest skills you have.",
                                  "a skill in both CLIs with sessions in one is \"all in Claude Code\", not \"across both CLIs\"")
        }
        env.toasts.isOverBottomBar = true
        for choice in [AppearanceChoice.dark, .light] { try shoot("skills-multi-added", choice, toasts: env.toasts) }
        env.toasts.runCurrentAction()
        try ShotHarness.wait("Undo and its re-read") {
            env.toasts.current?.message == "Undid Added 2 skills to Codex" && page.loadout.isSettled && !model.isLit(model.pickedRows, cli: .codex)
        }
        try ShotHarness.check(!model.isLit(model.pickedRows, cli: .codex), "Undo put both skills back to Claude Code only")
        env.toasts.isOverBottomBar = false
        env.toasts.dismiss()
        reset()
    }

    // MARK: The V5-A20 trace

    /// Per skill and CLI: the sessions the fixture writes, the core's own total (`usage.scan`), the row's cell and the pane's
    /// figure; they must agree. Then the list order and the status words.
    private static func check(_ page: AgentsPage, env: AppEnvironment) throws {
        let model = page.skills
        let usage = try requireUsage(page)
        let rows = model.rows
        let now = Date()
        for entry in fixture {
            guard let row = rows.first(where: { $0.name == entry.name }) else { throw ShotHarness.Failure("no row for \(entry.name)") }
            let usageRow = row.skillUsage
            for (cli, expected) in [(CoreCLI.claude, entry.claude as Int?), (CoreCLI.codex, entry.codex)] {
                let scanned = (cli == .claude ? usage.totals.claude : usage.totals.codex).skill[entry.name]?.sessions ?? 0
                let cell = usageRow.cells[cli] ?? .missing
                let meter = SkillsWording.meter(for: row, cli: cli, maxSessions: model.maxSessions, now: now)
                let shown = meter.figure.map { "\($0)" } ?? "-"
                print("trace: \(entry.name) \(cli.rawValue): fixture \(expected.map(String.init) ?? "not installed"), usage.scan \(scanned), cell \(cell), shown \(shown)")
                guard let expected else {
                    try ShotHarness.check(cell == .missing && meter.figure == nil, "\(entry.name) is not in \(cli.label): a dash, never a zero")
                    continue
                }
                try ShotHarness.check(scanned == expected, "\(entry.name) \(cli.label): usage.scan says \(expected) sessions")
                switch cell {
                case .sessions(let n, _): try ShotHarness.check(n == expected && meter.figure == expected, "\(entry.name) \(cli.label): the cell and the figure show \(expected)")
                case .added: try ShotHarness.check(expected == 0 && meter.figure == 0, "\(entry.name) \(cli.label): newly added shows 0 with the clock")
                default: throw ShotHarness.Failure("\(entry.name) \(cli.label): cell \(cell) is neither counted nor newly added")
                }
            }
        }
        let order = model.layout.rows.map(\.name)
        try ShotHarness.check(order == expectedOrder, "the list is ordered by sessions descending, ties by name: \(order.joined(separator: ", "))")
        let words = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, model.status(of: $0, among: rows).title) })
        print("trace: statuses \(expectedOrder.map { "\($0)=\(words[$0] ?? "?")" }.joined(separator: ", "))")
        try ShotHarness.check(words["ponytail"] == "Heavily used" && words["review-change"] == "Never ran" && words["skill-creator"] == "Never ran"
            && words["webapp-testing"] == "Never ran" && words["tdd"] == "Ran", "the status words follow the sessions")
        try ShotHarness.check(rows.first { $0.name == "skill-creator" }?.skillUsage.added != nil, "skill-creator reads as newly added (fresh file), not as a plain Never ran")
        try ShotHarness.check(rows.first { $0.name == "neon-postgres" }?.plugin != nil, "neon-postgres is plugin-owned, so read-only")
        try ShotHarness.check(model.detected == [.claude, .codex], "the logo strip lists the detected CLIs")
        print("trace: usage note \(page.loadout.usageNote)")
    }

    private static func requireUsage(_ page: AgentsPage) throws -> CoreUsageResult {
        guard let usage = page.loadout.usageResult else { throw ShotHarness.Failure("no usage scan result") }
        return usage
    }
}
