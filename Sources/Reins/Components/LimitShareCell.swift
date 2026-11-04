import SwiftUI

/// A window's share left in the Limits list: the ten-cell ruler and the number after it, as wide as a usage cell so the
/// two read alike. An unknown share (`nil`) draws the dashed outline, and its text is tertiary.
struct LimitShareCell: View {
    let share: Double?
    let text: String
    let fill: Color
    var tone: TextTone = .primary

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            Ruler(share: share, fill: fill)
            Text(text)
                .reinsText(.number, tone: share == nil ? .tertiary : tone)
                .lineLimit(1)
                .frame(width: Metrics.usageNumberWidth, alignment: .trailing)
        }
        .frame(width: Metrics.usageCellWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
