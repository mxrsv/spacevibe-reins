import AppKit
import Observation

/// The Limits readings, shared by the sidebar block on every tab and the Limits page; in the v5 shell by the sidebar's CLI
/// status rows (whose loop runs `run()`) and the Limits tab (`LimitsCanvas`). One instance per run, created beside
/// `ShellModel` and injected through the environment. Whether the old page shows is the shell's (`ShellModel.isLimitsOpen`).
///
/// A read is `limits.read` on the Go core (`env.goCore`): local files only, no request, no credential, no CLI started (spec, Limits). It runs off the
/// main actor and never throws to the UI; a missing or odd file is a state inside the result. Reads happen at launch,
/// when the window becomes key (the view calls `readOnce`), every `interval` while the window is visible, and on Refresh.
@MainActor
@Observable
final class LimitsModel {
    static let interval: Duration = .seconds(60)
    private static let unreadable = "The limits could not be read."

    let env: AppEnvironment

    /// Claude Code, Codex, Gemini CLI, in that order; empty until the first read lands.
    private(set) var results: [CoreLimitsEntry] = []
    /// When `results` was read. A window's remaining time is computed from the clock, not from this.
    private(set) var readAt: Date?
    /// A read that could not run (no roots). Cleared by the next successful read.
    private(set) var failure: String?
    /// Also list windows the CLI marks as not applying right now.
    var showInactive = false
    /// The entry the page shows, once picked; until then, or when it is no longer listed, the page shows the first selection.
    var selectedID: String?

    @ObservationIgnored private var isReading = false

    init(env: AppEnvironment) { self.env = env }

    /// A model that holds one reading and starts no read: the shot harness draws the V5-R62 states the fixture home cannot
    /// produce from it. A refresh still reads through `env`.
    init(env: AppEnvironment, results: [CoreLimitsEntry], failure: String? = nil) {
        self.env = env
        self.results = results
        self.failure = failure
        readAt = results.isEmpty ? nil : Date()
    }

    /// What the v5 page has to go on: loading, a failed first read, or the entries.
    var read: LimitsAnswer.Read { LimitsAnswer.Read(results: results, failure: failure) }

    var isLoading: Bool { results.isEmpty && failure == nil }

    func limits(for cli: CoreLimitsCLI) -> CoreLimitsEntry? { results.first { $0.cli == cli } }

    /// The entry the page shows among `entries`: the one picked, else the window with the least left.
    func selection(in entries: [LimitsWording.Entry], now: Date) -> String? {
        if let selectedID, entries.contains(where: { $0.id == selectedID }) { return selectedID }
        return LimitsWording.firstSelection(results, entries: entries, now: now)
    }

    /// One read, unless one is already running.
    func readOnce() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        do {
            results = try await env.goCore.limitsRead().limits
            readAt = Date()
            failure = nil
        } catch is CancellationError {
            // The window hid mid-read: keep what is shown.
        } catch {
            failure = (error as? CoreError)?.message ?? Self.unreadable
        }
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

/// Copies text only. SpaceVibe never runs the command (S-R4). `Copy /usage` on both Limits pages.
enum LimitsClipboard {
    @MainActor
    static func copyUsageCommand(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(LimitsWording.copyHint, forType: .string)
    }
}
