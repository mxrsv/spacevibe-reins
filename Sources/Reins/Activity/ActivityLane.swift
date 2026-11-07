import SwiftUI

/// One CLI: a card of its live sessions and a card of its failed commands. What cannot be measured is one region under
/// both lanes (`ActivityScreen`), so the two lanes end on the same line.
struct ActivityLane: View {
    let cli: CoreCLI
    let report: CoreActivityReport
    let now: Date
    let elapsedMs: Double
    var revealActions = false
    let onStop: (CoreActivitySession) -> Void

    @State private var failureLimit = ActivityRows.failurePage

    var body: some View {
        let sessions = ActivityRows.sessions(report, cli: cli)
        let failures = ActivityRows.failures(report, cli: cli)
        VStack(alignment: .leading, spacing: Rhythm.laneCards) {
            GroupedList {
                CardHeader(
                    cli.label, count: sessions.isEmpty ? nil : sessions.count,
                    detail: sessions.isEmpty ? nil : (sessions.count == 1 ? "session" : "sessions"),
                    lead: { CLIDot(core: cli, decorative: true) }
                )
                if sessions.isEmpty { EmptyRow("No \(cli.label) session is running.") }
                ForEach(sessions) { session in
                    ActivitySessionRow(session: session, elapsedMs: elapsedMs, revealActions: revealActions) { onStop(session) }
                }
            }
            GroupedList {
                CardHeader("Failed commands", count: failures.isEmpty ? nil : failures.count)
                if failures.isEmpty { EmptyRow("No failed commands in the last \(ActivityModel.historyDays) days.") }
                ForEach(failures.prefix(failureLimit), id: \.key) { failure in
                    ActivityFailureRow(failure: failure, now: now)
                }
                if let next = ActivityRows.nextPage(shown: failureLimit, total: failures.count, page: ActivityRows.failurePage) {
                    ShowMoreRow(reveal: next.reveal, hiddenAfter: next.hiddenAfter) { failureLimit += ActivityRows.failurePage }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cli.label)
    }
}
