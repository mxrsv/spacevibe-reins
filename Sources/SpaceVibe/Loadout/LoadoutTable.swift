import SwiftUI

/// The scrolling part of the screen: banners, one card per kind (Skills, Agents, Hooks) whose header stays put while its
/// rows scroll, and the legend with what the counts rest on.
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
                ScrollView { page }
                    .onChange(of: model.jumpToken) { _, _ in scrollToSelection(proxy) }
            }
        }
    }

    private var kinds: [LoadoutKind] {
        LoadoutKind.allCases.filter { model.shotKinds?.contains($0) ?? true }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners
            cards
            UsageLegend(note: model.usageNote).padding(.top, Rhythm.caption)
        }
        .pageContent()
    }

    @ViewBuilder
    private var banners: some View {
        let problems = (model.scanFailure.map { [$0] } ?? []).count + data.problems.count
        if problems > 0 {
            VStack(spacing: Space.s12) {
                if model.scanFailure != nil {
                    Banner(.warn, message: "Usage could not be counted, so every count shows as pending.", detail: model.scanFailure, actionTitle: "Try again", action: model.retry)
                }
                ForEach(data.problems, id: \.self) { problem in
                    Banner(.warn, message: problem)
                }
            }
            .padding(.bottom, Rhythm.cards)
        }
    }

    /// In the app each card's header pins to the top of the scroll view; a screenshot has no scrolling, so it is a stack.
    @ViewBuilder
    private var cards: some View {
        let shown = kinds.filter { !LoadoutRows.section(view.shown, $0).isEmpty }
        if shown.isEmpty {
            GroupedList {
                EmptyRow(view.all.isEmpty ? "Nothing installed at this scope." : "Nothing matches this filter.")
            }
        } else if isShotRendering {
            VStack(spacing: Rhythm.cards) {
                ForEach(shown, id: \.self) { kind in
                    VStack(spacing: 0) { header(kind); rows(kind) }
                }
            }
        } else {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(shown, id: \.self) { kind in
                    Section {
                        rows(kind).padding(.bottom, kind == shown.last ? 0 : Rhythm.cards)
                    } header: {
                        header(kind)
                    }
                }
            }
        }
    }

    private func header(_ kind: LoadoutKind) -> some View {
        CardHeader(kind.sectionTitle, count: LoadoutRows.section(view.shown, kind).count, columns: {
            CLIColumnHead(.claude)
            CLIColumnHead(.codex)
            ColumnSpacer(width: Metrics.loadoutActionsWidth)
        })
        .pinnedCardTop()
    }

    private func rows(_ kind: LoadoutKind) -> some View {
        GroupedList(edges: .belowPinnedHeader) {
            ForEach(LoadoutRows.section(view.shown, kind)) { row in
                LoadoutRowView(model: model, row: row, max: view.max[kind] ?? 1, events: data.events, selected: model.selectedKey == row.key)
                    .id(row.key)
            }
        }
        .accessibilityLabel(kind.sectionTitle)
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
