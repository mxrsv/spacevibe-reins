import AppKit
import Foundation
import Testing
@testable import SpaceVibe

/// The Limits model reads through `env.goCore`, the Go core (plan S.4). The core runs on a private copy of the synthetic
/// fixture home (S-R1).
@Suite("Limits model")
@MainActor
struct LimitsModelTests {
    private func model(_ fixture: CoreFixtureHome) throws -> (LimitsModel, CoreClient) {
        let client = try fixture.client()
        let env = AppEnvironment(makeCoreClient: { client })
        return (LimitsModel(env: env), client)
    }

    @Test("the core gives the page the fixture's entries, in order, and the page's tiles and summaries follow from them", .timeLimit(.minutes(1)))
    func fixtureHome() async throws {
        let fixture = try await CoreFixtureHome.make()
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        #expect(model.isLoading)
        await model.readOnce()
        #expect(model.failure == nil && model.readAt != nil && !model.isLoading)
        #expect(model.results.map(\.cli) == [.claude, .codex, .gemini])
        #expect(model.results.allSatisfy { $0.state != .measured ? $0.windows.isEmpty && $0.at == nil : !$0.windows.isEmpty })
        let now = Date()
        let shown = Set(LimitsWording.entries(model.results, showInactive: false).map(\.id))
        #expect(shown.isSubset(of: Set(LimitsWording.entries(model.results, showInactive: true).map(\.id))))
        #expect(model.results.map { LimitsWording.summary($0, now: now) }.count == 3)
    }

    @Test("a core that refuses its environment leaves its own sentence as the failure and no results", .timeLimit(.minutes(1)))
    func coreStartupProblem() async throws {
        let fixture = try await CoreFixtureHome.make(extraEnvironment: ["SPACEVIBE_TEST": "2"])
        defer { fixture.remove() }
        let (model, client) = try model(fixture)
        defer { client.shutdown() }
        await model.readOnce()
        #expect(model.failure?.contains("SPACEVIBE_TEST") == true)
        #expect(model.results.isEmpty && model.readAt == nil)
    }

    @Test("when the helper is missing, the page shows the fixed startup sentence and no results")
    func helperMissing() async {
        let client = CoreClient(binary: URL(fileURLWithPath: "/nonexistent/spacevibe"))
        let model = LimitsModel(env: AppEnvironment(makeCoreClient: { client }))
        await model.readOnce()
        #expect(model.failure == CoreWire.startFailedMessage)
        #expect(model.results.isEmpty && model.readAt == nil)
    }

    @Test("the palette offers the status-line capture install and uninstall commands, and copies the helper's quoted path and nothing else")
    func captureCommandsAreCopiedNotRun() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.spacevibe.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("before", forType: .string)
        let helper = URL(fileURLWithPath: "/Applications/Space Vibe's.app/Contents/Helpers/spacevibe")
        let entries = LimitsTab(helper: helper, pasteboard: pasteboard).paletteActions
        #expect(entries.map(\.title) == ["Copy the status-line capture install command", "Copy the status-line capture uninstall command"])
        let quoted = "'/Applications/Space Vibe'\\''s.app/Contents/Helpers/spacevibe'"
        entries[0].perform()
        #expect(pasteboard.string(forType: .string) == quoted + " statusline install")
        entries[1].perform()
        #expect(pasteboard.string(forType: .string) == quoted + " statusline uninstall")
        #expect(pasteboard.pasteboardItems?.count == 1)
    }
}
