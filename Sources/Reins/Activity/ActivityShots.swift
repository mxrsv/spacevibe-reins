import Foundation
import SwiftUI

/// Headless screenshots of the real Activity screen. `ShotRenderer.run` starts it for `SPACEVIBE_SHOT_SCREEN=activity`, which
/// needs the synthetic HOME and fake process list of `scripts/dev-fixture.sh --shots`; `ShotHarness` holds the waits and
/// shell it shares with the Loadout and Rules runs. The report is read from the synthetic HOME before any frame is drawn,
/// because `ImageRenderer` draws one frame and runs no `.task`.
///
/// Which states are written depends on the fixture: a HOME with live sessions gives `default`, `unmeasurable`
/// (the unmeasurable sessions only, Stop shown), `laterpass` (failure groups that have a later pass, no sessions), `stop`
/// (the confirmation) and `loading`; a HOME without live sessions gives `no-session`. The derived ones filter the real
/// report; none of them invents data.
@MainActor
enum ActivityShots {
    static func run(into directory: URL) throws {
        let env = AppEnvironment.live(toasts: ToastCenter(announce: false))
        if let problem = env.startupProblem { throw ShotHarness.Failure(problem) }
        let loader = ActivityModel(env: env)
        let report = try readBeforeRendering(loader)
        let live = report.sessions.filter { $0.state != .ended }

        for choice in [AppearanceChoice.dark, .light] {
            func shot(_ name: String, _ report: CoreActivityReport?, stop: CoreActivitySession? = nil, reveal: Bool = false) throws {
                let model = ActivityModel(env: env)
                model.preview(report: report)
                model.revealRowActions = reveal
                model.pendingStop = stop
                let shell = ShotHarness.shell(around: ActivityTab(model: model), choice: choice)
                try ShotRenderer.write(ShotHarness.view(shell, env: env), name: "activity-\(name)", choice: choice, to: directory)
            }
            if live.isEmpty {
                try shot("no-session", report)
                continue
            }
            try shot("default", report)
            try shot("unmeasurable", with(report) { $0.sessions = $0.sessions.filter { $0.state == .unmeasurable } }, reveal: true)
            try shot("laterpass", with(report) { r in
                r.sessions = []
                r.failures = r.failures.filter { $0.laterPass != nil }
            })
            try shot("loading", nil)
            let target = live.first { $0.cli == .claude && $0.state == .running } ?? live[0]
            try shot("stop", report, stop: target)
        }
    }

    private static func with(_ report: CoreActivityReport, _ change: (inout CoreActivityReport) -> Void) -> CoreActivityReport {
        var copy = report
        change(&copy)
        return copy
    }

    /// Runs the engine read and spins the main run loop until it lands; the engine is an actor, so this does not deadlock.
    private static func readBeforeRendering(_ model: ActivityModel) throws -> CoreActivityReport {
        Task { await model.readOnce() }
        try ShotHarness.wait("the Activity read", seconds: ShotHarness.settleSeconds) { model.report != nil || model.failure != nil }
        guard let report = model.report else {
            throw ShotHarness.Failure(model.failure ?? "the Activity read returned no report")
        }
        return report
    }
}
