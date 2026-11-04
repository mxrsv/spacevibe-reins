import ReinsCore
import SwiftUI

/// One list for both CLIs: the dots on each row say who edited the file. The engine's `label` is the shortest path tail
/// that tells two files apart, so the folder part is muted and the file name stronger; the full path is the help text.
struct ActivityFileHistory: View {
    let files: [ActivityFileRow]
    let now: Date
    @State private var limit = ActivityRows.filePage

    var body: some View {
        GroupedList {
            CardHeader("File history", columns: {
                if !files.isEmpty { Text("across sessions \u{00B7} last \(ActivityModel.historyDays) days") }
            })
            if files.isEmpty { EmptyRow("No file edits in the last \(ActivityModel.historyDays) days.") }
            ForEach(files.prefix(limit), id: \.path) { file in
                ActivityFileRowView(file: file, now: now)
            }
            if let next = ActivityRows.nextPage(shown: limit, total: files.count, page: ActivityRows.filePage) {
                ShowMoreRow(reveal: next.reveal, hiddenAfter: next.hiddenAfter) { limit += ActivityRows.filePage }
            }
        }
    }
}

private struct ActivityFileRowView: View {
    let file: ActivityFileRow
    let now: Date

    var body: some View {
        let cut = file.label.lastIndex(of: "/").map { file.label.index(after: $0) } ?? file.label.startIndex
        let folder = String(file.label[..<cut])
        let name = String(file.label[cut...])
        let title = Text(folder).reinsText(.codeBody, tone: .tertiary) + Text(name).reinsText(.codeTitle, tone: .primary)
        Row {
            ActivityLines(title: title, lines: [ActivityFormat.projects(file.projects)].compactMap { $0 }.map { ActivityLines.Line($0) }, help: file.path)
        }
        .lead { ReinsIcon(.file, size: .row) }
        .cells {
            HStack(spacing: Space.s4) {
                ForEach(file.clis, id: \.rawValue) { CLIDot($0) }
            }
            .frame(width: Metrics.fileCLIsWidth, alignment: .trailing)
            Text([ActivityFormat.plural(file.edits, "edit"), ActivityFormat.plural(file.sessions, "session"), ActivityFormat.ago(file.last, now: now)].joined(separator: " \u{00B7} "))
                .reinsText(.caption, tone: .tertiary)
                .frame(width: Metrics.fileMetaWidth, alignment: .trailing)
        }
        .accessibilityLabel(file.path)
    }
}
