import Foundation
import Testing
@testable import SpaceVibe

/// Gallery and shot entry points remain development-only after the UI cut-over.
@Suite("Development launch modes", .fixtureCLIs)
struct LaunchModeTests {
    @Test("the gallery and shot modes need a development build")
    func modesNeedDevelopmentBuild() {
        let gallery = ["SPACEVIBE_GALLERY": "1"]
        let shots = ["SPACEVIBE_SHOT_DIR": "/tmp/shots"]
        for environment in [gallery, shots, gallery.merging(shots) { $1 }] {
            guard case .normal = LaunchMode.current(environment: environment, isDevelopmentBuild: false) else {
                Issue.record("a distribution build must start normal: \(environment)")
                return
            }
        }
        guard case .gallery = LaunchMode.current(environment: gallery, isDevelopmentBuild: true) else {
            Issue.record("the gallery variable must open the gallery in a development build")
            return
        }
        guard case .shots(let directory) = LaunchMode.current(environment: shots, isDevelopmentBuild: true) else {
            Issue.record("the shot variable must pick the shots mode in a development build")
            return
        }
        #expect(directory.path == "/tmp/shots")
    }

    @Test("a debug build counts as a development build")
    func debugBuildIsDevelopment() {
        #if DEBUG
        #expect(LaunchMode.isDevelopmentBuild)
        #endif
    }

    private static let checkout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func script(_ name: String) throws -> String {
        try String(contentsOf: Self.checkout.appendingPathComponent("scripts/\(name)"), encoding: .utf8)
    }

    /// H9: the compile flag may sit on the development branch of `build-app.sh` only, and the release script must keep
    /// building with `--distribution`.
    @Test("build-app.sh adds the dev flag only outside --distribution; release.sh builds with --distribution")
    func buildFlagStaysOutOfDistribution() throws {
        let flag = "-DSPACEVIBE_DEVELOPMENT_TOOLS"
        let flagLines = try script("build-app.sh").split(separator: "\n").filter { $0.contains(flag) }
        #expect(flagLines.count == 1, "the flag must be set in one place")
        #expect(flagLines.first.map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\"\")") } == true,
                "the flag must be set on the no-argument (development) branch only")
        #expect(try script("release.sh").contains("scripts/build-app.sh\" --distribution"))
        #expect(!(try script("release.sh").contains(flag)))
    }
}
