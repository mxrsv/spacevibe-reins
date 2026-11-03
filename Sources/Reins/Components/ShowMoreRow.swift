import SwiftUI

/// The last row of a capped list: "Show 8 more" and how many stay hidden after that.
struct ShowMoreRow: View {
    let reveal: Int
    let hiddenAfter: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s8) {
                Text("Show \(reveal) more").reinsText(.bodyStrong, tone: .accent)
                if hiddenAfter > 0 {
                    Text("\(hiddenAfter) more after that").reinsText(.caption, tone: .tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Metrics.separatorInset)
            .padding(.trailing, Metrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: Metrics.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: 0)
        .groupedListPart(.plain)
    }
}
