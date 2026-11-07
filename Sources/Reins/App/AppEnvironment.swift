import Foundation
import Observation
import ReinsCore

/// The services every screen shares: where the config and logs live, the process adapter, the toast, and the way to
/// run a write with Undo. One instance per run (`AppEnvironment.shared`), injected into the SwiftUI environment by
/// `reinsRoot` and handed to a tab by its initialiser (`ActivityTab(env: .shared)` style).
///
///     // a screen model that writes:
///     env.performWithUndo(label: "Removed Bash(git push:*)", afterChange: { reload() }) {
///         try removeRule(roots, ...)      // returns the JournalEntry the engine recorded
///     }
///
/// `roots` is nil, with `startupProblem` set, when `Roots.resolve()` throws (under `SPACEVIBE_TEST=1` that is a root under
/// the real home). A screen shows `startupProblem` instead of reading anything.
///
/// Dev launch (`scripts/dev-fixture.sh`): `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` come from the
/// environment. With `SPACEVIBE_TEST=1` the process adapter is never the real one: it replays the file named by
/// `SPACEVIBE_PROC_FIXTURE`, or an empty list when that is unset, so nothing can signal a real process.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment.live()

    let roots: Roots?
    let startupProblem: String?
    let proc: any ProcessAdapter
    let toasts: ToastCenter
    /// The Limits readings, shared by the sidebar block on every tab and its detail.
    @ObservationIgnored lazy var limits = LimitsModel(env: self)
    /// The updater and what Settings > Update shows. `ReinsApp` starts it in a normal launch; elsewhere it never runs.
    @ObservationIgnored lazy var updates = UpdateController(toasts: toasts)

    init(roots: Roots?, startupProblem: String? = nil, proc: any ProcessAdapter, toasts: ToastCenter? = nil) {
        self.roots = roots
        self.startupProblem = roots == nil ? (startupProblem ?? "The config folders could not be resolved.") : startupProblem
        self.proc = proc
        self.toasts = toasts ?? ToastCenter()
    }

    static func live(environment: [String: String] = ProcessInfo.processInfo.environment, toasts: ToastCenter? = nil) -> AppEnvironment {
        var problems: [String] = []
        var roots: Roots?
        do { roots = try Roots.resolve(env: environment) } catch { problems.append(String(describing: error)) }
        let proc: any ProcessAdapter
        if environment[ReinsCore.env("TEST")] == "1" {
            if let path = environment[ReinsCore.env("PROC_FIXTURE")], !path.isEmpty {
                do { proc = try FixtureProcessAdapter.load(path: path) } catch {
                    problems.append(String(describing: error))
                    proc = FixtureProcessAdapter.empty
                }
            } else {
                proc = FixtureProcessAdapter.empty
            }
        } else {
            proc = SystemProcessAdapter()
        }
        return AppEnvironment(roots: roots, startupProblem: problems.isEmpty ? nil : problems.joined(separator: " "), proc: proc, toasts: toasts)
    }

    /// `roots`, or the reason there are none.
    func requireRoots() throws -> Roots {
        guard let roots else { throw ReinsError(startupProblem ?? "The config folders could not be resolved.", status: 500) }
        return roots
    }

    /// Runs a write off the main thread. On success it shows a toast with `label` and an Undo that calls
    /// `Journal.undo` (also off the main thread); on failure it shows a danger toast with `ReinsError.message`.
    /// `afterChange` runs on the main actor after the write and again after an undo, so a screen can reload; it does
    /// not run when the write failed. With `onFailure` the message goes there instead of a toast (a screen that shows the
    /// error next to the control, such as the Rules add-rule row).
    func performWithUndo(label: String, afterChange: (@MainActor () -> Void)? = nil, onFailure: (@MainActor (String) -> Void)? = nil, _ work: @escaping @Sendable () throws -> JournalEntry) {
        let roots: Roots
        do { roots = try requireRoots() } catch {
            if let onFailure { onFailure(Self.message(error)) } else { toasts.show(Self.message(error), tone: .danger) }
            return
        }
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { Result { try work() } }.value
            guard let self else { return }
            switch outcome {
            case .success(let entry):
                self.toasts.show(label, undo: { [weak self] in self?.undo(entry, roots: roots, label: label, afterChange: afterChange) })
                afterChange?()
            case .failure(let error):
                if let onFailure { onFailure(Self.message(error)) } else { self.toasts.show(Self.message(error), tone: .danger) }
            }
        }
    }

    private func undo(_ entry: JournalEntry, roots: Roots, label: String, afterChange: (@MainActor () -> Void)?) {
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { Result { try Journal.undo(roots, id: entry.id) } }.value
            guard let self else { return }
            switch outcome {
            case .success(let undone):
                self.toasts.show("Undid \(undone.isEmpty ? label : undone)")
                afterChange?()
            case .failure(let error):
                self.toasts.show(Self.message(error), tone: .danger)
            }
        }
    }

    /// A `ReinsError` message is safe to show; any other error gets a fixed sentence, never its description (S-R3).
    static func message(_ error: Error) -> String {
        (error as? ReinsError)?.message ?? "The change could not be made."
    }
}
