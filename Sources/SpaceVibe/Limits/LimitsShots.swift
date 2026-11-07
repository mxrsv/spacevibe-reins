import AppKit
import SwiftUI

/// `SPACEVIBE_SHOT_SCREEN=limits`, read from the synthetic home in both appearances; `SPACEVIBE_FIXTURE_LIMITS=typical|edge`
/// (scripts/fixture-home.mjs) chooses what the files say. Without the v5 switch: the sidebar block on a demo shell, then the
/// Limits page it opens. With `SPACEVIBE_UI_V5=1`: the v5 Limits page (`runV5`).
@MainActor
enum LimitsShots {
    static func run(into directory: URL) throws {
        if LaunchMode.uiV5Enabled() {
            try runV5(into: directory)
            return
        }
        let env = AppEnvironment.shared
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the Limits read") { env.limits.readAt != nil }
        try ShotHarness.check(env.limits.results.count == 3, "Limits read Claude Code, Codex and Gemini CLI")
        let entries = LimitsWording.entries(env.limits.results, showInactive: false)
        // Both fixture variants put the least left in the Codex weekly window (39% typical, 4% edge).
        try ShotHarness.check(env.limits.selection(in: entries, now: Date()) == "codex:secondary", "the page selects the window with the least left")
        for choice in [AppearanceChoice.dark, .light] {
            let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
            let toasts = ToastCenter(announce: false)
            try ShotRenderer.write(page(shell, toasts, env), name: "limits-sidebar", choice: choice, to: directory)
            shell.openLimits()
            try ShotHarness.check(shell.isLimitsOpen && shell.title == LimitsPage.title, "the sidebar block's action opens the page")
            try ShotRenderer.write(page(shell, toasts, env), name: "limits-page", choice: choice, to: directory)
            env.limits.showInactive = true
            try ShotRenderer.write(page(shell, toasts, env), name: "limits-page-inactive", choice: choice, to: directory)
            env.limits.showInactive = false
            // Claude Code's entry carries the source line with `Copy /usage` (a window), or its state note (no reading).
            env.limits.selectedID = entries.first { $0.cli == .claude }?.id
            try ShotRenderer.write(page(shell, toasts, env), name: "limits-page-claude", choice: choice, to: directory)
            // The edge fixture has a window past its reset: the dash figure, the dashed ruler and "Reset was".
            if let passed = entries.first(where: { $0.window.map { !$0.current } ?? false }) {
                env.limits.selectedID = passed.id
                try ShotRenderer.write(page(shell, toasts, env), name: "limits-page-passed", choice: choice, to: directory)
            }
            env.limits.selectedID = nil
            shell.select("rules")
            try ShotHarness.check(!shell.isLimitsOpen, "choosing a tab closes the page")
        }
    }

    private static func page(_ shell: ShellModel, _ toasts: ToastCenter, _ env: AppEnvironment) -> some View {
        ShellView()
            .spaceVibeRoot(shell: shell, toasts: toasts, env: env)
            .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
    }

    // MARK: v5

    /// A window narrow enough that the canvas (inside its 32 edge) is under 700 pt, so the halves stack (V5-R52).
    private static var narrow: CGSize { CGSize(width: 900, height: ShotRenderer.size.height) }
    /// Tall enough that nothing scrolls: where each card ends, for the fit at 1440 x 900 (V5-A22).
    private static var tall: CGSize { CGSize(width: ShotRenderer.size.width, height: 1400) }
    private static var narrowTall: CGSize { CGSize(width: 900, height: 1600) }

