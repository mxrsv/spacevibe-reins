import ReinsCore
import SwiftUI

/// One CLI's block in the Limits detail: its mark, name and plan tag with a line under them for the reading's age, a
/// trailing slot for the info button, and its tiles underneath. A `surface` block on the page's well with no border; the tiles inside are the only
/// nesting (one level), separated from each other by space alone.
struct LimitCard<Detail: View, Trailing: View, Content: View>: View {
    let cli: LimitsCLI
    let title: String
    var plan: String?
    let detail: Detail
    let trailing: Trailing
    let content: Content

    init(_ cli: LimitsCLI, title: String, plan: String? = nil, @ViewBuilder detail: () -> Detail, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.cli = cli
        self.title = title
        self.plan = plan
        self.detail = detail()
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(spacing: Space.s12) {
                CLIMark(cli)
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s8) {
                        Text(title).reinsText(.title, tone: .primary).lineLimit(1).layoutPriority(1)
                        if let plan { Tag(plan) }
                    }
                    detail
                }
                Spacer(minLength: Space.s8)
                trailing
            }
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.s12) { content }
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .contain)
    }
}
