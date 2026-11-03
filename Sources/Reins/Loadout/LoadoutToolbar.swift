import SwiftUI

/// Scope picker, the four filter chips and the note on what the counts rest on.
struct LoadoutToolbar: View {
    let model: LoadoutModel
    let view: LoadoutView
    let scopes: [LoadoutScope]

    var body: some View {
        HStack(spacing: 10) {
            LoadoutScopePicker(model: model, current: view.scope, scopes: scopes)
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

/// Global or one discovered project. A menu in the app; headless screenshots cannot draw one, so they get the closed label.
private struct LoadoutScopePicker: View {
    let model: LoadoutModel
    let current: LoadoutScope
    let scopes: [LoadoutScope]
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            label
        } else {
            Menu {
                ForEach(scopes, id: \.value) { scope in
                    Button {
                        model.setScope(scope.value)
                    } label: {
                        if scope.value == current.value { Label(scope.label, systemImage: "checkmark") } else { Text(scope.label) }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Scope")
            .accessibilityValue(current.label)
        }
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return HStack(spacing: 8) {
            Text(current.label).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary).accessibilityHidden(true)
        }
        .font(ReinsFont.body)
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 10)
        .frame(minWidth: 110, alignment: .leading)
        .frame(height: Metrics.controlHeight)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(shape)
    }
}
