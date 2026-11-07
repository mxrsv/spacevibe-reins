import SwiftUI

/// A quiet box inside a card or dialog: the rules a write replaces, the rules it writes. `surfaceRaised` with a border,
/// radius 8, 12 pt inside.
struct InsetBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Space.s6) { content }
            .padding(Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.surfaceRaised))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
    }
}

/// A warning line inside a dialog: the triangle and the text on the warn tint.
struct WarningNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s8) {
            SpaceVibeIcon(.warning, ink: TextTone.warn.color)
            Text(text).spaceVibeText(.caption, tone: .primary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.warnTint))
    }
}

/// A raised block inside a card with no border (spec v3, Cards: the one nesting, like `FactTile`): Settings' font size
/// sample and the note that says why updates are off. `surfaceRaised`, radius 8; `inset` is the space inside.
struct RaisedBlock<Content: View>: View {
    var inset: EdgeInsets = EdgeInsets(top: Space.s12, leading: Space.s12, bottom: Space.s12, trailing: Space.s12)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous).fill(Palette.surfaceRaised))
    }
}
