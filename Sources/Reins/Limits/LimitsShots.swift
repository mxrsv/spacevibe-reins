import AppKit
import SwiftUI

/// `REINS_SHOT_SCREEN=limits`: the sidebar block on a demo shell and the detail, read from the synthetic home, in both
/// appearances. `REINS_FIXTURE_LIMITS=typical|edge` (scripts/fixture-home.mjs) chooses what the files say.
@MainActor
enum LimitsShots {
    static func run(into directory: URL) throws {
        let env = AppEnvironment.shared
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the Limits read") { env.limits.readAt != nil }
        try ShotHarness.check(env.limits.results.count == 3, "Limits read Claude Code, Codex and Gemini CLI")
        for choice in [AppearanceChoice.dark, .light] {
            let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
            let toasts = ToastCenter(announce: false)
            try ShotRenderer.write(
                ShellView().reinsRoot(shell: shell, toasts: toasts, env: env).frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height),
                name: "limits-sidebar", choice: choice, to: directory
            )
            try ShotRenderer.write(
                LimitsDetail().reinsRoot(shell: shell, toasts: toasts, env: env).environment(\.colorScheme, choice.colorScheme),
                name: "limits-detail", choice: choice, to: directory, fullHeight: true
            )
            env.limits.showInactive = true
            try ShotRenderer.write(
                LimitsDetail().reinsRoot(shell: shell, toasts: toasts, env: env),
                name: "limits-detail-inactive", choice: choice, to: directory, fullHeight: true
            )
            env.limits.showInactive = false
        }
    }
}
