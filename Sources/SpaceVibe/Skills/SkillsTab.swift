import SwiftUI

/// The key hints and the data source the status bar shows on the Skills tab (V5-R35, V5-R36). Only keys `SkillsCanvas.keys` wires.
enum SkillsStatusBar {
    static let hints: [KeyHint] = [
        KeyHint(keys: "J K", label: "move"), KeyHint(keys: "X", label: "select"), KeyHint(keys: "\u{21B5}", label: "focus actions"),
        KeyHint(keys: "A", label: "add to other CLI"), KeyHint(keys: "R", label: "remove"), KeyHint(keys: "/", label: "filter"),
        KeyHint(keys: "1 2 3 4", label: "category"),
    ]

    /// Sessions, not runs (S2): what the counts rest on.
    static let source = "Sessions counted from local logs"
}

/// The scope control, `Filter` and `View` at the right of the tab head (V5-R19), each with its menu.
struct SkillsHeadActions: View {
    @Bindable var model: SkillsModel

    var body: some View {
        ToolbarMenuButton(model.scopeLabel, trailingCaret: true, isOpen: $model.isScopeOpen, id: "skills.scope") { close in
            RadioMenu(entries: scopeEntries, onPick: { value in
                model.setScope(value)
                close(true)
            }, onClose: close)
        }
        .accessibilityLabel("Scope")
        ToolbarMenuButton("Filter", glyph: .filter, isOpen: $model.isFilterOpen, id: "skills.filter") { close in
            FilterMenu(fields: filterFields, onToggle: { field, value in
                if let field = SkillsFilterField(rawValue: field) { model.toggleFilter(field, value) }
            }, onClose: close)
        }
        ToolbarMenuButton("View", glyph: .sliders, isOpen: $model.isViewOpen, id: "skills.view") { close in
            RadioMenu(entries: viewEntries, onPick: pickView, onClose: close)
        }
    }

    // MARK: Menus

    private var scopeEntries: [MenuEntry] {
        (model.loadout.data?.scopes ?? []).map { MenuEntry(id: $0.value, title: $0.label, kind: .radio(isOn: $0.value == model.loadout.scope)) }
    }

    private var filterFields: [FilterMenuField] {
        SkillsFilterField.allCases.map { field in
            var values: [MenuEntry] = []
            for value in field.values {
                if field == .rank, let group = SkillsFilterField.rankGroups.first(where: { $0.firstValue == value.id }) {
                    values.append(MenuEntry(id: "heading.\(group.heading)", title: group.heading, kind: .heading))
                }
                values.append(MenuEntry(id: value.id, title: value.title, kind: .check(isOn: model.query.filter.isPicked(field, value.id)),
                                        lead: field == .status ? .verdict(value.id == "heavy" ? .heavy : .never) : nil))
            }
            return FilterMenuField(id: field.rawValue, title: field.title, lead: field == .status ? .verdict(.used) : .glyph(Self.glyph(field)), values: values)
        }
    }

    private static func glyph(_ field: SkillsFilterField) -> ContentGlyph {
        switch field {
        case .status: .check
        case .cli: .stack
        case .owner: .lock
        case .rank: .rank
        case .lastRan: .clock
        }
    }

    private var viewEntries: [MenuEntry] {
        [MenuEntry(id: "heading.group", title: "Group by", kind: .heading)]
            + SkillsGroup.allCases.map { MenuEntry(id: "group.\($0.rawValue)", title: $0.title, kind: .radio(isOn: model.query.group == $0)) }
            + [MenuEntry(id: "heading.order", title: "Order by", kind: .heading)]
            + SkillsOrder.allCases.map { MenuEntry(id: "order.\($0.rawValue)", title: $0.title, kind: .radio(isOn: model.query.order == $0)) }
    }

    private func pickView(_ id: String) {
        if id.hasPrefix("group."), let group = SkillsGroup(rawValue: String(id.dropFirst("group.".count))) { model.query.group = group }
        if id.hasPrefix("order."), let order = SkillsOrder(rawValue: String(id.dropFirst("order.".count))) { model.query.order = order }
    }
}

/// The chips of the applied filters under the tab head, with `Clear` (V5-R28). Shown only while a filter is on.
struct SkillsChipRow: View {
    let model: SkillsModel

