import Foundation

/// The screens that move to the Go core one at a time (plan S.2, "Cut-over order").
enum CoreScreen: String, CaseIterable, Sendable {
    case activity, limits, loadout, loadoutWrites, rules
}

/// Which `CoreService` each screen uses while both engines exist. `SPACEVIBE_CORE_SCREENS` is a comma list of screen
/// names; a screen in it goes to the Go core, any other stays in process. It is read only when
/// `CoreEnvironment.overridesAllowed`, so a release build keeps the old path until a screen cuts over. An unknown name
/// is ignored. No screen asks for this yet.
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
