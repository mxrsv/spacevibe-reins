import Foundation

/// Where the app finds the Go core and which dev-only switches it honors (plan S.2). The switches exist for development
/// builds only (`LaunchMode.isDevelopmentBuild`: a debug build, or a bundle `build-app.sh` made without `--distribution`):
/// a distribution build ignores them, `SPACEVIBE_TEST=1` included, so a stray variable in a user's shell can never swap
/// the helper (S-R1).
enum CoreEnvironment {
    static let binaryOverride = CoreProtocol.envPrefix + "CORE_BINARY"
    static let testFlag = CoreProtocol.envPrefix + "TEST"

    /// The name of a product variable: `variable("TEST")` is `SPACEVIBE_TEST`.
    static func variable(_ suffix: String) -> String { CoreProtocol.envPrefix + suffix }

    /// The helper inside the bundle. It lives in `Helpers`, not `MacOS`, because `SpaceVibe` and `spacevibe` collide on a
    /// case-insensitive volume (docs/internals/core-protocol.md, "Spawn").
    static let bundledBinaryPath = "Contents/Helpers/spacevibe"

    /// True in a development build and nowhere else; the environment cannot turn it on.
    static func overridesAllowed(isDevelopmentBuild: Bool = LaunchMode.isDevelopmentBuild) -> Bool {
        isDevelopmentBuild
    }

    /// `SPACEVIBE_CORE_BINARY` when overrides are allowed and it is set, otherwise the helper inside the app bundle.
    static func binaryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        isDevelopmentBuild: Bool = LaunchMode.isDevelopmentBuild
    ) -> URL {
        if overridesAllowed(isDevelopmentBuild: isDevelopmentBuild), let path = environment[binaryOverride], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return bundle.bundleURL.appendingPathComponent(bundledBinaryPath)
    }
}
