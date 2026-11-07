import SwiftUI

/// The single place that lists the app's tabs. Order is sidebar order and decides `⌘1`, `⌘2`, `⌘3`.
/// A screen agent replaces its stub here with the real tab; nothing else in `Shell/` changes.
@MainActor
enum TabRegistry {
    static func makeTabs() -> [any ReinsTab] {
        [
            LoadoutTab(),
            RulesTab(),
            ActivityTab(),
        ]
    }
}
