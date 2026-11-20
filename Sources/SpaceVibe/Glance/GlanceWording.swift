/// Every sentence the glance widget shows (spec `docs/specs/2026-11-19-session-glance-widget.md`, GW-R2 to GW-R5). English,
/// like the rest of the app; the words follow GLOSSARY.md.
enum GlanceWording {
    static let noSession = "No session running"
    static let noTool = "No tool running"
    /// Where a click goes when no host app is found (GW6).
    static let activity = "Activity"
    static let widgetName = "SpaceVibe session widget"

    static func label(_ state: GlanceState) -> String {
        switch state {
        case .waiting: "Waiting for you"
        case .working: "Running"
        case .done: "Done"
        case .unmeasurable: "Unmeasurable"
        case .idle: "Idle"
        }
    }

    /// A row's second line: the open tool call; why the state cannot be measured (GW9); "No tool running" for an idle
    /// session; the core's state sentence when a working, waiting or done session has no tool call open.
    static func detail(_ entry: GlanceEntry) -> String {
        switch entry.state {
        case .unmeasurable: entry.stateReason
        case .idle: entry.toolText ?? noTool
        case .working, .waiting, .done: entry.toolText ?? entry.stateReason
        }
    }

    /// What VoiceOver reads for a strip entry.
    static func spoken(_ entry: GlanceEntry) -> String {
        "\(entry.cli.label), \(entry.title), \(label(entry.state))"
    }

    static func overflow(_ count: Int) -> String { "+\(count)" }
    static func overflowSpoken(_ count: Int) -> String { count == 1 ? "1 more session" : "\(count) more sessions" }
}
