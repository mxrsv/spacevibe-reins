import Foundation
import Observation
import ReinsCore

/// The Limits readings, shared by the sidebar block on every tab and its detail. One instance per run, created beside
/// `ShellModel` and injected through the environment.
///
/// A read is `Limits.read`: local files only, no request, no credential, no CLI started (spec, Limits). It runs off the
/// main actor and never throws to the UI; a missing or odd file is a state inside the result. Reads happen at launch,
/// when the window becomes key (the view calls `readOnce`), every `interval` while the window is visible, and on Refresh.
@MainActor
@Observable
final class LimitsModel {
    static let interval: Duration = .seconds(60)

    let env: AppEnvironment

    /// Claude Code, Codex, Gemini CLI, in that order; empty until the first read lands.
    private(set) var results: [CLILimits] = []
    /// When `results` was read. A window's remaining time is computed from the clock, not from this.
    private(set) var readAt: Date?
    /// A read that could not run (no roots). Cleared by the next successful read.
    private(set) var failure: String?
    /// The detail popover beside the sidebar is open.
    var isDetailOpen = false
    /// Also list windows the CLI marks as not applying right now.
    var showInactive = false

    @ObservationIgnored private var isReading = false

    init(env: AppEnvironment) { self.env = env }

    var isLoading: Bool { results.isEmpty && failure == nil }

    func limits(for cli: LimitsCLI) -> CLILimits? { results.first { $0.cli == cli } }

    /// One read, unless one is already running.
    func readOnce() async {
        guard !isReading else { return }
        guard let roots = env.roots else {
            failure = env.startupProblem ?? "The config folders could not be resolved."
            return
        }
        isReading = true
        defer { isReading = false }
        let fresh = await Task.detached(priority: .utility) { Limits.read(roots) }.value
        results = fresh
        readAt = Date()
        failure = nil
    }

    /// The read loop. The view drives it with `.task(id: isWindowVisible)`; SwiftUI cancels it when the window hides, and
    /// a cancelled run ends without a further read.
    func run() async {
        while !Task.isCancelled {
            await readOnce()
            try? await Task.sleep(for: Self.interval)
        }
    }
}
