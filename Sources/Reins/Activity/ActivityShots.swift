import Foundation
import ReinsCore
import SwiftUI

/// Headless screenshots of the real Activity screen (`REINS_SHOT_DIR` plus the dev variables `REINS_TEST=1` and
/// `REINS_PROC_FIXTURE`, as `scripts/dev-fixture.sh --shots` sets them). The report is read from the synthetic HOME before
/// any frame is drawn, because `ImageRenderer` draws one frame and runs no `.task`.
///
/// Which states are written depends on the fixture: a HOME with live sessions gives `default`, `unmeasurable`
/// (the unmeasurable sessions only, Stop shown), `laterpass` (failure groups that have a later pass, no sessions), `stop`
/// (the confirmation) and `loading`; a HOME without live sessions gives `no-session`. The derived ones filter the real
/// report; none of them invents data.
@MainActor
enum ActivityShots {
    static func isRequested(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["REINS_TEST"] == "1" && !(environment["REINS_PROC_FIXTURE"] ?? "").isEmpty
    }

    private struct ShotFailure: LocalizedError {
        let errorDescription: String?
    }

    static func run(into directory: URL) throws {
        let env = AppEnvironment.live(toasts: ToastCenter(announce: false))
        guard env.roots != nil else { throw ShotFailure(errorDescription: env.startupProblem ?? "no roots") }
        let loader = ActivityModel(env: env)
        let report = try readBeforeRendering(loader)
        let live = report.sessions.filter { $0.state != .ended }

        for choice in [AppearanceChoice.dark, .light] {
            func shot(_ name: String, _ report: ActivityReport?, stop: ActivitySession? = nil, reveal: Bool = false) throws {
                let model = ActivityModel(env: env)
                model.preview(report: report)
                model.revealRowActions = reveal
                model.pendingStop = stop
                try ShotRenderer.write(screen(model, env: env, choice: choice), name: "activity-\(name)", choice: choice, to: directory)
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

    private static func with(_ report: ActivityReport, _ change: (inout ActivityReport) -> Void) -> ActivityReport {
        var copy = report
        change(&copy)
        return copy
    }

    /// Runs the engine read and spins the main run loop until it lands; the engine is an actor, so this does not deadlock.
    private static func readBeforeRendering(_ model: ActivityModel) throws -> ActivityReport {
        Task { await model.readOnce() }
        let deadline = Date().addingTimeInterval(120)
        while model.report == nil, model.failure == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let report = model.report else {
            throw ShotFailure(errorDescription: model.failure ?? "the Activity read did not finish in 120 s")
        }
        return report
    }

    private static func screen(_ model: ActivityModel, env: AppEnvironment, choice: AppearanceChoice) -> some View {
        let tabs: [any ReinsTab] = TabRegistry.makeTabs().map { $0.id == ActivityTab.tabID ? ActivityTab(model: model) : $0 }
        let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), activeID: ActivityTab.tabID)
        return ShellView()
            .reinsRoot(shell: shell, toasts: env.toasts, env: env)
            .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
    }
}
