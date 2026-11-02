import SwiftUI

/// A System Settings style inset group: one bordered, rounded surface holding rows separated by hairlines.
/// Elevation is the border only; no shadow, and groups do not nest. Put `Row`s, `HeadRow`, `SectionRow`,
/// `EmptyRow` (or a `ForEach` of them) inside.
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id { Hairline() }
                    subview
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(Palette.surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// A 1 pt separator in the border colour.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.border).frame(height: 1).accessibilityHidden(true)
    }
}
