import ReinsCore
import SwiftUI

/// One line about the other CLI at the top of a page that shows only one (Rules): its mark and name, how it stands in a
/// sentence (warn ink and icon when it needs a look), and a ghost button that opens it. A 48 pt `surface` block on the
/// well, radius 12, so switching to one CLI never hides how the other one stands.
struct CLISummaryBar: View {
    let cli: InventoryCLI
    let message: String
    var warn = false
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            CLIMark(cli, size: .small)
            Text(cli.label).reinsText(.bodyStrong, tone: .primary)
            HStack(spacing: Space.s6) {
                if warn { ReinsIcon(.warning, size: .inline, ink: TextTone.warn.color) }
                Text(message).reinsText(.body, tone: warn ? .warn : .secondary).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                HStack(spacing: Space.s4) {
                    Text(actionTitle)
                    Chevron(.right)
                }
            }
            .buttonStyle(.reins(.ghost))
        }
        .padding(.leading, Metrics.rowHorizontalPadding)
        .padding(.trailing, Space.s8)
        .frame(minHeight: Metrics.rowMinHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surface))
        .controlGround(.card)
        .accessibilityElement(children: .contain)
    }
}
