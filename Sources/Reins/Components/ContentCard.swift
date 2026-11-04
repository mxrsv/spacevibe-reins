import SwiftUI

/// A card that holds one free-form view instead of a header and rows (the Limits page's detail): the same `surface` block
/// on the well as a `GroupedList`, radius 12, with 24 pt inside. Controls in it take the card's ground.
struct ContentCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surface))
            .controlGround(.card)
            .accessibilityElement(children: .contain)
    }
}
