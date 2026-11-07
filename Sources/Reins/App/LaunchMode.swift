import Foundation
import ReinsCore

/// How this process was started, decided once from the environment.
///
/// - `SPACEVIBE_GALLERY=1`: opens the component gallery instead of the shell.
/// - `SPACEVIBE_SHOT_DIR=<dir>`: writes PNGs of the shell and the gallery into `<dir>` without opening a window, then exits.
///
/// Beside the mode sits the v5 UI switch (`SPACEVIBE_UI_V5=1`, W17). It is not a mode: it combines with the gallery and the
/// shots. It is honoured only in a development build, so a distribution build can never show unfinished surfaces.
enum LaunchMode {
    case normal
    case gallery
    case shots(directory: URL)

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchMode {
        if let path = environment[ReinsCore.env("SHOT_DIR")], !path.isEmpty {
            return .shots(directory: URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true))
        }
        if environment[ReinsCore.env("GALLERY")] == "1" { return .gallery }
        return .normal
    }

    /// The one name of the v5 switch. Every read goes through `uiV5Enabled`.
    static let uiV5SwitchName = ReinsCore.env("UI_V5")

    /// True in a debug build and in a bundle `scripts/build-app.sh` made without `--distribution` (it passes
    /// `-DSPACEVIBE_DEV_BUILD`); false in a distribution build.
    static var isDevelopmentBuild: Bool {
        #if DEBUG || SPACEVIBE_DEV_BUILD
        true
        #else
        false
        #endif
    }

    /// Whether the v5 surfaces replace today's. The environment and the build condition are parameters so a test needs neither
    /// the real process environment nor a particular build.
    static func uiV5Enabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDevelopmentBuild: Bool = LaunchMode.isDevelopmentBuild
    ) -> Bool {
        isDevelopmentBuild && environment[uiV5SwitchName] == "1"
    }
}
