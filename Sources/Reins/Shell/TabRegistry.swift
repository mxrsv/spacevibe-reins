import SwiftUI

/// The single place that lists the app's tabs. Order is sidebar order and decides `⌘1`, `⌘2`, `⌘3`.
/// A screen agent replaces its stub here with the real tab; nothing else in `Shell/` changes.
/// Behind `AgentsSwitch` the Agents page takes Rules' place at `⌘2` (spec AG1), until the cut-over removes Rules.
@MainActor
enum TabRegistry {
    static func makeTabs(agents: Bool = AgentsSwitch.isOn()) -> [any ReinsTab] {
        let second: any ReinsTab
        if agents { second = AgentsTab() } else { second = RulesTab() }
        return [LoadoutTab(), second, ActivityTab()]
    }
}
