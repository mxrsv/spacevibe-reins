import SwiftUI

/// One fact about the window on the Limits page ("Resets in", "3 h 12 min"): a raised block of its own inside the detail
/// card, the one place a block sits in a card (spec v3, Cards). Radius 8, 12 pt inside, the label in `caption` and the
/// value in `title`; the three tiles of a row share one height.
struct FactTile: View {
    let label: String
    let value: String
    var tone: TextTone = .primary

    init(_ label: String, value: String, tone: TextTone = .primary) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).reinsText(.caption, tone: .secondary)
            Text(value).reinsText(.title, tone: tone).lineLimit(1)
        }
        .padding(Space.s12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous).fill(Palette.surfaceRaised))
        .accessibilityElement(children: .combine)
    }
}
