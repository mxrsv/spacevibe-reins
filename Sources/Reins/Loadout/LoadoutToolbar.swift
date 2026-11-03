import SwiftUI

/// Scope picker, the four filter chips and the note on what the counts rest on.
struct LoadoutToolbar: View {
    let model: LoadoutModel
    let view: LoadoutView
    let scopes: [LoadoutScope]

    var body: some View {
        HStack(spacing: 10) {
            ScopePicker(
                options: scopes.map { ScopeOption(id: $0.value, label: $0.label) },
                current: ScopeOption(id: view.scope.value, label: view.scope.label),
                minWidth: 110,
                onSelect: { model.setScope($0.id ?? LoadoutRows.globalScope) }
            )
            HStack(spacing: 6) {
                ForEach(LoadoutFilter.allCases, id: \.self) { filter in
                    FilterChip(filter.title, count: filter.count(in: view.counts), isOn: model.filter == filter) { model.filter = filter }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter")
            Spacer(minLength: 12)
            Text(model.usageNote)
                .font(ReinsFont.small)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
