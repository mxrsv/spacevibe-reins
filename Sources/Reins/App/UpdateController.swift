import AppKit
import Observation
import OSLog
import Sparkle

/// Sparkle owns the check, the update window, signature verification, installation and relaunch. This class decides
/// whether the updater runs at all, adds a toast when a scheduled check finds an update, and keeps what Settings > Update
/// shows: the last check's result and time and the automatic-check switch.
///
/// It is the only code in the app that reaches the network (AGENTS.md S-R5), and only when the build has a feed.
@MainActor
@Observable
final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    /// What Settings > Update says about this launch (spec `docs/specs/2026-11-04-reins-settings.md`, Update).
    enum Status: Equatable {
        /// No check has finished since launch: Settings shows the time of the last one only.
        case notChecked
        case checking
        case upToDate
        case available(version: String)
        /// The check could not finish (no network, a feed that cannot be read).
        case failed
        /// This launch cannot update; the reason is shown as is.
        case unavailable(String)
    }

    /// Set by `start` and Sparkle's callbacks; the screenshot runs set them, and `isRunning`, to draw each state.
    var status: Status = .notChecked
    var lastCheck: Date?
    /// Sparkle's automatic daily check. Off and disabled while the updater does not run.
    var automaticChecks = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != automaticChecks else { return }
            updater.automaticallyChecksForUpdates = automaticChecks
        }
    }
    /// True once Sparkle's updater has started.
    var isRunning = false
    /// `CFBundleShortVersionString` and `CFBundleVersion`; nil outside an app bundle.
    var version: String?
    var build: String?

    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let logger = Logger(subsystem: "dev.spacevibe.app", category: "updates")
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var reminder: UUID?
    @ObservationIgnored private var showingInFocus = false

    init(toasts: ToastCenter, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.toasts = toasts
        version = info["CFBundleShortVersionString"] as? String
        build = info["CFBundleVersion"] as? String
        super.init()
    }

    func start(
        mode: LaunchMode,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        info: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        guard controller == nil else { return }
        guard Self.runs(in: mode, environment: environment) else {
            status = .unavailable("Updates are off in this launch mode.")
            return
        }
        if let issue = Self.configurationIssue(in: info) {
            status = .unavailable(issue)
            logger.notice("Updater off: \(issue, privacy: .public)")
            return
        }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do {
            try updater.updater.start()
            controller = updater
            isRunning = true
            automaticChecks = updater.updater.automaticallyChecksForUpdates
            lastCheck = updater.updater.lastUpdateCheckDate
            logger.notice("Updater started, automatic checks: \(updater.updater.automaticallyChecksForUpdates, privacy: .public)")
        } catch {
            status = .unavailable("Updates could not start. Quit and reopen Reins, then try again.")
            logger.error("Updater failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }


    /// Settings' `Check Now`: Sparkle's background probe, so the result shows in place and no Sparkle window opens.
    func checkNow() {
        guard let updater = controller?.updater, updater.canCheckForUpdates, !updater.sessionInProgress, status != .checking else { return }
        status = .checking
        updater.checkForUpdateInformation()
    }

    /// The menu's `Check for Updates…` and Settings' `View Update`: Sparkle's own window.
    func checkForUpdates() {
        if case .unavailable(let reason) = status {
            let alert = NSAlert()
            alert.messageText = "Updates Unavailable"
            alert.informativeText = reason
            alert.runModal()
            return
        }
        controller?.checkForUpdates(nil)
    }

    /// Fixture, gallery and test launches must never reach the network, whatever the build carries.
    nonisolated static func runs(in mode: LaunchMode, environment: [String: String]) -> Bool {
        guard case .normal = mode else { return false }
        return environment[CoreEnvironment.variable("TEST")] != "1"
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
        ToastAction(title: "View", icon: .download, run: run)
    }

    /// What a finished check leaves: the found or not-found callback has set the result (a probe reaches both through
    /// `SPUBasicUpdateDriver`); a cycle that ended without either is up to date when its error is Sparkle's "no update",
    /// a failure for any other error, and otherwise says nothing new.
    nonisolated static func status(afterCycle current: Status, error: Error?) -> Status {
        guard current == .checking else { return current }
        guard let error = error as NSError? else { return .notChecked }
        return error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) ? .upToDate : .failed
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        // Every check, the probe included, moves Sparkle's last check date (SPUUpdater checkForUpdatesWithDriver:).
        lastCheck = updater.lastUpdateCheckDate
        status = Self.status(afterCycle: status, error: error)
        if let error { logger.notice("Update cycle ended: \(error.localizedDescription, privacy: .public)") }
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Sparkle keeps showing its own window; the toast only points at it, because it hides after a few seconds.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle always shows the update. At launch it shows it in focus, so a toast would only flash behind the window.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        showingInFocus = immediateFocus
        return true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let wantsToast = !state.userInitiated && !showingInFocus
        logger.notice("Update \(update.versionString, privacy: .public) found, by user: \(state.userInitiated, privacy: .public), toast: \(wantsToast, privacy: .public)")
        guard wantsToast else { return }
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
