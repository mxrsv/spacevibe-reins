import Foundation

/// The screens that still have an in-process path, and move to the Go core one at a time (plan S.2, "Cut-over order").
/// A screen that has cut over leaves this list for good: Activity and Stop (S.3) always use the core, so its name is no
/// longer accepted in `SPACEVIBE_CORE_SCREENS`.
enum CoreScreen: String, CaseIterable, Sendable {
    case limits, loadout, loadoutWrites, rules
}

/// Which `CoreService` each screen uses while both engines exist. `SPACEVIBE_CORE_SCREENS` is a comma list of screen
/// names; a screen in it goes to the Go core, any other stays in process (a screen that has cut over is not one of them). It is read only when
/// `CoreEnvironment.overridesAllowed`, so a release build keeps the old path until a screen cuts over. An unknown name
/// is ignored. `AppEnvironment.core(for:)` is the one place a screen asks.
struct CoreRouting: Equatable, Sendable {
    let viaCore: Set<CoreScreen>

    init(viaCore: Set<CoreScreen>) { self.viaCore = viaCore }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard CoreEnvironment.overridesAllowed(environment), let list = environment[CoreEnvironment.screensOverride] else {
            self.init(viaCore: [])
            return
        }
        self.init(viaCore: Set(list.split(separator: ",").compactMap { CoreScreen(rawValue: $0.trimmingCharacters(in: .whitespaces)) }))
    }

    func usesCore(_ screen: CoreScreen) -> Bool { viaCore.contains(screen) }

    /// The client is built only when the screen goes to the core, so a process that routes nothing never spawns it.
    func service(for screen: CoreScreen, inProcess: any CoreService, core: () -> any CoreService) -> any CoreService {
        usesCore(screen) ? core() : inProcess
    }
}
