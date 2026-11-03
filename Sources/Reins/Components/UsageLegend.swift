import SwiftUI

/// The key to the usage states, one line under the last card. `note` (what the counts rest on) ends the line.
struct UsageLegend: View {
    var note: String?

    var body: some View {
        HStack(spacing: Space.s16) {
            item(swatch: Capsule().fill(Palette.textSecondary).frame(width: Metrics.legendSwatchWidth, height: Metrics.rulerHeight), "counted from logs")
            item(swatch: Text("0").reinsText(.countStrong, tone: .danger), "never ran")
            item(swatch: Capsule().strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: Metrics.legendSwatchWidth, height: Metrics.rulerHeight), "not counted yet")
            item(swatch: ReinsIcon(.warning, size: .inline), "not measurable")
            Spacer(minLength: 0)
            if let note { Text(note).lineLimit(1).truncationMode(.tail).accessibilityAddTraits(.updatesFrequently) }
        }
        .reinsText(.caption, tone: .tertiary)
        .padding(.horizontal, Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage key: counted from logs, never ran, not counted yet, not measurable" + (note.map { ". \($0)" } ?? ""))
    }

    private func item<S: View>(swatch: S, _ text: String) -> some View {
        HStack(spacing: Space.s6) {
            swatch
            Text(text)
        }
    }
}
