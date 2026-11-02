import SwiftUI

/// The small heading above a group: "Skills 12", "Failed commands 4". `lead` is usually a `CLIDot`.
struct GroupLabel<Lead: View>: View {
    let title: String
    var count: Int?
    var detail: String?
    let lead: Lead

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            lead
            Text(title).font(ReinsFont.smallStrong).foregroundStyle(Palette.textSecondary)
            if let count { Text("\(count)").font(ReinsFont.small).foregroundStyle(Palette.textTertiary) }
            if let detail { Text(detail).font(ReinsFont.small).foregroundStyle(Palette.textTertiary) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 20)
        .padding(.bottom, 7)
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
