import Foundation
import Testing
@testable import SpaceVibe

/// GL-T7: what the glance widget draws and where a click goes, without a window (spec
/// `docs/specs/2026-11-19-session-glance-widget.md`, GW-R2 to GW-R6, GW-R11). Synthetic sessions only.
@MainActor
@Suite("Glance widget", .fixtureCLIs)
struct GlanceWidgetTests {
    private func session(_ id: String, cli: CLIID = .claude, state: CoreSessionState = .running, lastWrite: Double? = 1_000,
                         tool: CoreActivityTool? = nil, pid: Int = 4100, reason: String = "log written 1 s ago") -> CoreActivitySession {
        CoreActivitySession(cli: cli, id: id, title: "Task \(id)", project: nil, pid: pid, state: state, stateReason: reason, reasonCode: nil,
                            currentTool: tool, ageMs: 3_600_000, lastWriteAgoMs: lastWrite, cost: nil, costNote: nil)
    }

    private func entries(_ sessions: [CoreActivitySession]) -> GlanceEntries {
        GlanceEntries(report: CoreActivityReport(sessions: sessions, failures: [], files: [], unmeasurable: [],
                                                 stats: CoreActivityStats(logs: sessions.count, truncated: 0)))
    }

    private func entry(_ id: String = "s1", cli: CLIID = .claude, state: CoreSessionState = .running, pid: Int = 4100) throws -> GlanceEntry {
        try #require(GlanceEntry(session(id, cli: cli, state: state, pid: pid)))
    }

    // MARK: State look (GW-R2, GW9, GW20)

    @Test("each state draws its Phosphor Bold glyph, and idle is a dot")
    func glyphs() {
        #expect(GlanceState.working.glyph == .circleNotch)
        #expect(GlanceState.waiting.glyph == .chatCircleDots)
        #expect(GlanceState.done.glyph == .checkCircle)
        #expect(GlanceState.unmeasurable.glyph == .circleDashed)
        #expect(GlanceState.idle.glyph == nil)
    }

