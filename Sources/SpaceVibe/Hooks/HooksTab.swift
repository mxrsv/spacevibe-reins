import SwiftUI

/// The key hints and the data source the status bar shows on the Hooks tab (V5-R36, V5-R66). Only keys `HooksCanvas.keys` wires.
enum HooksStatusBar {
    static let hints: [KeyHint] = [
        KeyHint(keys: "J K", label: "move"), KeyHint(keys: "\u{21B5}", label: "detail"), KeyHint(keys: "A", label: "copy to other CLI"),
        KeyHint(keys: "R", label: "remove"), KeyHint(keys: "/", label: "filter"), KeyHint(keys: "1 2 3 4", label: "category"),
    ]

    static let source = "Read from hook config. \(SpaceVibeMark.productName) never runs a hook"
}

/// The one `Filter` button at the right of the tab head (V5-R61), with its two-level menu.
struct HooksHeadActions: View {
    @Bindable var model: HooksModel

    var body: some View {
        ToolbarMenuButton("Filter", glyph: .filter, isOpen: $model.isFilterOpen, id: "hooks.filter") { close in
            FilterMenu(fields: filterFields, onToggle: { field, value in
                if let field = HooksFilterField(rawValue: field) { model.toggleFilter(field, value) }
            }, onClose: close)
        }
    }

    private var filterFields: [FilterMenuField] {
        HooksFilterField.allCases.map { field in
            let values = Self.values(field, events: model.eventValues).map { value in
                MenuEntry(id: value.id, title: value.title, kind: .check(isOn: model.query.filter.isPicked(field, value.id)))
            }
            return FilterMenuField(id: field.rawValue, title: field.title, lead: .glyph(Self.glyph(field)), values: values)
        }
    }

    static func values(_ field: HooksFilterField, events: [FilterValue]) -> [FilterValue] { field == .event ? events : field.values }

    private static func glyph(_ field: HooksFilterField) -> ContentGlyph {
        switch field {
        case .cli: .stack
        case .status: .check
        case .event: .pulse
        }
    }
}

/// The chips of the applied filters under the tab head, with `Clear` (V5-R28). Shown only while a filter is on.
struct HooksChipRow: View {
    let model: HooksModel

    var body: some View {
        FilterChipRow(onClear: model.clearFilters) {
            ForEach(chips, id: \.id) { chip in
                FilterFieldChip(field: chip.field.chipTitle, value: chip.value.chip) { model.toggleFilter(chip.field, chip.value.id) }
            }
        }
    }

    private var chips: [(id: String, field: HooksFilterField, value: FilterValue)] {
        let events = model.eventValues
        return HooksFilterField.allCases.flatMap { field in
            HooksHeadActions.values(field, events: events).filter { model.query.filter.isPicked(field, $0.id) }
                .map { (id: "\(field.rawValue):\($0.id)", field: field, value: $0) }
        }
    }
}

/// The Hooks canvas (V5-R52, V5-R65): `Answer`, `Missing in Codex` and `Can't copy to Codex` on the left (a card with no row is
/// dropped), the `Hooks` spine with a band per event on the right, and the page's plain keys (V5-R36), which are off while the
/// palette or a menu holds the keyboard. Every sentence and fact is `HooksAnswer`, `HooksQuery` and `HooksWording`'s.
struct HooksCanvas: View {
    @Bindable var model: HooksModel

    @Environment(ShellModel.self) private var shell
    @Environment(\.openStateStore) private var store

    var body: some View {
        let layout = model.layout
        let visible = shownRows(layout)
        let current = model.current(in: visible)
        ZStack(alignment: .topLeading) {
            if !shell.isPaletteOpen && !model.isMenuOpen { keys(visible: visible, current: current) }
            content(layout: layout, current: current)
        }
        .onChange(of: visible.map(\.key), initial: true) { _, keys in model.listedKeys = keys }
    }

