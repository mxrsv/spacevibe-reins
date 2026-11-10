import SwiftUI

/// The key hints and the data source the status bar shows on the Subagents tab (V5-R36, V5-R64). Only keys `SubagentsCanvas.keys`
/// wires.
enum SubagentsStatusBar {
    static let hints: [KeyHint] = [
        KeyHint(keys: "J K", label: "move"), KeyHint(keys: "\u{21B5}", label: "detail"), KeyHint(keys: "A", label: "add to other CLI"),
        KeyHint(keys: "R", label: "remove"), KeyHint(keys: "/", label: "filter"), KeyHint(keys: "1 2 3 4", label: "category"),
    ]

    /// Sessions, not runs (S2): what the counts rest on.
    static let source = SkillsStatusBar.source
}

/// The one `Filter` button at the right of the tab head (V5-R61), with its two-level menu.
struct SubagentsHeadActions: View {
    @Bindable var model: SubagentsModel

    var body: some View {
        ToolbarMenuButton("Filter", glyph: .filter, isOpen: $model.isFilterOpen, id: "subagents.filter") { close in
            FilterMenu(fields: filterFields, onToggle: { field, value in
                if let field = SubagentsFilterField(rawValue: field) { model.toggleFilter(field, value) }
            }, onClose: close)
        }
    }

    private var filterFields: [FilterMenuField] {
        SubagentsFilterField.allCases.map { field in
            let values = field.values.map { value in
                MenuEntry(id: value.id, title: value.title, kind: .check(isOn: model.query.filter.isPicked(field, value.id)),
                          lead: field == .status ? .verdict(value.id == "neverRan" ? .never : .nm) : nil)
            }
            return FilterMenuField(id: field.rawValue, title: field.title, lead: field == .status ? .verdict(.used) : .glyph(Self.glyph(field)), values: values)
        }
    }

    private static func glyph(_ field: SubagentsFilterField) -> ContentGlyph {
        switch field {
        case .status: .check
        case .cli: .stack
        case .owner: .lock
        }
    }
}

/// The chips of the applied filters under the tab head, with `Clear` (V5-R28). Shown only while a filter is on.
struct SubagentsChipRow: View {
    let model: SubagentsModel

    var body: some View {
        FilterChipRow(onClear: model.clearFilters) {
            ForEach(model.query.filter.chips, id: \.value.id) { chip in
                FilterFieldChip(field: chip.field.chipTitle, value: chip.value.chip) { model.toggleFilter(chip.field, chip.value.id) }
            }
        }
    }
}

/// The Subagents canvas (V5-R52, V5-R63): `Answer` and `In one CLI only` on the left, the `Subagents` spine on the right, and the
/// page's plain keys (V5-R36), which are off while the palette or a menu holds the keyboard. Every sentence and fact is
/// `SubagentsAnswer`, `SubagentsQuery` and `SubagentsWording`'s.
struct SubagentsCanvas: View {
    @Bindable var model: SubagentsModel

    @Environment(ShellModel.self) private var shell
    @Environment(\.openStateStore) private var store

