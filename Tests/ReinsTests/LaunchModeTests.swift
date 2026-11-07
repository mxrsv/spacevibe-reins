import Foundation
import Testing
@testable import Reins

/// The v5 dev switch (W17, V5-A21): honoured only in a development build, never in a distribution build.
@Suite("Launch mode: the v5 dev switch")
struct LaunchModeTests {
    private var switchName: String { LaunchMode.uiV5SwitchName }

    @Test("the switch is SPACEVIBE_UI_V5, named once")
    func name() {
        #expect(switchName == "SPACEVIBE_UI_V5")
    }

    @Test("on in a development build when the value is 1")
    func onInDevelopmentBuild() {
        #expect(LaunchMode.uiV5Enabled(environment: [switchName: "1"], isDevelopmentBuild: true))
    }

    @Test("off when unset or any value but 1", arguments: [nil, "", "0", "true", "yes", " 1"] as [String?])
    func off(value: String?) {
        let environment = value.map { [switchName: $0] } ?? [:]
        #expect(!LaunchMode.uiV5Enabled(environment: environment, isDevelopmentBuild: true))
    }

    @Test("ignored in a distribution build, whatever the environment says")
    func ignoredInDistributionBuild() {
        #expect(!LaunchMode.uiV5Enabled(environment: [switchName: "1"], isDevelopmentBuild: false))
    }

    @Test("the switch does not change the launch mode")
    func modeUnchanged() {
        guard case .normal = LaunchMode.current(environment: [switchName: "1"]) else {
            Issue.record("SPACEVIBE_UI_V5 alone must leave the launch mode normal")
            return
        }
        guard case .gallery = LaunchMode.current(environment: [switchName: "1", "SPACEVIBE_GALLERY": "1"]) else {
            Issue.record("the switch must combine with the gallery")
            return
        }
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
        let flag = "-DSPACEVIBE_DEV_BUILD"
        let flagLines = try script("build-app.sh").split(separator: "\n").filter { $0.contains(flag) }
        #expect(flagLines.count == 1, "the flag must be set in one place")
        #expect(flagLines.first.map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\"\")") } == true,
                "the flag must be set on the no-argument (development) branch only")
        #expect(try script("release.sh").contains("scripts/build-app.sh\" --distribution"))
        #expect(!(try script("release.sh").contains(flag)))
    }
}
