import Foundation

/// How this process was started, decided once from the environment.
///
/// - `REINS_GALLERY=1`: opens the component gallery instead of the shell.
/// - `REINS_SHOT_DIR=<dir>`: writes PNGs of the shell and the gallery into `<dir>` without opening a window, then exits.
enum LaunchMode {
    case normal
    case gallery
    case shots(directory: URL)

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchMode {
        if let path = environment["REINS_SHOT_DIR"], !path.isEmpty {
            return .shots(directory: URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true))
        }
        if environment["REINS_GALLERY"] == "1" { return .gallery }
        return .normal
    }
}
