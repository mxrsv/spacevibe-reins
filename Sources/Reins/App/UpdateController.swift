import AppKit
import OSLog
import Sparkle

/// Sparkle owns the check, the update window, signature verification, installation and relaunch. This class decides
/// whether the updater runs at all and adds a toast when a scheduled check finds an update.
///
/// It is the only code in the app that reaches the network (AGENTS.md S-R5), and only when the build has a feed.
@MainActor
final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private let toasts: ToastCenter
    private let logger = Logger(subsystem: "dev.spacevibe.reins", category: "updates")
    private var controller: SPUStandardUpdaterController?
    private var unavailableReason: String?
    private var reminder: UUID?

    init(toasts: ToastCenter) {
        self.toasts = toasts
        super.init()
    }

    func start(
        mode: LaunchMode,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        info: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        guard controller == nil else { return }
        guard Self.runs(in: mode, environment: environment) else {
            unavailableReason = "Updates are off in this launch mode."
            return
        }
        if let issue = Self.configurationIssue(in: info) {
            unavailableReason = issue
            logger.notice("Updater off: \(issue, privacy: .public)")
            return
        }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        do {
            try updater.updater.start()
            controller = updater
            logger.notice("Updater started, automatic checks: \(updater.updater.automaticallyChecksForUpdates, privacy: .public)")
        } catch {
            unavailableReason = "Updates could not start. Quit and reopen Reins, then try again."
            logger.error("Updater failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isRunning: Bool { controller != nil }

    func checkForUpdates() {
        if let unavailableReason {
            let alert = NSAlert()
            alert.messageText = "Updates Unavailable"
            alert.informativeText = unavailableReason
            alert.runModal()
            return
        }
        controller?.checkForUpdates(nil)
    }

    /// Fixture, gallery and test launches must never reach the network, whatever the build carries.
    nonisolated static func runs(in mode: LaunchMode, environment: [String: String]) -> Bool {
        guard case .normal = mode else { return false }
        return environment["REINS_TEST"] != "1"
    }

    /// nil when the bundle can run the updater. Plain http is accepted only for 127.0.0.1, the local feed of
    /// `scripts/test-update.sh`; the update itself is still checked against the Ed25519 key.
    nonisolated static func configurationIssue(in info: [String: Any]) -> String? {
        guard let raw = info["SUFeedURL"] as? String, !raw.isEmpty else {
            return "This build has no update source. Install a release build to receive updates."
        }
        guard let url = URLComponents(string: raw), let host = url.host, !host.isEmpty,
              url.scheme == "https" || (url.scheme == "http" && host == "127.0.0.1"),
              url.user == nil, url.password == nil, url.fragment == nil else {
            return "This build has an invalid update source. Install a release build to receive updates."
        }
        guard let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else {
            return "This build has no valid update signing key. Install a release build to receive updates."
        }
        return nil
    }

    static func viewAction(_ run: @escaping @MainActor () -> Void) -> ToastAction {
        ToastAction(title: "View", systemImage: "arrow.down.circle", run: run)
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Sparkle keeps showing its own window; the toast only points at it, because it hides after a few seconds.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        logger.notice("Update \(update.versionString, privacy: .public) found, by user: \(state.userInitiated, privacy: .public)")
        guard !state.userInitiated else { return }
        reminder = toasts.show("Reins \(update.displayVersionString) is available", action: Self.viewAction { [weak self] in
            self?.checkForUpdates()
        })
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        logger.notice("Update window has the user's attention")
        clearReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        clearReminder()
    }

    private func clearReminder() {
        if let reminder { toasts.dismiss(id: reminder) }
        reminder = nil
    }
}
