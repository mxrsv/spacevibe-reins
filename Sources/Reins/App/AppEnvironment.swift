import Foundation
import Observation

/// The services every screen shares: where the config and logs live, the Go core, the toast, and the way to
/// run a write with Undo. One instance per run (`AppEnvironment.shared`), injected into the SwiftUI environment by
/// `reinsRoot` and handed to a tab by its initialiser (`ActivityTab(env: .shared)` style).
///
///     // a screen model that writes:
///     env.performWithUndo(label: "Removed Bash(git push:*)", via: env.core(for: .rules), afterChange: { reload() }) { core in
///         try await core.rulesRemove(...).entry      // the CoreJournalEntry the core recorded
///     }
///
/// `startupProblem` is set when the config folders could not be resolved (under `SPACEVIBE_TEST=1` that is a root under the real
/// home); the in-process core then refuses every call with it, and a screen shows the refusal instead of reading anything.
/// The Go core (`goCore`) resolves the same folders itself and refuses with its own sentence; when the helper is missing it
/// refuses with the fixed "could not be started" one.
///
/// Dev launch (`scripts/dev-fixture.sh`): `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` come from the
/// environment (`InProcessCore.live` and the core, which inherits it, read them). With `SPACEVIBE_TEST=1` the core's process
/// adapter is never the real one: it replays the file named by `SPACEVIBE_PROC_FIXTURE`, or an empty list when that is unset,
/// so nothing can signal a real process.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment.live()

    let startupProblem: String?
    let toasts: ToastCenter
    /// The in-process engine, for the screens that have not cut over to the Go core yet (plan S.1).
    let core: any CoreService
    /// Which of those screens read through the Go core (`SPACEVIBE_CORE_SCREENS`, dev builds and tests only). Empty by default.
    let routing: CoreRouting
    /// The Go core process, started on the first call of a screen that routes to it.
    @ObservationIgnored private lazy var coreClient: any CoreService = makeCoreClient()
    @ObservationIgnored private let makeCoreClient: () -> any CoreService
    /// The Limits readings, shared by the sidebar block on every tab and its detail.
    @ObservationIgnored lazy var limits = LimitsModel(env: self)
    /// The updater and what Settings > Update shows. `ReinsApp` starts it in a normal launch; elsewhere it never runs.
    @ObservationIgnored lazy var updates = UpdateController(toasts: toasts)

    init(startupProblem: String? = nil, toasts: ToastCenter? = nil, core: any CoreService, routing: CoreRouting = CoreRouting(), makeCoreClient: @escaping () -> any CoreService = { CoreClient() }) {
        self.startupProblem = startupProblem
        self.toasts = toasts ?? ToastCenter()
        self.core = core
        self.routing = routing
        self.makeCoreClient = makeCoreClient
    }

    /// The engine a screen that has not cut over reads through: `core` (in process) unless `routing` sends it to the Go core.
    func core(for screen: CoreScreen) -> any CoreService {
        routing.service(for: screen, inProcess: core, core: { coreClient })
    }

    /// The Go core, the only engine of a screen that has cut over (Activity and Stop, Limits, Loadout), and the engine every Undo runs on. It starts on the first call.
    var goCore: any CoreService { coreClient }

    static func live(environment: [String: String] = ProcessInfo.processInfo.environment, toasts: ToastCenter? = nil) -> AppEnvironment {
        let (core, problem) = InProcessCore.live(environment: environment)
        return AppEnvironment(startupProblem: problem, toasts: toasts, core: core)
    }

    /// Runs a write through `service` (the engine the screen's writes route to). On success it shows a toast with `label` and an
    /// Undo that calls `goCore.journalUndo` with the entry the write returned (the journal is one file for both engines), and `afterChange` runs on the main actor after the
    /// write and again after an Undo, so a screen can reload; it does not run when the write failed. On failure it shows a danger
    /// toast with the `CoreError` message, or with `onFailure` the message goes there instead (a screen that shows the error next
    /// to the control, such as the Rules add-rule row).
    func performWithUndo(label: String, via service: any CoreService, afterChange: (@MainActor () -> Void)? = nil, onFailure: (@MainActor (String) -> Void)? = nil, _ work: @escaping @Sendable (any CoreService) async throws -> CoreJournalEntry) {
        Task { [weak self] in
            let outcome: Result<CoreJournalEntry, Error>
            do { outcome = .success(try await work(service)) } catch { outcome = .failure(error) }
            guard let self else { return }
            switch outcome {
            case .success(let entry):
                self.toasts.show(label, undo: { [weak self] in self?.undo(entry, label: label, afterChange: afterChange) })
                afterChange?()
            case .failure(let error):
                if let onFailure { onFailure(Self.message(error)) } else { self.toasts.show(Self.message(error), tone: .danger) }
            }
        }
    }

    private func undo(_ entry: CoreJournalEntry, label: String, afterChange: (@MainActor () -> Void)?) {
        let core = goCore
        Task { [weak self] in
            let outcome: Result<CoreUndoResult, Error>
            do { outcome = .success(try await core.journalUndo(id: entry.id)) } catch { outcome = .failure(error) }
            guard let self else { return }
            switch outcome {
            case .success(let undone):
                self.toasts.show("Undid \(undone.label.isEmpty ? label : undone.label)")
                afterChange?()
            case .failure(let error):
                self.toasts.show(Self.message(error), tone: .danger)
            }
        }
    }

    /// A `CoreError` message is safe to show; any other error gets a fixed sentence, never its description (S-R3).
    static func message(_ error: Error) -> String {
        (error as? CoreError)?.message ?? CoreError.unexpectedMessage
    }
}
