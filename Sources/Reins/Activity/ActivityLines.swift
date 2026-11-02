import SwiftUI

/// The text block of an Activity row: a title the caller has already styled, then muted lines under it.
/// Built here because `RowText` holds one subtitle line and failures need up to three.
struct ActivityLines: View {
    let title: Text
    var lines: [String]
    /// The full text on hover when the title is cut (a long command, a long path).
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title.lineLimit(1).truncationMode(.tail).help(help ?? "")
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(ReinsFont.small)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

/// The last row of a capped list: "Show 8 more" and how many stay hidden.
struct ShowMoreRow: View {
    let reveal: Int
    let hiddenAfter: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Show \(reveal) more").font(ReinsFont.bodyStrong).foregroundStyle(Palette.accent)
                if hiddenAfter > 0 {
                    Text("\(hiddenAfter) more after that").font(ReinsFont.small).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
