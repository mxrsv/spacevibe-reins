import SwiftUI

/// Registers Activity with the shell: sidebar item, badge, palette entries and the screen.
@MainActor
final class ActivityTab: ReinsTab {
    static let tabID = "activity"

    let id = ActivityTab.tabID
    let title = "Activity"
    let icon = ReinsGlyph.activity
    let model: ActivityModel

    init(env: AppEnvironment? = nil) { model = ActivityModel(env: env ?? .shared) }

    init(model: ActivityModel) { self.model = model }

    /// Failure groups whose last failure was within 24 hours.
    var badge: TabBadge? {
        let count = model.recentFailures
        return count > 0 ? TabBadge(value: count, alert: true, spoken: "\(count) recent failed \(count == 1 ? "command" : "commands")") : nil
    }

    var paletteActions: [PaletteEntry] {
        [PaletteEntry(id: "activity.refresh", title: "Refresh activity", icon: .refresh, keywords: ["reload", "sessions", "failures"]) { [model] in
            model.refreshNow()
        }]
    }

    var content: AnyView { AnyView(ActivityScreen(model: model)) }
}
