import Foundation
import Testing
@testable import Reins

@Suite("CoreRouting")
struct CoreRoutingTests {
    // Tests run in a DEBUG build, where the dev switches are honored; a release build honors them only under SPACEVIBE_TEST=1.
    private static let allowed = ["SPACEVIBE_TEST": "1"]

    @Test("SPACEVIBE_CORE_SCREENS picks the screens that use the core, ignoring unknown names and spaces")
    func screens() {
        let routing = CoreRouting(environment: Self.allowed.merging(["SPACEVIBE_CORE_SCREENS": "activity, rules ,nope,"]) { $1 })
        #expect(routing.viaCore == [.activity, .rules])
        #expect(routing.usesCore(.activity))
        #expect(!routing.usesCore(.limits))
    }

    @Test("with no variable, or an empty one, every screen stays in process")
    func none() {
        #expect(CoreRouting(environment: Self.allowed).viaCore.isEmpty)
        #expect(CoreRouting(environment: Self.allowed.merging(["SPACEVIBE_CORE_SCREENS": ""]) { $1 }).viaCore.isEmpty)
    }

    @Test("the core is built only for a screen that routes to it")
    func lazyCore() async throws {
        let inProcess = InProcessCore(roots: nil, proc: FixtureProcessAdapter.empty)
        let routing = CoreRouting(viaCore: [.limits])
        var built = 0
        let other = routing.service(for: .activity, inProcess: inProcess) { built += 1; return CoreClient() }
        #expect(other is InProcessCore)
        #expect(built == 0)
        let routed = routing.service(for: .limits, inProcess: inProcess) { built += 1; return CoreClient(binary: URL(fileURLWithPath: "/nonexistent")) }
        #expect(routed is CoreClient)
        #expect(built == 1)
    }

    @Test("the binary override is honored when overrides are allowed, and the bundle's helper is the default")
    func binary() {
        #expect(CoreEnvironment.binaryURL(environment: Self.allowed.merging(["SPACEVIBE_CORE_BINARY": "/tmp/x/spacevibe"]) { $1 }).path == "/tmp/x/spacevibe")
        let bundled = CoreEnvironment.binaryURL(environment: Self.allowed, bundle: Bundle(for: BundleToken.self))
        #expect(bundled.path.hasSuffix("/Contents/Helpers/spacevibe"))
    }

    private final class BundleToken {}
}
