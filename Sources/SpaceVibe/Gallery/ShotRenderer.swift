import AppKit
import SwiftUI

/// Headless screenshots (`SPACEVIBE_SHOT_DIR=<dir>`). Renders views with `ImageRenderer`: no window is created, no
/// focus is taken and no Screen Recording permission is needed. Then the process exits.
///
/// `SPACEVIBE_SHOT_SCREEN` picks the run, and nothing else does:
/// - `shell` (the default): the demo shell states and the gallery, `<name>-<dark|light>.png`, 1440x900 points at 2x for the
///   shell states and the gallery at its full height, in two images (`gallery`, `gallery-more`), plus `gallery-v5` (the v5
///   containers) and `gallery-controls` (the v5 controls and overlays) and `gallery-pane` (the Skills detail pane in its six states) with the v5 switch on. Synthetic demo data only; it never touches the saved appearance choice
///   or the real config folders.
/// With the v5 switch on, `shell` shoots the v5 window instead of the demo states (`ShellShots`: every Agents tab, Activity, Limits,
/// the palette, the toast and Settings; it reads the synthetic home, so it needs `SPACEVIBE_TEST=1`) and then the gallery;
/// `subagents` and `hooks` shoot the Agents page on that tab, `skills` the real Skills tab in every state (`SkillsShots`), and `limits` the v5 Limits page (`LimitsShots`). The other
/// real-screen runs below stay on the old shell until their region is built.
/// - `settings`: Settings on the demo shell in every update state and at the Large font size, and the demo tabs at Large
///   (`SettingsShots`). Synthetic data only, like `shell`.
/// - `loadout`, `rules`, `activity`, `limits`: the real screen read from the synthetic HOME, with checks on the writes
///   (`LoadoutShots`, `RulesShots`, `ActivityShots`, which share `ShotHarness`). These need `SPACEVIBE_TEST=1` and a synthetic
///   home, as `scripts/dev-fixture.sh --shots` sets up.
@MainActor
enum ShotRenderer {
    static let size = CGSize(width: 1440, height: 900)
    static let scale: CGFloat = 2

