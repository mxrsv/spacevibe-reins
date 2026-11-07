import Foundation
import Testing
@testable import Reins

@Suite("CoreEnvironment")
struct CoreEnvironmentTests {
    // Tests run in a DEBUG build, where the dev switches are honored; a release build honors them only under SPACEVIBE_TEST=1.
    private static let allowed = ["SPACEVIBE_TEST": "1"]

    @Test("the binary override is honored when overrides are allowed, and the bundle's helper is the default")
    func binary() {
        #expect(CoreEnvironment.binaryURL(environment: Self.allowed.merging(["SPACEVIBE_CORE_BINARY": "/tmp/x/spacevibe"]) { $1 }).path == "/tmp/x/spacevibe")
        let bundled = CoreEnvironment.binaryURL(environment: Self.allowed, bundle: Bundle(for: BundleToken.self))
        #expect(bundled.path.hasSuffix("/Contents/Helpers/spacevibe"))
    }

    private final class BundleToken {}
}
