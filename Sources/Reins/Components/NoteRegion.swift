import ReinsCore
import SwiftUI

/// Plain-text notes about what the screen cannot know ("Cannot be measured"): one region under the lists it qualifies,
/// one column per CLI so both start on the same line, and lines that apply to both once at the end. Not a card: it is
/// a footnote, set off by a hairline above it.
struct NoteRegion: View {
    struct Column: Identifiable {
        let cli: InventoryCLI
        let notes: [String]
        var id: InventoryCLI { cli }
    }

    let title: String
    let columns: [Column]
    var shared: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text(title).reinsText(.captionStrong, tone: .secondary).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Space.s24) {
                ForEach(columns) { column in
                    VStack(alignment: .leading, spacing: Space.s6) {
                        HStack(spacing: Space.s6) {
                            CLIDot(column.cli, decorative: true)
                            Text(column.cli.label).reinsText(.captionStrong, tone: .secondary)
                        }
                        .padding(.bottom, Space.s2)
                        ForEach(column.notes, id: \.self) { note in line(note) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
                }
            }
            ForEach(shared, id: \.self) { note in line(note) }
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s6) {
            ReinsIcon(.info, size: .inline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .reinsText(.caption, tone: .tertiary)
    }
}
