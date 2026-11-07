import SwiftUI

/// The text block of an Activity row: a title the caller has already styled, then muted lines under it. A line that is
/// machine output (a compiler error, a curl message) is set as code. Built here because `RowText` holds one subtitle line
/// and failures need up to three.
struct ActivityLines: View {
    struct Line: Hashable {
        let text: String
        var code = false

        init(_ text: String, code: Bool = false) {
            self.text = text
            self.code = code
        }
    }

    let title: Text
    var lines: [Line]
    /// The full text on hover when the title is cut (a long command, a long path).
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            title.lineLimit(1).truncationMode(.tail).help(help ?? "")
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .reinsText(line.code ? .code : .caption, tone: line.code ? .secondary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