    /// The v5 window on its Limits page, read from the synthetic home: the V5-A20 trace printed and checked against the
    /// engine's DTOs, then the page, Show unused, a tall and a narrow window, and the V5-R62 states the fixture cannot hold,
    /// drawn from in-memory readings (`states`).
    private static func runV5(into directory: URL) throws {
        let env = AppEnvironment.shared
        let tabs = TabRegistry.makeTabs(isV5: true)
        let agents = tabs.compactMap { $0 as? AgentsPage }.first
        agents?.start()
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the Limits read and the Agents counts") { env.limits.readAt != nil && agents?.counts.total != nil }
        try ShotHarness.check(env.limits.results.map(\.cli) == CoreLimitsCLI.allCases, "Limits read Claude Code, Codex and Gemini CLI, in that order")
        try trace(env.limits.results, now: Date())

        for choice in [AppearanceChoice.dark, .light] {
            func write(_ model: LimitsModel, _ name: String, size: CGSize? = nil) throws {
                let size = size ?? ShotRenderer.size
                let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), activeID: TabRegistry.limitsID, isV5: true)
                let view = ShellView()
                    .environment(model)
                    .spaceVibeRoot(shell: shell, toasts: ToastCenter(announce: false), env: env)
                    .frame(width: size.width, height: size.height)
                try ShotRenderer.write(view, name: name, choice: choice, to: directory)
            }
            try write(env.limits, "limits-page")
            try write(env.limits, "limits-tall", size: tall)
            try write(env.limits, "limits-narrow", size: narrow)
            try write(env.limits, "limits-narrow-tall", size: narrowTall)
            env.limits.showInactive = true
            try write(env.limits, "limits-unused")
            env.limits.showInactive = false
            for (name, model) in states(env, now: Date()) { try write(model, "limits-state-\(name)") }
        }
    }

    /// V5-A20: every window the engine returned, its fields and what the page shows for it, with the direction checked (the
    /// share shown is 100 minus `usedPercent`, a window past its reset shows none); then the Answer, Next resets and Source.
    private static func trace(_ results: [CoreLimitsEntry], now: Date) throws {
        let all = LimitsAnswer(.read(results), showUnused: true, now: now)
        for entry in results {
            let age = entry.reading.map { LimitsWording.readAge(at: $0.at, now: now) } ?? "-"
            print("trace: \(entry.cli.rawValue) state \(entry.state.rawValue), plan \(entry.plan ?? "null"), at \(entry.at.map { String($0) } ?? "null") (\(age))")
            let rows: [LimitsAnswer.WindowRow]
            if let band = all.bands.first(where: { $0.cli == entry.cli }), case .windows(let listed) = band.body { rows = listed } else { rows = [] }
            for window in entry.windows {
                let row = rows.first { $0.id == "\(entry.cli.rawValue):\(window.id)" }
                let expected: Int? = window.current ? Int(max(0, 100 - window.usedPercent).rounded()) : nil
                print("trace: \(entry.cli.rawValue) \(window.id): usedPercent \(window.usedPercent), current \(window.current), active \(window.active), resetsAt \(window.resetsAt) -> \"\(row?.name ?? "?")\" \(row?.left.map { "\($0)%" } ?? "\u{2014}")\(row?.warning.map { " [\($0.mark.label)]" } ?? "")")
                try ShotHarness.check(row != nil && row?.left == expected, "\(entry.cli.rawValue) \(window.id) shows the share left (100 - used), or none past its reset")
            }
        }
        let page = LimitsAnswer(.read(results), showUnused: false, now: now)
        print("trace: answer \"\(page.sentence ?? "-")\" | \(page.verdict.map { "\($0.title). \($0.text)\($0.small.map { " / \($0)" } ?? "")" } ?? "-")")
        print("trace: next resets \(page.resets?.map { "\($0.time) \($0.title)" }.joined(separator: "; ") ?? "-")")
        print("trace: source \(page.sources.map { "\($0.name) \($0.state)" }.joined(separator: "; "))")
        print("trace: bands \(page.bands.map { "\($0.cli.rawValue) count \($0.count.map(String.init) ?? "-")\($0.mark.map { " [\($0.label)]" } ?? "")\($0.staleAge.map { " \($0)" } ?? "")" }.joined(separator: "; "))")
        try ShotHarness.check(page.resets?.count == page.bands.reduce(0) { total, band in
            guard case .windows(let rows) = band.body else { return total }
            return total + rows.filter { $0.left != nil }.count
        }, "Next resets lists every shown window whose reset is still ahead, once")
    }

    /// The V5-R62 states (`b-limits` presets) as in-memory readings, relative to `now`; the fixture's two variants cover the
    /// sample, a stale read, a reset passed, no reading yet and Gemini CLI not installed from real files.
    private static func states(_ env: AppEnvironment, now: Date) -> [(String, LimitsModel)] {
        let t = now.timeIntervalSince1970
        let hour = 3600.0, day = 86_400.0
        func window(_ id: String, _ minutes: Int?, scope: String? = nil, used: Double, resets: Double, active: Bool = true) -> CoreLimitWindow {
            CoreLimitWindow(id: id, minutes: minutes, scope: scope, usedPercent: used, resetsAt: t + resets, active: active, current: resets > 0)
        }
        func claude(_ windows: [CoreLimitWindow], ago: Double = 120) -> CoreLimitsEntry {
            CoreLimitsEntry(cli: .claude, state: .measured, plan: nil, source: .claudeStatusline, at: t - ago, windows: windows)
        }
        func codex(_ windows: [CoreLimitWindow], ago: Double = 120) -> CoreLimitsEntry {
            CoreLimitsEntry(cli: .codex, state: .measured, plan: "plus", source: nil, at: t - ago, windows: windows)
        }
        func state(_ cli: CoreLimitsCLI, _ state: CoreLimitsState) -> CoreLimitsEntry {
            CoreLimitsEntry(cli: cli, state: state, plan: nil, source: nil, at: nil, windows: [])
        }
        func claudeSample(used: [Double], fiveHourResets: Double = 2 * hour + 40 * 60) -> [CoreLimitWindow] {
            [window("five_hour", 300, used: used[0], resets: fiveHourResets),
             window("seven_day", 10080, used: used[1], resets: 5 * day + 18 * hour),
             window("seven_day_opus", 10080, scope: "Opus", used: used[2], resets: 5 * day + 18 * hour),
             window("seven_day_sonnet", 10080, scope: "Sonnet", used: 0, resets: 5 * day + 18 * hour, active: false)]
        }
        func codexSample(used: [Double]) -> [CoreLimitWindow] {
            [window("primary", 300, used: used[0], resets: hour + 20 * 60), window("secondary", 10080, used: used[1], resets: 3 * day + 2 * hour)]
        }
        let gemini = state(.gemini, .notMeasurable)
        let sample = [claude(claudeSample(used: [22, 59, 88])), codex(codexSample(used: [36, 7])), gemini]
        let many = (0 ..< 22).map { index in
            window("model_\(index)", 10080, scope: String(format: "Model %02d", index + 1), used: Double([12, 36, 59, 77, 91, 97, 28, 45][index % 8]),
                   resets: 5 * day - Double(index) * 3 * hour)
        }
        func model(_ results: [CoreLimitsEntry], failure: String? = nil) -> LimitsModel {
            LimitsModel(env: env, results: results, failure: failure)
        }
        return [
            ("healthy", model([claude(claudeSample(used: [12, 29, 36])), codex(codexSample(used: [8, 3])), gemini])),
            ("low", model([claude(claudeSample(used: [86, 91, 94])), codex(codexSample(used: [82, 97])), gemini])),
            ("many", model([claude(claudeSample(used: [22, 59, 88]) + many), codex(codexSample(used: [36, 7]) + many), gemini])),
            ("stale", model([sample[0], codex(codexSample(used: [36, 7]), ago: 8 * hour), gemini])),
            ("unknown", model([claude(claudeSample(used: [22, 59, 88], fiveHourResets: -30 * 60)), sample[1], gemini])),
            ("none", model([sample[0], state(.codex, .notRecorded), gemini])),
            ("missing", model([sample[0], state(.codex, .notInstalled), gemini])),
            ("unreadable", model([state(.claude, .unreadable), sample[1], gemini])),
            ("failed", model([], failure: "The limits could not be read.")),
            ("loading", model([])),
        ]
    }
}
