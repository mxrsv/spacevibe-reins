import AppKit
import SwiftUI

/// The v5 shell's shots (`SPACEVIBE_UI_V5=1`): `SPACEVIBE_SHOT_SCREEN=shell` draws the window on every page, with the palette,
/// the toast and Settings; `skills`, `subagents` and `hooks` draw the Agents page with that tab selected. They read the
/// synthetic home like the other real-screen runs: the counts and the CLI status rows are the fixture's own, and each shot
/// run checks them against what the engine returned (V5-A20) before drawing.
@MainActor
enum ShellShots {
    static func run(into directory: URL, tab: AgentsCategory?) throws {
        let env = AppEnvironment.shared
        let tabs = TabRegistry.makeTabs(isV5: true)
        guard let page = tabs.compactMap({ $0 as? AgentsPage }).first else { throw ShotHarness.Failure("the v5 registry has no Agents page") }
        page.start()
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the counts and the CLI reads") {
            page.counts.total != nil && page.counts.rules != nil && env.limits.readAt != nil
        }
        try check(page: page, limits: env.limits.results)

        for choice in [AppearanceChoice.dark, .light] {
            func shell(_ configure: (ShellModel) -> Void = { _ in }) -> ShellModel {
                let model = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), isV5: true)
                configure(model)
                return model
            }
            if let tab {
                page.select(tab)
                try write(shell(), env, tab.rawValue, choice, to: directory)
                continue
            }
            for category in AgentsCategory.allCases {
                page.select(category)
                try write(shell(), env, "shell-agents-\(category.rawValue)", choice, to: directory)
            }
            page.select(.skills)
            try write(shell { $0.select(TabRegistry.activityID) }, env, "shell-activity", choice, to: directory)
            try write(shell { $0.select(TabRegistry.limitsID) }, env, "shell-limits", choice, to: directory)
            try write(shell { $0.openPalette() }, env, "shell-palette", choice, to: directory)
            try write(shell { $0.openPalette(query: "set") }, env, "shell-palette-filtered", choice, to: directory)
            try write(shell { $0.openPalette(query: "zzz") }, env, "shell-palette-empty", choice, to: directory)
            try write(shell { $0.openSettings() }, env, "shell-settings", choice, to: directory)
            let toasts = ToastCenter(announce: false)
            toasts.show("Removed ponytail", undo: {})
            try write(shell(), env, "shell-toast", choice, to: directory, toasts: toasts)
        }
    }

    /// The V5-A20 trace: the numbers the sidebar and the tabs show equal what the engine returned for this fixture.
    private static func check(page: AgentsPage, limits: [CoreLimitsEntry]) throws {
        let counts = page.counts
        print("trace: skills \(counts.skills.map(String.init) ?? "-"), subagents \(counts.subagents.map(String.init) ?? "-"), hooks \(counts.hooks.map(String.init) ?? "-"), rules \(counts.rules.map(String.init) ?? "-"), total \(counts.total.map(String.init) ?? "-")")
        try ShotHarness.check(counts.skills != nil && counts.total == (counts.skills ?? 0) + (counts.subagents ?? 0) + (counts.hooks ?? 0),
                              "the Agents total is the skills, subagents and hooks together")
        try ShotHarness.check(page.badge?.value == counts.total, "the sidebar's Agents count is that total")
        for entry in limits {
            let state = CLIStatusDerivation.state(of: entry)
            print("trace: \(entry.cli.label) limits \(entry.state.rawValue) -> \(state?.label ?? "no state drawn")")
        }
        try ShotHarness.check(limits.count == CoreLimitsCLI.allCases.count, "one status row per CLI")
    }

    private static func write(_ shell: ShellModel, _ env: AppEnvironment, _ name: String, _ choice: AppearanceChoice,
                              to directory: URL, toasts: ToastCenter? = nil) throws {
        let view = ShellView()
            .spaceVibeRoot(shell: shell, toasts: toasts ?? ToastCenter(announce: false), env: env)
            .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
        try ShotRenderer.write(view, name: name, choice: choice, to: directory)
    }
}
