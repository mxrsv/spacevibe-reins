import SwiftUI

/// A heading above a block that is not a card (the gallery's sections). A card's name goes in its `CardHeader` instead.
struct GroupLabel<Lead: View>: View {
    let title: String
    var count: Int?
    var detail: String?
    let lead: Lead

    var body: some View {
        HStack(alignment: .center, spacing: Space.s8) {
            lead
            Text(title).spaceVibeText(.captionStrong, tone: .secondary)
            if let count { Count(count) }
            if let detail { Text(detail).spaceVibeText(.caption, tone: .tertiary) }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s24)
        .padding(.bottom, Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension GroupLabel where Lead == EmptyView {
    init(_ title: String, count: Int? = nil, detail: String? = nil) {
        self.title = title
        self.count = count
        self.detail = detail
        self.lead = EmptyView()
    }
}

extension GroupLabel {
    init(_ title: String, count: Int? = nil, detail: String? = nil, @ViewBuilder lead: () -> Lead) {
        self.title = title
        self.count = count
        self.detail = detail
        self.lead = lead()
    }
}