    @ViewBuilder
    private func content(layout: HooksQuery.Layout, current: LoadoutRow?) -> some View {
        if !model.isLoaded {
            SplitCanvas {
                AnswerCard(sentence: nil, isOpen: open("answer"))
            } spine: {
                Tile("Hooks", layout: .bare, maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, isOpen: open("spine")) { LoadingSkeleton() }
            }
        } else if model.rows.isEmpty {
            SplitCanvas {
                AnswerCard(sentence: model.answer.sentence, isOpen: open("answer"))
            } spine: {
                Tile("Hooks", layout: .bare, maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, isOpen: open("none")) {
                    // The core lists `command` hooks only: when it names others, "none" would be false.
                    QuietEmptyState("No hooks", message: model.notShown.first ?? "Neither CLI has a hook configured.", placement: .card)
                }
            }
        } else {
            let missing = model.missing
            let cantCopy = model.cantCopy
            SplitCanvas {
                answerCard(model.answer)
                if !missing.isEmpty { missingCard(missing) }
                if !cantCopy.isEmpty { cantCopyCard(cantCopy) }
            } spine: {
                spineCard(layout, current: current)
            }
        }
    }

    private func open(_ id: String) -> Binding<Bool> {
        store.binding(page: HooksModel.page, id: id, byDefault: true)
    }

    // MARK: Answer

