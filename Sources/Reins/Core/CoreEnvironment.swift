import Foundation

/// Where the app finds the Go core and which dev-only switches it honors (plan S.2). The switches exist for debug builds
/// and tests only: a release build ignores them, so a stray variable in a user's shell can never swap the helper or send a
/// screen down another path (S-R1).
enum CoreEnvironment {
    static let binaryOverride = CoreProtocol.envPrefix + "CORE_BINARY"
    static let screensOverride = CoreProtocol.envPrefix + "CORE_SCREENS"
    static let testFlag = CoreProtocol.envPrefix + "TEST"

    /// The name of a product variable: `variable("TEST")` is `SPACEVIBE_TEST`.
    static func variable(_ suffix: String) -> String { CoreProtocol.envPrefix + suffix }

    /// The helper inside the bundle. It lives in `Helpers`, not `MacOS`, because `SpaceVibe` and `spacevibe` collide on a
    /// case-insensitive volume (docs/internals/core-protocol.md, "Spawn").
    static let bundledBinaryPath = "Contents/Helpers/spacevibe"

    /// True in a DEBUG build and under `SPACEVIBE_TEST=1`.
    static func overridesAllowed(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        return true
        #else
        return environment[testFlag] == "1"
        #endif
    }

    /// `SPACEVIBE_CORE_BINARY` when overrides are allowed and it is set, otherwise the helper inside the app bundle.
    static func binaryURL(environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main) -> URL {
        if overridesAllowed(environment), let path = environment[binaryOverride], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return bundle.bundleURL.appendingPathComponent(bundledBinaryPath)
    }
}
