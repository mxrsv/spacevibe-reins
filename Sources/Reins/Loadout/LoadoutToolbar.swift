import SwiftUI

/// Scope picker and the four filter chips. What the counts rest on is in the legend under the last card.
struct LoadoutToolbar: View {
    let model: LoadoutModel
    let view: LoadoutView
    let scopes: [LoadoutScope]

    var body: some View {
        HStack(spacing: Rhythm.toolGroups) {
            ScopePicker(
                options: scopes.map { ScopeOption(id: $0.value, label: $0.label) },
                current: ScopeOption(id: view.scope.value, label: view.scope.label),
                minWidth: Metrics.scopePickerMinWidth,
                onSelect: { model.setScope($0.id ?? LoadoutRows.globalScope) }
            )
            HStack(spacing: Rhythm.chips) {
                ForEach(LoadoutFilter.allCases, id: \.self) { filter in
                    FilterChip(filter.title, count: filter.count(in: view.counts), isOn: model.filter == filter) { model.filter = filter }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter")
            Spacer(minLength: 0)
        }
        .pageTools()
    }
}
