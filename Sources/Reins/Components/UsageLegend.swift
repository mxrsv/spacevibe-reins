import SwiftUI

/// The key to the usage states. One line under a list.
struct UsageLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            item(swatch: Capsule().fill(Palette.textSecondary).frame(width: 22, height: Metrics.barHeight), "counted from logs")
            item(swatch: Text("0").font(ReinsFont.smallStrong).foregroundStyle(Palette.dangerInk), "never ran")
            item(swatch: Capsule().strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 22, height: Metrics.barHeight), "not counted yet")
            item(swatch: Image(systemName: "exclamationmark.triangle").imageScale(.small), "not measurable")
            Spacer(minLength: 0)
        }
        .font(ReinsFont.small)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage key: counted from logs, never ran, not counted yet, not measurable")
    }

    private func item<S: View>(swatch: S, _ text: String) -> some View {
        HStack(spacing: 7) {
            swatch
            Text(text)
        }
    }
}
