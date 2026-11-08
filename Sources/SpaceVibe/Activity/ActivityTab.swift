import SwiftUI

/// Registers Activity with the shell: sidebar item, badge, palette entries and the screen. With the v5 switch on (`isV5`) the
/// screen is the three-tab page of `ActivityCanvas` and the status bar lists its keys; without it, today's screen.
@MainActor
final class ActivityTab: SpaceVibeTab {
    static let tabID = "activity"

    let id = ActivityTab.tabID
    let title = "Activity"
    let icon = SpaceVibeGlyph.activity
    let model: ActivityModel

    init(env: AppEnvironment? = nil, isV5: Bool = false) { model = ActivityModel(env: env ?? .shared, isV5: isV5) }

    init(model: ActivityModel) { self.model = model }

    var glyph: any GlyphSource { model.isV5 ? ContentGlyph.pulse : icon }

    /// Failure groups whose last failure was within 24 hours. The v5 sidebar gives a count to Agents only (V5-R50), so none here.
    var badge: TabBadge? {
        guard !model.isV5 else { return nil }
        let count = model.recentFailures
        return count > 0 ? TabBadge(value: count, alert: true, spoken: "\(count) recent failed \(count == 1 ? "command" : "commands")") : nil
    }

    var paletteActions: [PaletteEntry] {
        [PaletteEntry(id: "activity.refresh", title: "Refresh activity", icon: .refresh, keywords: ["reload", "sessions", "failures"]) { [model] in
            model.refreshNow()
        }]
    }

    /// Only the keys `ActivityCanvas.keys` wires (V5-R36), per tab.
    var hints: [KeyHint] { model.isV5 ? ActivityStatusBar.hints(for: model.pane) : [] }
    var source: String? { model.isV5 ? ActivityStatusBar.source : nil }

    var content: AnyView { model.isV5 ? AnyView(ActivityCanvas(model: model)) : AnyView(ActivityScreen(model: model)) }

    /// The Stop confirmation over the whole window (V5-R59).
    var modal: AnyView? {
        guard model.isV5, let session = model.pendingStop else { return nil }
        return AnyView(StopSessionPanel(session: session, isStopping: model.isStopping, cancel: model.cancelStop, confirm: model.confirmStop))
    }
}

/// The key hints and the data source of the status bar on the Activity page (V5-R36, V5-R69).
enum ActivityStatusBar {
    static let source = "Read from local session logs"

    static func hints(for pane: ActivityPane) -> [KeyHint] {
        let move = KeyHint(keys: "J K", label: "move"), detail = KeyHint(keys: "\u{21B5}", label: "detail")
        let filter = KeyHint(keys: "/", label: "filter"), tabs = KeyHint(keys: "1 2 3", label: "tabs")
        switch pane {
        case .running: return [move, detail, KeyHint(keys: "S", label: "stop"), filter, tabs]
        case .failed: return [move, detail, KeyHint(keys: "C", label: "copy"), filter, tabs]
        case .files: return [move, detail, KeyHint(keys: "O", label: "show in Finder"), tabs]
        }
    }
}
