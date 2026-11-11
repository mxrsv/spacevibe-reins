import Foundation
import Testing
@testable import SpaceVibe

@Suite("CoreEnvironment")
struct CoreEnvironmentTests {
    private static let override = ["SPACEVIBE_CORE_BINARY": "/tmp/x/spacevibe"]
    private static let testFlag = ["SPACEVIBE_TEST": "1"]

    @Test("the binary override is honored in a development build, and the bundle's helper is the default")
    func binary() {
        #expect(CoreEnvironment.binaryURL(environment: Self.override, isDevelopmentBuild: true).path == "/tmp/x/spacevibe")
        let bundled = CoreEnvironment.binaryURL(environment: [:], bundle: Bundle(for: BundleToken.self), isDevelopmentBuild: true)
        #expect(bundled.path.hasSuffix("/Contents/Helpers/spacevibe"))
    }

    @Test("a distribution build ignores the override, even under SPACEVIBE_TEST=1")
    func distributionIgnoresOverride() {
        let environment = Self.override.merging(Self.testFlag) { $1 }
        let url = CoreEnvironment.binaryURL(environment: environment, bundle: Bundle(for: BundleToken.self), isDevelopmentBuild: false)
        #expect(url.path != "/tmp/x/spacevibe")
        #expect(url.path.hasSuffix("/Contents/Helpers/spacevibe"))
        #expect(!CoreEnvironment.overridesAllowed(isDevelopmentBuild: false))
        #expect(CoreEnvironment.overridesAllowed(isDevelopmentBuild: true))
    }

    private final class BundleToken {}
}
