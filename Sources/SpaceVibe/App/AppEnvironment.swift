import Foundation
import Observation

/// The services every screen shares: where the config and logs live, the Go core, the toast, and the way to
/// run a write with Undo. One instance per run (`AppEnvironment.shared`), injected into the SwiftUI environment by
/// `spaceVibeRoot` and handed to a tab by its initialiser (`ActivityTab(env: .shared)` style).
///
///     // a screen model that writes:
///     env.performWithUndo(label: "Removed Bash(git push:*)", via: env.goCore, afterChange: { reload() }) { core in
///         try await core.rulesRemove(...).entry      // the CoreJournalEntry the core recorded
///     }
///
/// The Go core (`goCore`) resolves the config folders itself and refuses with its own sentence when it cannot (under
/// `SPACEVIBE_TEST=1`, a root under the real home); when the helper is missing it refuses with the fixed "could not be started" one.
///
/// Dev launch (`scripts/dev-fixture.sh`): `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` come from the
/// environment, which the core inherits. With `SPACEVIBE_TEST=1` the core's process adapter is never the real one: it replays
/// the file named by `SPACEVIBE_PROC_FIXTURE`, or an empty list when that is unset, so nothing can signal a real process.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment.live()

    let toasts: ToastCenter
    /// The Go core process, started on the first call.
    @ObservationIgnored private lazy var coreClient: any CoreService = makeCoreClient()
    @ObservationIgnored private let makeCoreClient: () -> any CoreService
    /// The Limits readings, shared by the sidebar block on every tab and its detail.
    @ObservationIgnored lazy var limits = LimitsModel(env: self)
    /// The updater and what Settings > Update shows. `SpaceVibeApp` starts it in a normal launch; elsewhere it never runs.
    @ObservationIgnored lazy var updates = UpdateController(toasts: toasts)

    init(toasts: ToastCenter? = nil, makeCoreClient: @escaping () -> any CoreService = { CoreClient() }) {
        self.toasts = toasts ?? ToastCenter()
        self.makeCoreClient = makeCoreClient
    }

    /// The Go core, the only engine of every screen (Activity and Stop, Limits, Loadout, Rules), and the engine every Undo runs on. It starts on the first call.
    var goCore: any CoreService { coreClient }

    static func live(toasts: ToastCenter? = nil) -> AppEnvironment { AppEnvironment(toasts: toasts) }

    /// Runs a write through `service` (the Go core, `goCore`). On success it shows a toast with `label` and an
    /// Undo that calls `goCore.journalUndo` with the entry the write returned, and `afterChange` runs on the main actor after the
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

    /// One change made of several journal writes (a whole family's verdicts): they run one after the other, a failing step undoes the
    /// ones before it (all or nothing), and ONE toast carries the Undo that undoes every entry, newest first. `afterChange` runs after
    /// the writes and after the Undo. `undone` is the sentence after a clean Undo (`Undid <label>` when nil).
    func performBatchWithUndo(label: String, undone: String? = nil, via service: any CoreService, afterChange: (@MainActor () -> Void)? = nil,
                              onFailure: (@MainActor (String) -> Void)? = nil,
                              _ steps: [@Sendable (any CoreService) async throws -> CoreJournalEntry]) {
        Task { [weak self] in
            var entries: [CoreJournalEntry] = []
            do {
                for step in steps { entries.append(try await step(service)) }
            } catch {
                let reverted = await Self.undoAll(entries, on: service)
                guard let self else { return }
                let message = Self.message(error)
                let shown = reverted ? message : "\(message) Some earlier changes could not be undone."
                if let onFailure { onFailure(shown) } else { self.toasts.show(shown, tone: .danger) }
                if !entries.isEmpty { afterChange?() }
                return
            }
            guard let self else { return }
            self.toasts.show(label, undo: { [weak self] in self?.undoBatch(entries, label: label, undone: undone, afterChange: afterChange) })
            afterChange?()
        }
    }

    /// Undoes `entries` newest first; false when one of them could not be undone.
    nonisolated static func undoAll(_ entries: [CoreJournalEntry], on core: any CoreService) async -> Bool {
        var all = true
        for entry in entries.reversed() {
            do { _ = try await core.journalUndo(id: entry.id) } catch { all = false }
        }
        return all
    }

    /// One entry reads as `performWithUndo` does (the core's own label, its own refusal); several read as one change.
    private func undoBatch(_ entries: [CoreJournalEntry], label: String, undone: String?, afterChange: (@MainActor () -> Void)?) {
        let core = goCore
        Task { [weak self] in
            var results: [CoreUndoResult] = []
            var failure: Error?
            for entry in entries.reversed() {
                do { results.append(try await core.journalUndo(id: entry.id)) } catch { failure = failure ?? error }
            }
            guard let self else { return }
            if let failure {
                self.toasts.show(entries.count == 1 ? Self.message(failure) : "Could not undo all of \(label)", tone: .danger)
            } else if let undone {
                self.toasts.show(undone)
            } else {
                let named = entries.count == 1 ? results.first?.label : nil
                self.toasts.show("Undid \(named.flatMap { $0.isEmpty ? nil : $0 } ?? label)")
            }
            afterChange?()
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
