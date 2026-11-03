import SwiftUI

/// The tile that stands in for windows when a CLI has no reading: "No reading yet", "Not installed", "Not measurable".
/// Same block as `LimitTile` (raised fill, no border); `warn` marks a CLI the app cannot read, neutral a plain fact.
/// An optional action sits under the text ("Copy /usage").
struct LimitNoteTile: View {
    let title: String
    let text: String
    var isWarn = false
    var action: (title: String, systemImage: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.s12) {
            Image(systemName: isWarn ? "exclamationmark.triangle" : "info.circle")
                .imageScale(.medium)
                .foregroundStyle(isWarn ? Palette.warnInk : Palette.text)
                .frame(width: Metrics.limitTileIconSize, height: Metrics.limitTileIconSize)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(isWarn ? Palette.warnTint : Palette.surface))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).reinsText(.title, tone: .primary)
                    Text(text).reinsText(.body, tone: .secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let action {
                    Button(action: action.run) {
                        HStack(spacing: Space.s6) {
                            Image(systemName: action.systemImage).imageScale(.small).accessibilityHidden(true)
                            Text(action.title)
                        }
                    }
                    .buttonStyle(.reins(.normal))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surfaceRaised))
        .accessibilityElement(children: .contain)
    }
}
