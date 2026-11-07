import AppKit
import SwiftUI

/// `SPACEVIBE_SHOT_SCREEN=limits`: the sidebar block on a demo shell, then the Limits page it opens, read from the synthetic
/// home, in both appearances. `SPACEVIBE_FIXTURE_LIMITS=typical|edge` (scripts/fixture-home.mjs) chooses what the files say.
@MainActor
enum LimitsShots {
    static func run(into directory: URL) throws {
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
}
