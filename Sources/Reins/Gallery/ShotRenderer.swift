import AppKit
import SwiftUI

/// Headless screenshots (`REINS_SHOT_DIR=<dir>`). Renders views with `ImageRenderer`: no window is created, no
/// focus is taken and no Screen Recording permission is needed. Then the process exits.
///
/// `REINS_SHOT_SCREEN` picks the run, and nothing else does:
/// - `shell` (the default): the demo shell states and the gallery, `<name>-<dark|light>.png`, 1440x900 points at 2x for the
///   shell states and the gallery at its full height. Synthetic demo data only; it never touches the saved appearance choice
///   or the real config folders.
/// - `loadout`, `rules`, `activity`: the real screen read from the synthetic HOME, with checks on the writes
///   (`LoadoutShots`, `RulesShots`, `ActivityShots`, which share `ShotHarness`). These need `REINS_TEST=1` and a synthetic
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
            let screen = environment["REINS_SHOT_SCREEN"] ?? "shell"
            switch screen {
            case "shell": try writeShellStates(into: directory)
            case "loadout": try requireSyntheticHome(environment); try LoadoutShots.run(into: directory)
            case "rules": try requireSyntheticHome(environment); try RulesShots.run(into: directory)
            case "activity": try requireSyntheticHome(environment); try ActivityShots.run(into: directory)
            default: throw ShotHarness.Failure("unknown REINS_SHOT_SCREEN \"\(screen)\" (shell, loadout, rules or activity)")
            }
        } catch {
            FileHandle.standardError.write(Data("shot mode failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    /// The real screens read config folders, so they run only where `Roots.resolve` refuses a root under the real home.
    private static func requireSyntheticHome(_ environment: [String: String]) throws {
        guard environment["REINS_TEST"] == "1" else {
            throw ShotHarness.Failure("real-screen shots need REINS_TEST=1 and a synthetic home")
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
            try write(shell(choice) { _, toasts in toasts.show("Reins 0.2.0 is available", action: UpdateController.viewAction {}) }, name: "shell-toast-update", choice: choice, to: directory)
            try write(gallery(choice), name: "gallery", choice: choice, to: directory, fullHeight: true)
        }
    }

    private static func shell(_ choice: AppearanceChoice, configure: (ShellModel, ToastCenter) -> Void) -> some View {
        let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
        let toasts = ToastCenter(announce: false)
        configure(shell, toasts)
        return ShellView()
            .reinsRoot(shell: shell, toasts: toasts)
            .frame(width: size.width, height: size.height)
    }

    private static func gallery(_ choice: AppearanceChoice) -> some View {
        let shell = ShellModel(tabs: DemoTabs.make(), appearance: AppearanceStore(forced: choice))
        return VStack(alignment: .leading, spacing: 0) {
            Text("Component gallery")
                .font(ReinsFont.title)
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 4)
            ComponentGalleryContent()
        }
        .frame(width: size.width, alignment: .topLeading)
        .background(Palette.background)
        .reinsRoot(shell: shell, toasts: ToastCenter(announce: false))
    }

    static func write<V: View>(_ view: V, name: String, choice: AppearanceChoice, to directory: URL, fullHeight: Bool = false) throws {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, choice.colorScheme)
            .environment(\.isShotRendering, true))
        renderer.scale = scale
        if fullHeight { renderer.proposedSize = ProposedViewSize(width: size.width, height: nil) }
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ShotError.renderFailed(name)
        }
        let url = directory.appendingPathComponent("\(name)-\(choice.rawValue).png")
        try png.write(to: url)
        print(url.path)
    }

    private enum ShotError: LocalizedError {
        case renderFailed(String)
        var errorDescription: String? {
            if case .renderFailed(let name) = self { return "could not render \(name)" }
            return nil
        }
    }
}
