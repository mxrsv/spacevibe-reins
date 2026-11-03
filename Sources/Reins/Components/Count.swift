import SwiftUI

/// A count beside a label: "Skills 10", "All 22", the sidebar's badge. One look everywhere: `count` type (tabular digits)
/// in the tertiary tone, or semibold in the danger tone when it is an alert.
struct Count: View {
    let value: Int
    var alert = false

    init(_ value: Int, alert: Bool = false) {
        self.value = value
        self.alert = alert
    }

    var body: some View {
        Text("\(value)")
            .reinsText(alert ? .countStrong : .count, tone: alert ? .danger : .tertiary)
            .lineLimit(1)
    }
}
