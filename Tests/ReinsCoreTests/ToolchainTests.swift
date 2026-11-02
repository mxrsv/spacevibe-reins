import Testing
@testable import ReinsCore

@Suite("Toolchain")
struct ToolchainTests {
    @Test("swift-testing discovers and runs a test")
    func runs() {
        #expect(ReinsCore.name == "ReinsCore")
    }
}