    @Test("working, waiting and done use their state tokens; unmeasurable and idle are a faint mute")
    func inks() {
        let expected: [(GlanceState, ColorValue)] = [
            (.working, PaletteValue.sessionWorking), (.waiting, PaletteValue.sessionWaiting), (.done, PaletteValue.sessionDone),
            (.unmeasurable, PaletteValue.mute), (.idle, PaletteValue.mute),
        ]
        for (state, token) in expected {
            #expect(state.ink.dark == token.dark && state.ink.light == token.light, "\(state)")
        }
        for state in [GlanceState.working, .waiting, .done] { #expect(state.inkOpacity == 1) }
        #expect(GlanceState.unmeasurable.inkOpacity < 1)
        #expect(GlanceState.idle.inkOpacity < 1)
    }

    @Test("only the working ring turns, one turn per period")
    func motion() {
        #expect(GlanceState.allCases.filter(\.rotates) == [.working])
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(SessionStateGlyph.angle(at: start).degrees == 0)
        #expect(abs(SessionStateGlyph.angle(at: start.addingTimeInterval(Metrics.Glance.spinPeriod / 4)).degrees - 90) < 0.001)
    }

    // MARK: Strip (GW-R3, GW-R4, GW14)

    @Test("the left and right edge middles stack the strip, every other slot runs it in a row")
    func axisPerSlot() {
        for slot in GlanceSlot.allCases {
            let strip = GlanceStrip(entries: .empty, slot: slot)
            let vertical = slot == .leftMiddle || slot == .rightMiddle
            #expect(strip.axis == (vertical ? .vertical : .horizontal), "\(slot)")
        }
    }

    @Test("no session is the empty strip, a few are all shown, twelve are six and +6 with waiting first")
    func items() {
        #expect(GlanceStrip(entries: .empty, slot: .bottomRight).isEmpty)

        let few = GlanceStrip(entries: entries([session("a"), session("b", state: .waiting)]), slot: .bottomRight)
        #expect(few.items.map(\.id) == ["claude:b", "claude:a"])

        let many = entries((1...12).map { session("s\($0)", state: $0 == 9 ? .waiting : .running, lastWrite: Double($0)) })
        let strip = GlanceStrip(entries: many, slot: .topRight)
        #expect(strip.items.count == 7)
        #expect(strip.items.first?.id == "claude:s9")
        #expect(strip.items.last == .overflow(6))
    }

    // MARK: Wording (GW-R5)

    @Test("a row's second line: the tool, the reason when unmeasurable, No tool running when idle")
    func detail() throws {
        let tool = CoreActivityTool(name: "Bash", target: "scripts/test.sh")
        let running = try #require(GlanceEntry(session("r", tool: tool)))
        #expect(GlanceWording.detail(running) == "Bash · scripts/test.sh")
        let unmeasurable = try #require(GlanceEntry(session("u", state: .unmeasurable, tool: tool, reason: "Rollout could not be read")))
        #expect(GlanceWording.detail(unmeasurable) == "Rollout could not be read")
        let idle = try #require(GlanceEntry(session("i", state: .idle, lastWrite: 3_600_000)))
        #expect(GlanceWording.detail(idle) == GlanceWording.noTool)
        #expect(GlanceState.allCases.map(GlanceWording.label) == ["Waiting for you", "Running", "Done", "Unmeasurable", "Idle"])
    }

    // MARK: Click (GW5, GW6, GW-R6)

    private final class Calls {
        var activated: [HostApp] = []
        var opened: [String] = []
    }

    private func route(host: HostApp?, activates: Bool, calls: Calls) -> GlanceClickRoute {
        GlanceClickRoute(hostApp: { _ in host }, activate: { calls.activated.append($0); return activates },
                         openActivity: { calls.opened.append($0) })
    }

    @Test("a found host app is brought forward and Activity is not opened")
    func clickHost() throws {
        let app = HostApp(pid: 900, bundleIdentifier: "com.example.term", name: "Term")
        let calls = Calls()
        let outcome = route(host: app, activates: true, calls: calls).open(try entry(pid: 4100))
        #expect(outcome == .hostApp(app))
        #expect(calls.activated == [app])
        #expect(calls.opened.isEmpty)
    }

    @Test("no host app, or one that refuses to come forward, opens Activity at that session")
    func clickFallback() throws {
        let codex = try entry("t-1", cli: .codex)
        let none = Calls()
        #expect(route(host: nil, activates: true, calls: none).open(codex) == .activity(itemID: "codex:t-1"))
        #expect(none.activated.isEmpty && none.opened == ["codex:t-1"])

        let refused = Calls()
        let app = HostApp(pid: 900, bundleIdentifier: nil, name: "Term")
        #expect(route(host: app, activates: false, calls: refused).open(codex) == .activity(itemID: "codex:t-1"))
        #expect(refused.activated == [app] && refused.opened == ["codex:t-1"])
    }

    @Test("the hovered row names the host app, or Activity")
    func destination() throws {
        let calls = Calls()
        let session = try entry()
        #expect(route(host: HostApp(pid: 900, bundleIdentifier: nil, name: "Ghostty"), activates: true, calls: calls).destination(of: session) == "Ghostty")
        #expect(route(host: nil, activates: true, calls: calls).destination(of: session) == GlanceWording.activity)
        #expect(calls.activated.isEmpty, "naming the destination never activates")
    }

    @Test("the Activity route selects Activity's Running tab with that session current and open")
    func shellRoute() throws {
        let shell = ShellModel.forAppTests()
        shell.openSettings()
        let activity = try #require(shell.tabs.first { $0.id == TabRegistry.activityID } as? ActivityTab)
        activity.model.select(.failed)
        shell.openActivity(sessionItemID: "claude:abc")
        #expect(shell.activeID == TabRegistry.activityID)
        #expect(!shell.isSettingsOpen)
        #expect(activity.model.pane == .running)
        #expect(activity.model.currentID == "claude:abc")
        #expect(activity.model.detailID == "claude:abc")
    }

    // MARK: Launch gate

    @Test("the widget runs only in a normal launch without the test flag")
    func runsOnlyInNormalLaunch() {
        #expect(GlanceController.runs(in: .normal, environment: [:]))
        #expect(!GlanceController.runs(in: .normal, environment: [CoreEnvironment.testFlag: "1"]))
        #expect(!GlanceController.runs(in: .gallery, environment: [:]))
        #expect(!GlanceController.runs(in: .shots(directory: URL(fileURLWithPath: "/tmp")), environment: [:]))
    }

    /// S-R1, GL-T10: each launch is decided from its environment the way the app decides it (`LaunchMode.current`), so a
    /// gallery, a fixture shot run (what `scripts/dev-fixture.sh --shots` exports) and a test run never show the widget, even
    /// in a development build; only a plain launch does.
    @Test("gallery, fixture shot and test launches never show the widget")
    func launchesFromEnvironment() {
        let test = [CoreEnvironment.testFlag: "1"]
        let gallery = [CoreEnvironment.variable("GALLERY"): "1"]
        let shots = [CoreEnvironment.variable("SHOT_DIR"): "/tmp/shots", CoreEnvironment.variable("SHOT_SCREEN"): "glance"]
        let gated: [[String: String]] = [test, gallery, shots, shots.merging(test) { $1 }, gallery.merging(test) { $1 }]
        for environment in gated {
            let mode = LaunchMode.current(environment: environment, isDevelopmentBuild: true)
            #expect(!GlanceController.runs(in: mode, environment: environment), "\(environment)")
        }
        // A distribution build ignores the gallery and shot variables and launches normally, with the widget; the test flag
        // still keeps it off.
        #expect(GlanceController.runs(in: LaunchMode.current(environment: shots, isDevelopmentBuild: false), environment: shots))
        #expect(!GlanceController.runs(in: LaunchMode.current(environment: test, isDevelopmentBuild: false), environment: test))
        #expect(GlanceController.runs(in: LaunchMode.current(environment: [:], isDevelopmentBuild: true), environment: [:]))
        // This test process runs under `scripts/test.sh`, which sets the flag.
        let own = ProcessInfo.processInfo.environment
        #expect(!GlanceController.runs(in: LaunchMode.current(environment: own), environment: own))
    }

    @Test("a gated launch never asks for a core, so no subscription opens")
    func gatedStartOpensNothing() {
        let suite = "dev.spacevibe.tests.glance-gate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var asked = 0
        let controller = GlanceController(preferences: GlancePreferences(defaults: defaults)) {
            asked += 1
            return UnservedCore()
        }
        controller.start(mode: .gallery, environment: [:], openMainWindow: {})
        controller.start(mode: .shots(directory: URL(fileURLWithPath: "/tmp")), environment: [:], openMainWindow: {})
        controller.start(mode: .normal, environment: [CoreEnvironment.testFlag: "1"], openMainWindow: {})
        #expect(asked == 0)
    }
}
