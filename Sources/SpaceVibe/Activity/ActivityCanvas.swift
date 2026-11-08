import SwiftUI

/// The v5 Activity page (V5-R69 to V5-R72; the `b-activity` mock): the tab head with Running, Failed and Files and one `Filter`,
/// the chip row while a filter is on, and the selected tab's split canvas. Every sentence and figure is `ActivityAnswers`',
/// every list `ActivityQuery`'s; the cards are `ActivityCards`'. The page's plain keys (V5-R36) are off while the palette, the
/// Filter menu or the Stop confirmation holds the keyboard.
struct ActivityCanvas: View {
    static let page = "activity"

    @Bindable var model: ActivityModel

    @Environment(ShellModel.self) private var shell
    @Environment(\.openStateStore) private var store

    var body: some View {
        let isActive = shell.activeID == ActivityTab.tabID
        // The clock the ages read: the page redraws once a minute, as Limits does.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let query = model.query(at: context.date)
            let visible = Self.visibleIDs(query, pane: model.pane, store: store)
            ZStack(alignment: .topLeading) {
                if !shell.isPaletteOpen && !model.isMenuOpen { keys(query, visible: visible) }
                VStack(spacing: 0) {
                    TabHead {
                        ForEach(ActivityPane.allCases) { pane in
                            TabChip(title: pane.title, glyph: pane.glyph, count: query.isLoading ? nil : query.count(pane), tone: .accent,
                                    isActive: model.pane == pane) { model.select(pane) }
                        }
                    } actions: {
                        if model.pane.hasFilter { ActivityHeadActions(model: model) }
                    }
                    // The chips stay on every tab, Files included, so the filtered counts of the others are explained (V5-R69).
                    if model.filter.isOn { ActivityChipRow(model: model) }
                    canvas(query, visible: visible, now: context.date)
                }
            }
        }
        // Reads while this tab shows, and once at launch for the sidebar badge; SwiftUI cancels the task on a tab switch.
        .task(id: isActive) { await model.run(active: isActive) }
    }

    @ViewBuilder
    private func canvas(_ query: ActivityQuery, visible: [String], now: Date) -> some View {
        if query.isLoading, let failure = model.failure {
            QuietEmptyState("Could not read the session logs", message: failure, placement: .list) {
                Button(action: model.retry) { ActionLabel("Try again") }.buttonStyle(ActionButtonStyle())
            }
            Spacer(minLength: 0)
        } else {
            ActivityCards(pane: model.pane, model: model, query: query, current: model.current(in: visible), now: now)
        }
    }

    // MARK: The rows the keys move over

    /// The rows the user can see, in order: those of every open band (V5-R55's default: a band holding a problem opens; when none
    /// does, the first opens).
    static func visibleIDs(_ query: ActivityQuery, pane: ActivityPane, store: OpenStateStore) -> [String] {
        func open(_ id: String, problem: Bool, offset: Int, needs: Bool) -> Bool {
            store.isOpen(page: page, id: id, byDefault: OpenStateStore.defaultOpen(holdsProblem: problem, isFirst: offset == 0, pageNeedsUser: needs))
        }
        switch pane {
        case .running:
            let needs = query.sessionBands.contains(where: \.holdsProblem)
            return query.sessionBands.enumerated().flatMap { offset, band in
                open("run:\(band.id)", problem: band.holdsProblem, offset: offset, needs: needs) ? band.items.map(\.id) : []
            }
        case .failed:
            let needs = query.failureBands.contains(where: \.holdsProblem)
            return query.failureBands.enumerated().flatMap { offset, band in
                open("fail:\(band.id)", problem: band.holdsProblem, offset: offset, needs: needs) ? band.items.map(\.id) : []
            }
        case .files:
            return query.fileBands.enumerated().flatMap { offset, band in
                open("files:\(band.id)", problem: false, offset: offset, needs: false) ? band.items.map(\.id) : []
            }
        }
    }

    // MARK: Keys

    /// `j`/`k` and the arrows move, Return opens the detail, `s` stops, `c` copies, `o` shows the file, `/` opens Filter, `1` to `3`
    /// switch the tabs, Esc closes the detail (V5-R36). A key acts on the current row of the tab it belongs to.
    private func keys(_ query: ActivityQuery, visible: [String]) -> some View {
        let current = model.current(in: visible)
        return Group {
            HiddenKey(KeyboardShortcut("j", modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut(.downArrow, modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut("k", modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.upArrow, modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.return, modifiers: [])) { model.toggleDetail(of: current) }
            HiddenKey(KeyboardShortcut("s", modifiers: [])) {
                if model.pane == .running, let item = query.sessions.first(where: { $0.id == current }), item.canStop { model.requestStop(item.session) }
            }
            HiddenKey(KeyboardShortcut("c", modifiers: [])) {
                if model.pane == .failed, let item = query.failures.first(where: { $0.id == current }) { model.copy(item) }
            }
            HiddenKey(KeyboardShortcut("o", modifiers: [])) {
                if model.pane == .files, let item = query.files.first(where: { $0.id == current }) { model.reveal(item) }
            }
            HiddenKey(KeyboardShortcut("/", modifiers: [])) { if model.pane.hasFilter { model.isFilterOpen = true } }
            ForEach(Array(ActivityPane.allCases.enumerated()), id: \.element) { index, _ in
                HiddenKey(KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])) { model.select(index: index) }
            }
            if model.detailID != nil { HiddenKey(KeyboardShortcut(.escape, modifiers: [])) { model.detailID = nil } }
        }
    }
}

/// The one `Filter` button at the right of the tab head (V5-R61): one menu level, because the page has one field.
struct ActivityHeadActions: View {
    @Bindable var model: ActivityModel

    var body: some View {
        ToolbarMenuButton("Filter", glyph: .filter, isOpen: $model.isFilterOpen, id: "activity.filter") { close in
            FilterMenu(fields: [field], onToggle: { _, value in model.toggleFilter(value) }, onClose: close)
        }
    }

    private var field: FilterMenuField {
        let values = ActivityFilterField.cli.values.map { value in
            MenuEntry(id: value.id, title: value.title, kind: .check(isOn: model.filter.isPicked(.cli, value.id)))
        }
        return FilterMenuField(id: ActivityFilterField.cli.rawValue, title: ActivityFilterField.cli.title, lead: .glyph(.terminal), values: values)
    }
}

/// The chips of the applied filters under the tab head, with `Clear` (V5-R28).
struct ActivityChipRow: View {
    let model: ActivityModel

    var body: some View {
        FilterChipRow(onClear: model.clearFilters) {
            ForEach(model.filter.chips, id: \.value.id) { chip in
                FilterFieldChip(field: chip.field.chipTitle, value: chip.value.chip) { model.toggleFilter(chip.value.id) }
            }
        }
    }
}
