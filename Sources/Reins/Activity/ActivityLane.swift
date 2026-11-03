import ReinsCore
import SwiftUI

/// One CLI: its live sessions, its failed commands, and what cannot be measured for it.
struct ActivityLane: View {
    let cli: InventoryCLI
    let report: ActivityReport
    let now: Date
    let elapsedMs: Double
    var revealActions = false
    let onStop: (ActivitySession) -> Void

    @State private var failureLimit = ActivityRows.failurePage

    private static let costLimit = "Cost is estimated from logged tokens at API prices (API-equivalent), not what you are billed."

    var body: some View {
        let sessions = ActivityRows.sessions(report, cli: cli)
        let failures = ActivityRows.failures(report, cli: cli)
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel(cli.label, count: sessions.isEmpty ? nil : sessions.count, detail: sessions.isEmpty ? nil : (sessions.count == 1 ? "session" : "sessions")) {
                CLIDot(cli, decorative: true)
            }
            GroupedList {
                if sessions.isEmpty { EmptyRow("No \(cli.label) session is running.") }
                ForEach(sessions) { session in
                    ActivitySessionRow(session: session, elapsedMs: elapsedMs, revealActions: revealActions) { onStop(session) }
                }
            }
            GroupLabel("Failed commands", count: failures.isEmpty ? nil : failures.count)
            GroupedList {
                if failures.isEmpty { EmptyRow("No failed commands in the last \(ActivityModel.historyDays) days.") }
                ForEach(failures.prefix(failureLimit), id: \.key) { failure in
                    ActivityFailureRow(failure: failure, now: now)
                }
                if let next = ActivityRows.nextPage(shown: failureLimit, total: failures.count, page: ActivityRows.failurePage) {
                    ShowMoreRow(reveal: next.reveal, hiddenAfter: next.hiddenAfter) { failureLimit += ActivityRows.failurePage }
                }
            }
            GroupLabel("Cannot be measured")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ActivityRows.limits(report, cli: cli), id: \.code) { limit in
                    limitLine(limit.text)
                }
                limitLine(Self.costLimit)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cli.label)
    }

    private func limitLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").imageScale(.small).padding(.top, 1).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(ReinsFont.small)
        .foregroundStyle(Palette.textTertiary)
    }
}
