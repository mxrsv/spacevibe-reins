import AppKit
import SwiftUI

/// `REINS_SHOT_SCREEN=settings`: Settings over the demo shell in both appearances, every Update state, the Large font
/// size, and the demo tabs at Large, where the fixed text columns would truncate first. Synthetic data only; nothing is
/// read or saved, and the updater never starts.
@MainActor
enum SettingsShots {
    static func run(into directory: URL) throws {
        let env = AppEnvironment.shared
        let updates = env.updates
        updates.version = "0.1.0"
        updates.build = "1"
        let checked = Calendar.current.date(bySettingHour: 9, minute: 14, second: 0, of: Date()) ?? Date()
        let states: [(String, UpdateController.Status)] = [
            ("not-checked", .notChecked),
            ("up-to-date", .upToDate),
            ("checking", .checking),
            ("available", .available(version: "0.2.0")),
            ("failed", .failed),
            ("unavailable", .unavailable("This build has no update source. Install a release build to receive updates.")),
        ]

        for choice in [AppearanceChoice.dark, .light] {
            let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
            let toasts = ToastCenter(announce: false)
            shell.select("rules")
            shell.openSettings()
            try ShotHarness.check(shell.isSettingsOpen && shell.settingsSection == .appearance, "Settings opens on Appearance")
            try write(shell, toasts, env, "settings-appearance", choice, to: directory)

            shell.appearance.theme = .system
            try write(shell, toasts, env, "settings-appearance-system", choice, to: directory)
            shell.appearance.theme = ThemeSetting(choice)

            try atLarge(shell) { try write(shell, toasts, env, "settings-appearance-large", choice, to: directory) }

            shell.settingsSection = .update
            for (name, status) in states {
                let running: Bool
                if case .unavailable = status { running = false } else { running = true }
                updates.isRunning = running
                updates.automaticChecks = running
                updates.status = status
                updates.lastCheck = status == .notChecked ? nil : checked
                try write(shell, toasts, env, "settings-update-\(name)", choice, to: directory)
            }

            shell.openPalette()
            try ShotHarness.check(shell.isSettingsOpen && shell.isPaletteOpen, "the palette opens over Settings")
            try write(shell, toasts, env, "settings-palette", choice, to: directory)
            shell.select("loadout")
            try ShotHarness.check(!shell.isSettingsOpen && !shell.isPaletteOpen, "choosing a tab closes Settings")

            for tab in ["loadout", "activity", "rules"] {
                shell.select(tab)
                try atLarge(shell) { try write(shell, toasts, env, "large-\(tab)", choice, to: directory) }
            }
        }
    }

    /// The Large step for one shot; the shot store is not the app's, so the step is set here and put back.
    private static func atLarge(_ shell: ShellModel, _ shot: () throws -> Void) throws {
        shell.appearance.fontSize = .large
        TypeScale.shared.step = FontSizeChoice.large.step
        defer {
            TypeScale.shared.step = FontSizeChoice.standard.step
            shell.appearance.fontSize = .standard
        }
        try shot()
    }

    private static func write(_ shell: ShellModel, _ toasts: ToastCenter, _ env: AppEnvironment, _ name: String,
                              _ choice: AppearanceChoice, to directory: URL) throws {
        let view = ShellView()
            .reinsRoot(shell: shell, toasts: toasts, env: env)
            .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
        try ShotRenderer.write(view, name: name, choice: choice, to: directory)
    }
}
