import SwiftUI

/// The single place that lists the app's tabs. Order is sidebar order and decides `⌘1`, `⌘2`, `⌘3`.
/// A screen agent replaces its stub here with the real tab; nothing else in `Shell/` changes.
///
/// With the v5 switch on (`isV5`, read once by the app) the list is the v5 sidebar: Agents, Activity and Limits. Activity stays
/// a `PlannedPageTab` placeholder until its region is built (U12).
@MainActor
enum TabRegistry {
    static let agentsID = "agents"
    static let activityID = "activity"
    static let limitsID = "limits"

    static func makeTabs(isV5: Bool = false) -> [any SpaceVibeTab] {
        guard isV5 else {
            return [
                LoadoutTab(),
                RulesTab(),
                ActivityTab(),
            ]
        }
        return [
            AgentsPage(),
            PlannedPageTab(id: activityID, title: "Activity", glyph: ContentGlyph.pulse),
            LimitsTab(),
        ]
    }
}
