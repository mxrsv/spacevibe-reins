import Foundation

/// Version string of the engine, shown by the app and asserted by the toolchain test.
public enum ReinsCore {
    public static let name = "ReinsCore"
    /// Prefix of every environment variable the product reads (SV12). One constant; the Go core owns the same value.
    public static let envPrefix = "SPACEVIBE_"
    /// The data folder under the home directory (SV12). No alias for the old name and no migration (SV15).
    public static let dataFolderName = ".spacevibe"

    /// `env("TEST")` is `SPACEVIBE_TEST`.
    public static func env(_ suffix: String) -> String { envPrefix + suffix }
}
