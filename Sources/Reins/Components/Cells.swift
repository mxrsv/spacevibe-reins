import SwiftUI

/// A number in a column (cost, a count of runs), right-aligned in a fixed width so the column lines up.
struct NumberCell: View {
    let text: String
    var muted = false
    var width: CGFloat = Metrics.costWidth

    var body: some View {
        Text(text)
            .reinsText(.number, tone: muted ? .tertiary : .primary)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

/// A state tag right-aligned in a fixed column, so the text before it keeps one width whatever the state says.
struct StateCell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.frame(width: Metrics.stateWidth, alignment: .trailing)
    }
}
