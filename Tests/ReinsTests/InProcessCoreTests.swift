import Foundation
import Testing
import ReinsCore
@testable import Reins

/// What is left of the in-process adapter: the handshake, and a refusal for every call (every screen is served by the Go core).
@Suite("InProcessCore")
struct InProcessCoreTests {
    @Test("the handshake names the engine's identity and serves nothing else")
    func handshake() async throws {
        let hello = try await InProcessCore(roots: nil).initialize()
        #expect(hello.identity.envPrefix == ReinsCore.envPrefix && hello.methods == ["initialize"])
    }

    @Test("every Rules call is served by the Go core only")
    func rulesAreGoCoreOnly() async {
        let core = InProcessCore(roots: nil)
        let expected = CoreError("This is served by the Go core only.", status: 500)
        await expectFailure(expected) { _ = try await core.rulesCheck(rule: "Bash") }
        await expectFailure(expected) { _ = try await core.rulesSnapshot(scope: .global, dir: nil, refreshProjects: false) }
        await expectFailure(expected) { _ = try await core.rulesPreview(scope: .global, dir: nil, capability: .run, verdict: .ask) }
        await expectFailure(expected) { _ = try await core.rulesSetCapability(scope: .global, dir: nil, capability: .run, verdict: .ask) }
        await expectFailure(expected) { _ = try await core.rulesAdd(scope: .global, dir: nil, verdict: .ask, rule: "Bash") }
        await expectFailure(expected) { _ = try await core.rulesRemove(scope: .global, dir: nil, verdict: .ask, rule: "Bash") }
        await expectFailure(expected) { _ = try await core.rulesChangeVerdict(scope: .global, dir: nil, rule: "Bash", from: .ask, to: .deny) }
    }

    @MainActor
    @Test("AppEnvironment carries the in-process stub, and shows a CoreError's message")
    func environment() async throws {
        let env = AppEnvironment(roots: nil, startupProblem: "No folders.")
        #expect(try await env.core.initialize().identity.envPrefix == ReinsCore.envPrefix)
        #expect(env.startupProblem == "No folders.")
        #expect(AppEnvironment.message(CoreError("Gone.", status: 404)) == "Gone.")
        // The core turns an engine ReinsError into a CoreError; a screen never gets the raw one.
        #expect(AppEnvironment.message(ReinsError("Refused.", status: 403)) == CoreError.unexpectedMessage)
        #expect(AppEnvironment.message(CancellationError()) == CoreError.unexpectedMessage)
    }

    private func expectFailure(_ expected: CoreError, _ work: () async throws -> Void) async {
        do {
            try await work()
            Issue.record("expected \(expected)")
        } catch let error as CoreError {
            #expect(error == expected)
        } catch {
            Issue.record("expected a CoreError, got \(error)")
        }
    }
}