    var body: some View {
        FilterChipRow(onClear: model.clearFilters) {
            ForEach(model.query.filter.chips, id: \.value.id) { chip in
                FilterFieldChip(field: chip.field.chipTitle, value: chip.value.chip) { model.toggleFilter(chip.field, chip.value.id) }
            }
        }
    }
}

/// The Skills canvas: the list with its order line, the permanent pane, the bottom bar while rows are picked, and the page's
/// plain keys (V5-R36), which are off while the palette or a menu holds the keyboard.
struct SkillsCanvas: View {
    @Bindable var model: SkillsModel

    @Environment(ShellModel.self) private var shell
    @Environment(\.openStateStore) private var store

    var body: some View {
        // The clock the "Last ran" words read: the page redraws once a minute, as Limits does.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let layout = model.layout
            let visible = SkillsList.visibleRows(layout, store: store)
            let current = model.current(in: visible)
            let rows = model.rows
            let detected = model.detected
            let picked = model.pickedRows
            ZStack(alignment: .topLeading) {
                if keysAreOn { keys(visible: visible, current: current, picked: picked) }
                ListPaneLayout(orderLine: model.query.orderLine, scrollTarget: current?.key, barShown: !picked.isEmpty) {
                    SkillsList(model: model, layout: layout, current: current, detected: detected)
                } pane: {
                    SkillsPane(model: model, row: current, detected: detected,
                               status: current.map { model.status(of: $0, among: rows) } ?? .loading, scopeLabel: model.scopeLabel,
                               now: context.date)
                } bar: {
                    bar(picked, detected: detected)
                }
            }
            .onChange(of: visible.map(\.key), initial: true) { _, keys in model.listedKeys = keys }
        }
    }

    // MARK: Bottom bar

    private func bar(_ picked: [LoadoutRow], detected: [CoreCLI]) -> some View {
        BulkBar("\(picked.count) selected", stripLabel: "Add to") {
            LogoStrip {
                ForEach(detected, id: \.self) { cli in
                    LogoToggle(cli: CoreLimitsCLI(cli), isLit: model.isLit(picked, cli: cli), mode: model.bulkMode(picked, cli: cli),
                               spokenValue: SkillsWording.bulkSpoken(picked, cli: cli, isLit: model.isLit(picked, cli: cli),
                                                                      mode: model.bulkMode(picked, cli: cli))) {
                        model.toggleBulk(picked, cli: cli)
                    }
                }
            }
        } actions: {
            Button { model.remove(picked) } label: { ActionLabel("Remove", key: "R") }
                .buttonStyle(ActionButtonStyle(kind: .danger, size: .bar))
            Button { model.clearPicks() } label: { ActionLabel("Clear", key: "Esc") }
        }
    }

    // MARK: Keys

    private var keysAreOn: Bool {
        !shell.isPaletteOpen && !model.isMenuOpen
    }

    /// `j`/`k` and the arrows move, `x` picks, Return focuses the pane's actions, `a` adds to the other CLI, `r` and Delete
    /// remove, `o` opens the file, `/` opens Filter, Esc clears the picks. A key acts on the picked rows, else on the current one.
    private func keys(visible: [LoadoutRow], current: LoadoutRow?, picked: [LoadoutRow]) -> some View {
        let targets = picked.isEmpty ? (current.map { [$0] } ?? []) : picked
        return Group {
            HiddenKey(KeyboardShortcut("j", modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut(.downArrow, modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut("k", modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.upArrow, modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut("x", modifiers: [])) { if let current { model.togglePick(current.key) } }
            HiddenKey(KeyboardShortcut(.return, modifiers: [])) { model.focusPane() }
            HiddenKey(KeyboardShortcut("a", modifiers: [])) { model.addToOtherCLI(targets) }
            HiddenKey(KeyboardShortcut("r", modifiers: [])) { model.remove(targets) }
            HiddenKey(KeyboardShortcut(.delete, modifiers: [])) { model.remove(targets) }
            HiddenKey(KeyboardShortcut("o", modifiers: [])) { if let target = targets.first { model.openFile(of: target) } }
            HiddenKey(KeyboardShortcut("/", modifiers: [])) { model.isFilterOpen = true }
            if !picked.isEmpty { HiddenKey(KeyboardShortcut(.escape, modifiers: [])) { model.clearPicks() } }
        }
    }
}
