import Foundation
import Testing
@testable import Reins

/// The Limits model reads through `env.core(for: .limits)`: in process by default, the Go core when the screen is routed to
/// it (plan S.1b, cut-over readiness). Both run on a private copy of the synthetic fixture home (S-R1).
@Suite("Limits model")
@MainActor
struct LimitsModelTests {
    private func model(_ fixture: CoreFixtureHome, viaCore: Bool) throws -> (LimitsModel, CoreClient?) {
        let client = viaCore ? try fixture.client() : nil
        let env = AppEnvironment(
            roots: try fixture.roots(), proc: FixtureProcessAdapter.empty,
            routing: CoreRouting(viaCore: viaCore ? [.limits] : []), makeCoreClient: { client ?? CoreClient() }
        )
        return (LimitsModel(env: env), client)
    }

    @Test("the in-process path and the Go core give the page the same entries, tiles and summaries")
    func sameThroughBothEngines() async throws {
        let fixture = try CoreFixtureHome()
        defer { fixture.remove() }
        let (inProcess, _) = try model(fixture, viaCore: false)
        let (viaCore, client) = try model(fixture, viaCore: true)
        defer { client?.shutdown() }
        await inProcess.readOnce()
        await viaCore.readOnce()
        #expect(inProcess.failure == nil && viaCore.failure == nil)
        #expect(inProcess.results.map(\.cli) == [.claude, .codex, .gemini])
        #expect(viaCore.results == inProcess.results)
        let now = Date()
        for showInactive in [false, true] {
            #expect(LimitsWording.entries(viaCore.results, showInactive: showInactive) == LimitsWording.entries(inProcess.results, showInactive: showInactive))
        }
        #expect(viaCore.results.map { LimitsWording.summary($0, now: now) } == inProcess.results.map { LimitsWording.summary($0, now: now) })
    }

    @Test("a read that cannot run leaves the engine's sentence as the failure and no results")
    func failure() async {
        let env = AppEnvironment(roots: nil, startupProblem: "No home here.", proc: FixtureProcessAdapter.empty)
        let model = LimitsModel(env: env)
        await model.readOnce()
        #expect(model.failure == "No home here.")
        #expect(model.results.isEmpty && model.readAt == nil)
    }
}
