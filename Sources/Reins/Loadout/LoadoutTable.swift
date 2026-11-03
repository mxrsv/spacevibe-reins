import ReinsCore
import SwiftUI

/// The scrolling part of the screen: banners, the matrix table with a header that stays put, and the legend.
struct LoadoutTable: View {
    let model: LoadoutModel
    let view: LoadoutView
    let data: LoadoutData
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            page.modifier(ShotFit())
        } else {
            ScrollViewReader { proxy in
                ScrollView { page.frame(maxWidth: .infinity, alignment: .topLeading) }
                    .onChange(of: model.jumpToken) { _, _ in scrollToSelection(proxy) }
            }
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners
            tableLayout
            UsageLegend()
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 8) {
            if model.scanFailure != nil {
                Banner(.warn, message: "Usage could not be counted, so every count shows as pending.", detail: model.scanFailure, actionTitle: "Try again", action: model.retry)
            }
            ForEach(data.problems, id: \.self) { problem in
                Banner(.warn, message: problem)
            }
        }
        .padding(.bottom, data.problems.isEmpty && model.scanFailure == nil ? 0 : 10)
    }

    /// In the app the header pins to the top of the scroll view; a screenshot has no scrolling, so it is a plain stack.
    @ViewBuilder
    private var tableLayout: some View {
        if isShotRendering {
            VStack(spacing: 0) { head; bodyRows }
        } else {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section { bodyRows } header: { head }
            }
        }
    }

    private var head: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Metrics.groupRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: Metrics.groupRadius, style: .continuous)
        return HeadRow("Name") {
            CLIColumnHead(.claude)
            CLIColumnHead(.codex)
            Color.clear.frame(width: loadoutActionsWidth, height: 1)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .background(Palette.background)
    }

    private var bodyRows: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: Metrics.groupRadius, bottomTrailingRadius: Metrics.groupRadius, topTrailingRadius: 0, style: .continuous)
        let kinds = LoadoutKind.allCases.filter { model.shotKinds?.contains($0) ?? true }
        return VStack(spacing: 0) {
            if view.shown.isEmpty {
                EmptyRow(view.all.isEmpty ? "Nothing installed at this scope." : "Nothing matches this filter.")
            }
            ForEach(kinds, id: \.self) { kind in
                let rows = LoadoutRows.section(view.shown, kind)
                if !rows.isEmpty {
                    Hairline()
                    SectionRow(kind.sectionTitle, count: rows.count)
                    ForEach(rows) { row in
                        Hairline()
                        LoadoutRowView(model: model, row: row, max: view.max[kind] ?? 1, events: data.events, selected: model.selectedKey == row.key)
                            .id(row.key)
                    }
                }
            }
        }
        .background(Palette.surface)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        // One point up, so its top edge lies on the header's bottom edge instead of doubling it.
        .padding(.top, -1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Skills, agents and hooks")
    }

    /// After the layout pass that follows the scope and filter reset of a jump.
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let key = model.selectedKey else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation { proxy.scrollTo(key, anchor: .center) }
        }
    }
}