    var body: some View {
        // The clock the detail popover's "last session" words read: the page redraws once a minute, as Limits does.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let layout = model.layout
            let visible = Self.visibleRows(layout, store: store)
            let current = model.current(in: visible)
            ZStack(alignment: .topLeading) {
                if !shell.isPaletteOpen && !model.isMenuOpen { keys(visible: visible, current: current) }
                content(layout: layout, current: current, now: context.date)
            }
        }
    }

    @ViewBuilder
    private func content(layout: SubagentsQuery.Layout, current: LoadoutRow?, now: Date) -> some View {
        if !model.isLoaded {
            SplitCanvas {
                AnswerCard(sentence: nil, isOpen: open("answer"))
                Tile("In one CLI only", layout: .bare, isOpen: open("onecli")) { LoadingSkeleton() }
            } spine: {
                Tile("Subagents", layout: .bare, maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, isOpen: open("spine")) { LoadingSkeleton() }
            }
        } else if model.rows.isEmpty {
            SpaceVibeScrollView {
                Tile("Subagents", layout: .bare, isOpen: open("none")) {
                    QuietEmptyState("No subagents yet", message: "SpaceVibe found none in your CLI folders.", placement: .card)
                }
                .padding(Rhythm.edge)
            }
        } else {
            let answer = model.answer
            let addable = model.addable
            SplitCanvas {
                answerCard(answer)
                if !addable.isEmpty { oneCLICard(addable) }
            } spine: {
                spineCard(layout, current: current, now: now)
            }
        }
    }

    private func open(_ id: String) -> Binding<Bool> {
        store.binding(page: SubagentsModel.page, id: id, byDefault: true)
    }

    // MARK: Answer

    @ViewBuilder
    private func answerCard(_ answer: SubagentsAnswer) -> some View {
        if let verdict = answer.verdict {
            AnswerCard(sentence: answer.sentence,
                       verdict: VerdictBox(glyph: .never, glyphLabel: "Never ran", title: verdict.name, text: verdict.text, small: verdict.small),
                       moreMarked: answer.more, isOpen: open("answer")) {
                Button { model.review(verdict.key, store: store) } label: { ActionLabel("Review") }
                    .buttonStyle(ActionButtonStyle())
                if verdict.offersRemove, let row = model.rows.first(where: { $0.key == verdict.key }) {
                    Button { model.remove(row) } label: { ActionLabel("Remove", glyph: .trash) }
                        .buttonStyle(ActionButtonStyle(kind: .danger))
                }
            }
        } else {
            AnswerCard(sentence: answer.sentence, isOpen: open("answer"))
        }
    }

    // MARK: In one CLI only

    private func oneCLICard(_ addable: SubagentsAddable) -> some View {
        let count = "\(addable.entries.count) \(addable.entries.count == 1 ? "subagent" : "subagents")"
        return Tile("In one CLI only", count: count, maxHeight: Metrics.Tile.subagentsSmallMaxHeight, isOpen: open("onecli")) {
            ListRows {
                ForEach(addable.entries) { entry in
                    ListRow(entry.row.name, onActivate: { model.review(entry.row.key, store: store) },
                            accessibilityName: "\(entry.row.name), only in \(entry.here.label)") {
                        CLIMark(entry.here, size: .control)
                    } trailing: {
                        ChipButton("Add to \(entry.target.label)", glyph: .plus,
                                   accessibilityLabel: "Add \(entry.row.name) to \(entry.target.label)") { model.add(entry.row, to: entry.target) }
                    }
                }
            }
            ForEach(SubagentsWording.addableNotes(addable), id: \.self) { note in
                Text(note)
                    .spaceVibeText(.metaLine, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.metaLine)
                    .padding(.horizontal, Metrics.ListRow.leading)
                    .padding(.top, Metrics.Subagents.noteTop)
            }
            if !addable.leftOut.isEmpty {
                Text("Not listed: \(addable.leftOut.joined(separator: ", ")).")
                    .spaceVibeText(.metaLine, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.metaLine)
                    .padding(.horizontal, Metrics.ListRow.leading)
                    .padding(.top, Metrics.Subagents.noteTop)
            }
        }
    }

    // MARK: The spine

    private func spineCard(_ layout: SubagentsQuery.Layout, current: LoadoutRow?, now: Date) -> some View {
        Tile("Subagents", maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, scrollTarget: current?.key, isOpen: open("spine")) {
            spineBody(layout, current: current, now: now)
        } actions: {
            GroupMenuButton(model: model)
        }
    }

    @ViewBuilder
    private func spineBody(_ layout: SubagentsQuery.Layout, current: LoadoutRow?, now: Date) -> some View {
        let detected = model.detected
        if layout.rows.isEmpty {
            QuietEmptyState("Nothing matches", message: "No subagent fits these filters.", placement: .card) {
                Button { model.clearFilters() } label: { ActionLabel("Clear filters") }
                    .buttonStyle(ActionButtonStyle(size: .compact))
            }
        } else if layout.isGrouped {
            BandStack {
                ForEach(Array(layout.groups.enumerated()), id: \.element.id) { offset, group in
                    Band(group.title, count: group.rows.count,
                         isOpen: store.binding(page: SubagentsModel.page, id: group.id, byDefault: Self.opensByDefault(layout, offset))) {
                        ListRows { ForEach(group.rows) { row in listRow(row, current: current, detected: detected, now: now) } }
                    }
                }
            }
        } else {
            ListRows { ForEach(layout.rows) { row in listRow(row, current: current, detected: detected, now: now) } }
        }
    }

    /// V5-R55: a band holding a problem opens; when nothing needs the user, the first opens; the others start closed.
    static func opensByDefault(_ layout: SubagentsQuery.Layout, _ offset: Int) -> Bool {
        OpenStateStore.defaultOpen(holdsProblem: layout.groups[offset].holdsProblem, isFirst: offset == 0,
                                   pageNeedsUser: layout.groups.contains { $0.holdsProblem })
    }

    /// The rows the user can see, in order: the rows of every open band (all of them when flat).
    static func visibleRows(_ layout: SubagentsQuery.Layout, store: OpenStateStore) -> [LoadoutRow] {
        guard layout.isGrouped else { return layout.rows }
        return layout.groups.enumerated().flatMap { offset, group in
            store.isOpen(page: SubagentsModel.page, id: group.id, byDefault: opensByDefault(layout, offset)) ? group.rows : []
        }
    }

    // MARK: Rows

    private func listRow(_ row: LoadoutRow, current: LoadoutRow?, detected: [CoreCLI], now: Date) -> some View {
        ListRow(row.name, isCurrent: row.key == current?.key, onActivate: { model.open(row.key) },
                accessibilityName: SubagentsWording.spoken(row)) {
            MetaCell(text: SubagentsWording.sessionsText(row), width: Metrics.Subagents.sessionsWidth)
            LogoStrip {
                ForEach(detected, id: \.self) { cli in
                    LogoToggle(cli: CoreLimitsCLI(cli), isLit: row.members[cli] != nil, mode: model.mode(row, cli: cli),
                               justChanged: model.changed.contains("\(row.key):\(cli.rawValue)")) { model.toggle(row, cli: cli) }
                }
            }
            warningSlot(row)
        }
        .id(row.key)
        .anchoredOverlay(isPresented: model.detailKey == row.key, id: "\(SubagentsModel.page):detail", placement: .popover,
                         onOutsideTap: { model.detailKey = nil }) {
            detail(row, now: now)
        }
    }

    @ViewBuilder
    private func warningSlot(_ row: LoadoutRow) -> some View {
        if let slot = SubagentsWording.slot(for: row) {
            WarningSlot(mark: slot.mark, detail: slot.sentence ?? slot.mark.label, id: Self.slotID(row)) {
                if let sentence = slot.sentence { PopoverSentence(sentence) }
                if let plugin = slot.plugin { PopoverNote("Owned by the \(plugin) plugin. SpaceVibe can read it but not change it.", glyph: .lock) }
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

    static func slotID(_ row: LoadoutRow) -> String { "\(SubagentsModel.page):warn:\(row.key)" }

    // MARK: The row detail (V5-R57)

    private func detail(_ row: LoadoutRow, now: Date) -> some View {
        let add = model.addable.entries.first { $0.row.key == row.key }
        return PopoverSurface(onExit: { model.detailKey = nil }) {
            PopoverHead(name: row.name, sub: SubagentsWording.presence(row)) {
                SpaceVibeIcon(source: CategoryGlyph.subagent, size: .row, ink: TextTone.tertiary.color)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SubagentsWording.detailLines(for: row, adding: add?.target, now: now), id: \.self) { PopoverSentence($0) }
            }
            if let plugin = row.plugin { PopoverNote("Owned by the \(plugin) plugin. SpaceVibe can read it but not change it.", glyph: .lock) }
            if add != nil || row.plugin == nil { detailActions(row, add: add) }
        }
    }

    /// The actions side by side; one under the other when `Add to Claude Code` and `Remove` with their key caps do not fit the
    /// popover's 272.
    private func detailActions(_ row: LoadoutRow, add: SubagentsAddable.Entry?) -> some View {
        let buttons = Group {
            if let add {
                Button { model.add(row, to: add.target) } label: { ActionLabel("Add to \(add.target.label)", key: "A") }
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

    /// `j`/`k` and the arrows move, Return opens the detail, `a` adds to the other CLI, `r` and Delete remove, `/` opens Filter,
    /// Esc closes the detail (V5-R36). A key acts on the current row.
    private func keys(visible: [LoadoutRow], current: LoadoutRow?) -> some View {
        Group {
            HiddenKey(KeyboardShortcut("j", modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut(.downArrow, modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut("k", modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.upArrow, modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.return, modifiers: [])) { model.toggleDetail(of: current) }
            HiddenKey(KeyboardShortcut("a", modifiers: [])) { model.addToOtherCLI(current) }
            HiddenKey(KeyboardShortcut("r", modifiers: [])) { if let current { model.remove(current) } }
            HiddenKey(KeyboardShortcut(.delete, modifiers: [])) { if let current { model.remove(current) } }
            HiddenKey(KeyboardShortcut("/", modifiers: [])) { model.isFilterOpen = true }
            if model.detailKey != nil { HiddenKey(KeyboardShortcut(.escape, modifiers: [])) { model.detailKey = nil } }
        }
    }
}

/// `Group: <field>` in the spine card's header (V5-R63): a 28-high button that opens the radio menu under itself.
private struct GroupMenuButton: View {
    @Bindable var model: SubagentsModel

    @FocusState private var focused: Bool

    var body: some View {
        Button { model.isGroupOpen.toggle() } label: { ActionLabel("Group: \(model.query.group.title)") }
            .buttonStyle(ActionButtonStyle(size: .compact))
            .focused($focused)
            .anchoredOverlay(isPresented: model.isGroupOpen, id: "subagents.group", placement: .menu(.trailing), onOutsideTap: { model.isGroupOpen = false }) {
                RadioMenu(entries: entries, onPick: { id in
                    if let group = SubagentsGroup(rawValue: String(id.dropFirst("group.".count))) { model.query.group = group }
                }, onClose: { refocus in
                    model.isGroupOpen = false
                    if refocus { focused = true }
                })
            }
            .accessibilityValue(model.isGroupOpen ? "Menu open" : "")
    }

    private var entries: [MenuEntry] {
        [MenuEntry(id: "heading.group", title: "Group by", kind: .heading)]
            + SubagentsGroup.allCases.map { MenuEntry(id: "group.\($0.rawValue)", title: $0.title, kind: .radio(isOn: model.query.group == $0)) }
    }
}
