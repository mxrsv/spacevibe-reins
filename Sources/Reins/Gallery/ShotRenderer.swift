import AppKit
import SwiftUI

/// Headless screenshots (`REINS_SHOT_DIR=<dir>`). Renders views with `ImageRenderer`: no window is created, no
/// focus is taken and no Screen Recording permission is needed. Writes `<name>-<dark|light>.png`, 1440x900 points
/// at 2x for the shell states and the gallery at its full height, then the process exits.
///
/// It uses only synthetic demo data and never touches the saved appearance choice or the real config folders.
@MainActor
enum ShotRenderer {
    static let size = CGSize(width: 1440, height: 900)
    static let scale: CGFloat = 2

    static func run(into directory: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // REINS_SHOT_SCREEN=loadout selects the real Loadout screen; the dev variables of scripts/dev-fixture.sh the Activity one.
            if LoadoutShots.isRequested() {
                try LoadoutShots.run(into: directory)
                exit(0)
            }
            if RulesShots.isRequested() {
                try RulesShots.run(into: directory)
                exit(0)
            }
            if TokensShots.isRequested() {
                try TokensShots.run(into: directory)
                exit(0)
            }
            if ActivityShots.isRequested() {
                try ActivityShots.run(into: directory)
                exit(0)
            }
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
        } catch {
            FileHandle.standardError.write(Data("shot mode failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
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
