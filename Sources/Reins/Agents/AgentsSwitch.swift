import Foundation

/// The development switch for the Agents page (spec AG1; plan A8). `REINS_AGENTS=1` puts Agents at `⌘2` in place of Rules,
/// but only in a debug build, or in any build that also has `REINS_TEST=1`: the second case lets the owner try the release
/// bundle from `scripts/build-app.sh` on a synthetic home, and `REINS_TEST=1` makes `Roots.resolve` refuse the real home.
/// No user sets both. Removed at cut-over (plan A12) together with the Rules tab.
enum AgentsSwitch {
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    static func isOn(environment: [String: String] = ProcessInfo.processInfo.environment, debugBuild: Bool = isDebugBuild) -> Bool {
        guard environment["REINS_AGENTS"] == "1" else { return false }
        return debugBuild || environment["REINS_TEST"] == "1"
    }
}
