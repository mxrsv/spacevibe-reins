import SwiftUI

/// One fact about the window on the Limits page ("Resets in", "3 h 12 min"): a raised block of its own inside the detail
/// card, the one place a block sits in a card (spec v3, Cards). A note and an accessory (a button) can sit under the value;
/// a button there takes `surface`, since the tile is already `surfaceRaised`.
struct FactTile<Accessory: View>: View {
    let label: String
    let value: String
    var tone: TextTone = .primary
    var note: String?
    let accessory: Accessory

    init(_ label: String, value: String, tone: TextTone = .primary, note: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.label = label
        self.value = value
        self.tone = tone
        self.note = note
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(label).reinsText(.caption, tone: .tertiary)
            Text(value).reinsText(.title, tone: tone).lineLimit(1)
            if let note {
                Text(note).reinsText(.caption, tone: .secondary).fixedSize(horizontal: false, vertical: true)
            }
            if Accessory.self != EmptyView.self { accessory.padding(.top, Space.s4) }
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surfaceRaised))
        .controlGround(.well)
        .accessibilityElement(children: .contain)
    }
}

extension FactTile where Accessory == EmptyView {
    init(_ label: String, value: String, tone: TextTone = .primary, note: String? = nil) {
        self.init(label, value: value, tone: tone, note: note) { EmptyView() }
    }
}