    @ViewBuilder
    private func answerCard(_ answer: HooksAnswer) -> some View {
        if answer.dead.isEmpty && answer.missing.isEmpty {
            AnswerCard(sentence: answer.sentence, isOpen: open("answer"))
        } else {
            AnswerCard(sentence: answer.sentence, moreMarked: answer.more, isOpen: open("answer")) {
                ListRows {
                    ForEach(answer.dead) { row in
                        ListRow(row.hookTitle, onActivate: { model.reveal(row.key, store: store) },
                                accessibilityName: "\(row.hookTitle), \(row.hookEvent), script gone") {
                            MetaCell(text: "\(row.hookEvent) \u{00B7} script gone")
                            if row.plugin == nil {
                                Button { model.remove(row) } label: { ActionLabel("Remove", glyph: .trash) }
                                    .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
                            }
                        }
                    }
                    if !answer.missing.isEmpty {
                        ListRow("Claude Code runs \(answer.missing.count == 1 ? "it" : "them"), Codex doesn't") {
                            Button { model.copyMissing(answer.missing) } label: { ActionLabel("Copy \(answer.missing.count) to Codex") }
                                .buttonStyle(ActionButtonStyle(size: .compact))
                        }
                    }
                }
                .padding(.horizontal, -Metrics.Hooks.fixesBleed)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: The small cards

    private func missingCard(_ missing: HooksMissing) -> some View {
        Tile("Missing in Codex", count: "\(missing.rows.count) \(missing.rows.count == 1 ? "hook" : "hooks")",
             maxHeight: Metrics.Tile.hooksSmallMaxHeight, isOpen: open("missing")) {
            ListRows {
                ForEach(missing.rows) { row in
                    ListRow(row.hookTitle, onActivate: { model.reveal(row.key, store: store) },
                            accessibilityName: "\(row.hookTitle), \(HooksWording.eventLine(row)), missing in Codex") {
                        MetaCell(text: HooksWording.eventLine(row))
                        ChipButton("Codex", glyph: .plus, accessibilityLabel: "Copy \(row.hookTitle) to Codex") { model.copy(row, to: .codex) }
                    }
                }
            }
        }
    }

    private func cantCopyCard(_ cantCopy: HooksCantCopy) -> some View {
        Tile("Can't copy to Codex", count: "\(cantCopy.entries.count) \(cantCopy.entries.count == 1 ? "hook" : "hooks")",
             maxHeight: Metrics.Tile.hooksSmallMaxHeight, isOpen: open("cantcopy")) {
            ListRows {
                ForEach(cantCopy.entries) { entry in
                    ListRow(entry.row.hookTitle, onActivate: { model.reveal(entry.row.key, store: store) },
                            accessibilityName: "\(entry.row.hookTitle), \(HooksWording.short(entry.block))") {
                        MetaCell(text: HooksWording.short(entry.block))
                    }
                }
            }
        } actions: {
            WhyButton(model: model, entries: cantCopy.entries)
        }
    }

    // MARK: The spine

    private func spineCard(_ layout: HooksQuery.Layout, current: LoadoutRow?) -> some View {
        Tile("Hooks", maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, scrollTarget: current?.key, isOpen: open("spine")) {
            spineBody(layout, current: current)
        }
    }

    @ViewBuilder
    private func spineBody(_ layout: HooksQuery.Layout, current: LoadoutRow?) -> some View {
        if layout.bands.isEmpty {
            QuietEmptyState("Nothing matches", message: "No hook fits these filters.", placement: .card) {
                Button { model.clearFilters() } label: { ActionLabel("Clear filters") }
                    .buttonStyle(ActionButtonStyle(size: .compact))
            }
        } else {
            let detected = model.detected
            BandStack(closedRuns: .grid) {
                ForEach(Array(layout.bands.enumerated()), id: \.element.id) { offset, band in
                    Band(band.event, count: band.rows.count,
                         state: band.holdsProblem ? StateMark(.danger, label: "A hook in this event can't run") : nil,
                         isOpen: store.binding(page: HooksModel.page, id: band.id, byDefault: opensByDefault(layout, offset))) {
                        ListRows { ForEach(band.rows) { row in listRow(row, current: current, detected: detected) } }
                    } lead: {
                        if let cli = band.lead { CLIMark(cli, size: .control) }
                    }
                }
            }
            let notShown = model.notShown
            if !notShown.isEmpty {
                Text(notShown.joined(separator: " "))
                    .spaceVibeText(.metaLine, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.metaLine)
                    .padding(.horizontal, Metrics.ListRow.leading)
                    .padding(.top, Metrics.Hooks.noteTop)
            }
        }
    }

    /// V5-R55: a band holding a hook that cannot run opens; when nothing needs the user, the first opens; a Filter opens every band
    /// it leaves rows in (the mock), so a match is never hidden.
    private func opensByDefault(_ layout: HooksQuery.Layout, _ offset: Int) -> Bool {
        model.query.filter.isOn || Self.opensByDefault(layout, offset)
    }

    static func opensByDefault(_ layout: HooksQuery.Layout, _ offset: Int) -> Bool {
        OpenStateStore.defaultOpen(holdsProblem: layout.bands[offset].holdsProblem, isFirst: offset == 0,
                                   pageNeedsUser: layout.bands.contains { $0.holdsProblem })
    }

    /// The rows the user can see, in order: the rows of every open band.
    private func shownRows(_ layout: HooksQuery.Layout) -> [LoadoutRow] { Self.visibleRows(layout, store: store, filterIsOn: model.query.filter.isOn) }

    static func visibleRows(_ layout: HooksQuery.Layout, store: OpenStateStore, filterIsOn: Bool = false) -> [LoadoutRow] {
        layout.bands.enumerated().flatMap { offset, band in
            store.isOpen(page: HooksModel.page, id: band.id, byDefault: filterIsOn || opensByDefault(layout, offset)) ? band.rows : []
        }
    }

    // MARK: Rows

    private func listRow(_ row: LoadoutRow, current: LoadoutRow?, detected: [CoreCLI]) -> some View {
        ListRow(row.hookTitle, lead: CategoryGlyph.hook, isCurrent: row.key == current?.key, onActivate: { model.open(row.key) },
                accessibilityName: HooksWording.spoken(row, home: model.home)) {
            MetaCell(text: row.hookMatcher ?? "", width: Metrics.Hooks.matcherWidth)
            LogoStrip {
                ForEach(detected, id: \.self) { cli in
                    if model.showsToggle(row, cli: cli) {
                        LogoToggle(cli: CoreLimitsCLI(cli), isLit: row.members[cli] != nil, mode: model.mode(row, cli: cli),
                                   justChanged: model.changed.contains("\(row.key):\(cli.rawValue)")) { model.toggle(row, cli: cli) }
                    } else {
                        // This CLI cannot take the hook: no toggle at all; the detail says why.
                        Color.clear.frame(width: Metrics.LogoToggle.box, height: Metrics.LogoToggle.box).accessibilityHidden(true)
                    }
                }
            }
            warningSlot(row)
        }
        .id(row.key)
        .anchoredOverlay(isPresented: model.detailKey == row.key, id: "\(HooksModel.page):detail", placement: .popover,
                         onOutsideTap: { model.detailKey = nil }) {
            detail(row)
        }
    }

    @ViewBuilder
    private func warningSlot(_ row: LoadoutRow) -> some View {
        if let slot = HooksWording.slot(for: row, home: model.home) {
            WarningSlot(mark: slot.mark, detail: slot.sentence, id: Self.slotID(row)) {
                PopoverSentence(slot.sentence)
                if slot.offersRemove {
                    PopoverActions {
                        Button { model.remove(row) } label: { ActionLabel("Remove", glyph: .trash) }
                            .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
                    }
                }
            }
        } else {
            WarningSlot()
        }
    }

    static func slotID(_ row: LoadoutRow) -> String { "\(HooksModel.page):warn:\(row.key)" }

    // MARK: The row detail (V5-R57, V5-R66)

    private func detail(_ row: LoadoutRow) -> some View {
        let context = model.context
        let target = row.presentCLIs.count == 1 ? row.presentCLIs.first?.other : nil
        let copyTarget = target.flatMap { context.block(row, to: $0) == nil ? $0 : nil }
        return PopoverSurface(onExit: { model.detailKey = nil }) {
            PopoverHead(name: row.hookTitle, sub: HooksWording.eventLine(row)) {
                SpaceVibeIcon(source: CategoryGlyph.hook, size: .row, ink: TextTone.tertiary.color)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(HooksWording.lines(for: row, context: context, home: model.home), id: \.self) { PopoverSentence($0) }
            }
            if copyTarget != nil && row.hookMatcher != nil {
                Text(HooksWording.matcherNote).spaceVibeText(.meta, tone: .tertiary).fixedSize(horizontal: false, vertical: true).lineBox(.meta)
            }
            if copyTarget != nil || row.plugin == nil { detailActions(row, copyTo: copyTarget) }
        }
    }

    /// The actions side by side; one under the other when `Copy to Claude Code` and `Remove` with their key caps do not fit the
    /// popover's 272.
    private func detailActions(_ row: LoadoutRow, copyTo: CoreCLI?) -> some View {
        let buttons = Group {
            if let copyTo {
                Button { model.copy(row, to: copyTo) } label: { ActionLabel("Copy to \(copyTo.label)", key: "A") }
            }
            if row.plugin == nil {
                Button { model.remove(row) } label: { ActionLabel("Remove", glyph: .trash, key: "R") }
                    .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
            }
        }
        return ViewThatFits(in: .horizontal) {
            PopoverActions { buttons.fixedSize() }
            VStack(alignment: .leading, spacing: Metrics.Popover.actionSpacing) { buttons }
                .buttonStyle(ActionButtonStyle(size: .compact))
        }
    }

    // MARK: Keys

    /// `j`/`k` and the arrows move, Return opens the detail, `a` copies to the other CLI, `r` and Delete remove, `/` opens Filter,
    /// Esc closes the detail (V5-R36). A key acts on the current row.
    private func keys(visible: [LoadoutRow], current: LoadoutRow?) -> some View {
        Group {
            HiddenKey(KeyboardShortcut("j", modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut(.downArrow, modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut("k", modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.upArrow, modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.return, modifiers: [])) { model.toggleDetail(of: current) }
            HiddenKey(KeyboardShortcut("a", modifiers: [])) { model.copyToOtherCLI(current) }
            HiddenKey(KeyboardShortcut("r", modifiers: [])) { if let current { model.remove(current) } }
            HiddenKey(KeyboardShortcut(.delete, modifiers: [])) { if let current { model.remove(current) } }
            HiddenKey(KeyboardShortcut("/", modifiers: [])) { model.isFilterOpen = true }
            if model.detailKey != nil { HiddenKey(KeyboardShortcut(.escape, modifiers: [])) { model.detailKey = nil } }
        }
    }
}

/// `Why` in the header of `Can't copy to Codex` (V5-R65): a 28-high button that opens the popover of the reasons under itself.
private struct WhyButton: View {
    @Bindable var model: HooksModel
    let entries: [HooksCantCopy.Entry]

    @FocusState private var focused: Bool

    var body: some View {
        Button { model.isWhyOpen.toggle() } label: { ActionLabel("Why") }
            .buttonStyle(ActionButtonStyle(size: .compact))
            .focused($focused)
            .accessibilityLabel("Why these hooks can't go to Codex")
            .anchoredOverlay(isPresented: model.isWhyOpen, id: "hooks.why", placement: .popover, onOutsideTap: { model.isWhyOpen = false }) {
                PopoverSurface(onExit: {
                    model.isWhyOpen = false
                    focused = true
                }) {
                    PopoverHead(name: "Why these stay in Claude Code") { EmptyView() }
                    VStack(alignment: .leading, spacing: Metrics.Popover.actionSpacing) {
                        ForEach(HooksWording.why(entries), id: \.self) { PopoverSentence($0) }
                    }
                }
            }
    }
}