    static func run(into directory: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let environment = ProcessInfo.processInfo.environment
            let screen = environment[CoreEnvironment.variable("SHOT_SCREEN")] ?? "shell"
            switch screen {
            case "shell" where LaunchMode.uiV5Enabled():
                try requireSyntheticHome(environment)
                try ShellShots.run(into: directory, tab: nil)
                try writeGalleries(into: directory)
            case "shell": try writeShellStates(into: directory)
            case "skills", "subagents", "hooks":
                guard LaunchMode.uiV5Enabled(), let tab = AgentsCategory(rawValue: screen) else {
                    throw ShotHarness.Failure("SPACEVIBE_SHOT_SCREEN=\(screen) needs SPACEVIBE_UI_V5=1 (a development build)")
                }
                try requireSyntheticHome(environment)
                if tab == .skills { try SkillsShots.run(into: directory) } else { try ShellShots.run(into: directory, tab: tab) }
            case "loadout": try requireSyntheticHome(environment); try LoadoutShots.run(into: directory)
            case "rules": try requireSyntheticHome(environment); try RulesShots.run(into: directory)
            case "activity": try requireSyntheticHome(environment); try ActivityShots.run(into: directory)
            case "limits": try requireSyntheticHome(environment); try LimitsShots.run(into: directory)
            case "settings": try SettingsShots.run(into: directory)
            default: throw ShotHarness.Failure("unknown SPACEVIBE_SHOT_SCREEN \"\(screen)\" (shell, skills, subagents, hooks, loadout, rules, activity, limits or settings)")
            }
        } catch {
            FileHandle.standardError.write(Data("shot mode failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    /// The real screens read config folders, so they run only where the core refuses a root under the real home.
    private static func requireSyntheticHome(_ environment: [String: String]) throws {
        guard environment[CoreEnvironment.variable("TEST")] == "1" else {
            throw ShotHarness.Failure("real-screen shots need SPACEVIBE_TEST=1 and a synthetic home")
        }
    }

    private static func writeShellStates(into directory: URL) throws {
        for choice in [AppearanceChoice.dark, .light] {
            try write(shell(choice) { _, _ in }, name: "shell-loadout", choice: choice, to: directory)
            try write(shell(choice) { shell, _ in shell.select("activity") }, name: "shell-activity", choice: choice, to: directory)
            try write(shell(choice) { shell, _ in shell.select("rules") }, name: "shell-rules", choice: choice, to: directory)
            try write(shell(choice) { shell, _ in shell.openPalette() }, name: "shell-palette", choice: choice, to: directory)
            try write(shell(choice) { shell, _ in shell.openPalette(query: "p") }, name: "shell-palette-filtered", choice: choice, to: directory)
            try write(shell(choice) { _, toasts in toasts.show("Removed ponytail", undo: {}) }, name: "shell-toast", choice: choice, to: directory)
            try write(shell(choice) { _, toasts in toasts.show("SpaceVibe 0.2.0 is available", action: UpdateController.viewAction {}) }, name: "shell-toast-update", choice: choice, to: directory)
            try write(gallery(choice, part: .first), name: "gallery", choice: choice, to: directory, fullHeight: true)
            try write(gallery(choice, part: .second), name: "gallery-more", choice: choice, to: directory, fullHeight: true)
            if LaunchMode.uiV5Enabled() { try writeV5Galleries(choice, into: directory) }
        }
    }

    /// The gallery without the demo shell states: what the v5 `shell` run adds to the v5 window's own shots.
    private static func writeGalleries(into directory: URL) throws {
        for choice in [AppearanceChoice.dark, .light] {
            try write(gallery(choice, part: .first), name: "gallery", choice: choice, to: directory, fullHeight: true)
            try write(gallery(choice, part: .second), name: "gallery-more", choice: choice, to: directory, fullHeight: true)
            try writeV5Galleries(choice, into: directory)
        }
    }

    private static func writeV5Galleries(_ choice: AppearanceChoice, into directory: URL) throws {
        try write(gallery(choice, part: .third), name: "gallery-v5", choice: choice, to: directory, fullHeight: true)
        try write(gallery(choice, part: .fourth), name: "gallery-controls", choice: choice, to: directory, fullHeight: true)
        try write(gallery(choice, part: .fifth), name: "gallery-pane", choice: choice, to: directory, fullHeight: true)
    }

    private static func shell(_ choice: AppearanceChoice, configure: (ShellModel, ToastCenter) -> Void) -> some View {
        let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
        let toasts = ToastCenter(announce: false)
        configure(shell, toasts)
        return ShellView()
            .spaceVibeRoot(shell: shell, toasts: toasts)
            .frame(width: size.width, height: size.height)
    }

    private static func gallery(_ choice: AppearanceChoice, part: ComponentGalleryContent.Part) -> some View {
        let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
        return VStack(alignment: .leading, spacing: 0) {
            Text("Component gallery")
                .spaceVibeText(.title)
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 4)
            ComponentGalleryContent(part: part)
        }
        .frame(width: size.width, alignment: .topLeading)
        .overlayHost()
        .background(Palette.background)
        .spaceVibeRoot(shell: shell, toasts: ToastCenter(announce: false))
    }

    static func write<V: View>(_ view: V, name: String, choice: AppearanceChoice, to directory: URL, fullHeight: Bool = false) throws {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, choice.colorScheme)
            .environment(\.isShotRendering, true))
        renderer.scale = scale
        if fullHeight { renderer.proposedSize = ProposedViewSize(width: size.width, height: nil) }
        // A taller image renders blank without an error (the 16384 px texture limit), so it is refused here: split the content.
        guard let image = renderer.cgImage, image.height <= maxImageHeight,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ShotError.renderFailed(name)
        }
        let url = directory.appendingPathComponent("\(name)-\(choice.rawValue).png")
        try png.write(to: url)
        print(url.path)
    }

    private static let maxImageHeight = 16384

    private enum ShotError: LocalizedError {
        case renderFailed(String)
        var errorDescription: String? {
            if case .renderFailed(let name) = self { return "could not render \(name) (a shot taller than 16384 px renders blank: split it)" }
            return nil
        }
    }
}
