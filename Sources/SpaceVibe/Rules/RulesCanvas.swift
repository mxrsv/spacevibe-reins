import SwiftUI

/// The key hints and the data source the status bar shows on the Rules tab (V5-R36, V5-R68). Only keys `RulesCanvas.keys` wires.
enum RulesStatusBar {
    static let hints: [KeyHint] = [
        KeyHint(keys: "J K", label: "move"), KeyHint(keys: "\u{21B5}", label: "detail"), KeyHint(keys: "R", label: "remove"),
        KeyHint(keys: "/", label: "filter"), KeyHint(keys: "1 2 3 4", label: "category"),
    ]

    static let source = "Read from \(RulesTabWording.settingsFile)"
}

/// The one `Filter` button at the right of the tab head (V5-R61): one field, so the menu has one level.
struct RulesHeadActions: View {
    @Bindable var model: RulesModel

    var body: some View {
        ToolbarMenuButton("Filter", glyph: .filter, isOpen: $model.isFilterOpen, id: "rules.filter") { close in
            FilterMenu(fields: [field], onToggle: { _, value in if CoreVerdict(rawValue: value) != nil { model.toggleFilter(value) } }, onClose: close)
        }
    }

    private var field: FilterMenuField {
        FilterMenuField(
            id: RulesFilterField.verdict.rawValue, title: RulesFilterField.verdict.title, lead: .glyph(.check),
            values: [MenuEntry(id: "heading", title: RulesFilterField.verdict.title, kind: .heading)]
                + RulesFilterField.verdict.values.map { MenuEntry(id: $0.id, title: $0.title, kind: .check(isOn: model.filter.isPicked(.verdict, $0.id))) }
        )
    }
}

/// The chips of the applied filters under the tab head, with `Clear` (V5-R28). Shown only while a filter is on.
struct RulesChipRow: View {
    let model: RulesModel

    var body: some View {
        FilterChipRow(onClear: model.clearFilters) {
            ForEach(model.filter.chips, id: \.value.id) { chip in
                FilterFieldChip(field: chip.field.chipTitle, value: chip.value.chip) { model.toggleFilter(chip.value.id) }
            }
        }
    }
}

/// The Rules canvas (V5-R52, V5-R67, V5-R68): `Answer` and `Redundant rules` on the left (a card with no row is dropped), the
/// `Permissions` spine with a band per tool family on the right, and the page's plain keys (V5-R36), which are off while the
/// palette or a menu holds the keyboard. Every sentence and fact is `RulesPage`'s and `RuleFamilies`'.
struct RulesCanvas: View {
    @Bindable var model: RulesModel

    @Environment(ShellModel.self) private var shell
    @Environment(\.openStateStore) private var store

    var body: some View {
        let page = model.page
        let visible = Self.visibleRules(page.layout, store: store, filterIsOn: model.filter.isOn)
        let current = model.current(in: visible)
        ZStack(alignment: .topLeading) {
            if !shell.isPaletteOpen && !model.isMenuOpen { keys(visible: visible, current: current) }
            content(page, current: current)
        }
        .task { model.showGlobal() }
    }

    @ViewBuilder
    private func content(_ page: RulesPage, current: CoreRule?) -> some View {
        switch page.state {
        case .loading:
            SplitCanvas {
                AnswerCard(sentence: nil, isOpen: open("answer"))
            } spine: {
                Tile("Permissions", layout: .bare, maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, isOpen: open("spine")) { LoadingSkeleton() }
            }
        case .unreadable(let message):
            unreadable(page, text: message)
        case .invalid:
            unreadable(page, text: RulesTabWording.hiddenUntilParses)
        case .empty:
            SplitCanvas {
                answerCard(page)
            } spine: {
                Tile("Permissions", layout: .bare, maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, isOpen: open("none")) {
                    QuietEmptyState("No rules yet", message: "\(RulesTabWording.settingsFile) holds no permission rules.", placement: .card)
                }
            }
        case .ready:
            SplitCanvas {
                answerCard(page)
                if !page.layout.redundant.isEmpty { redundantCard(page.layout.redundant) }
            } spine: {
                spineCard(page, current: current)
            }
        }
    }

    /// The file does not parse or the core cannot be asked: the danger glyph on the spine, no rules, the Answer with `Retry`.
    private func unreadable(_ page: RulesPage, text: String) -> some View {
        SplitCanvas {
            answerCard(page)
        } spine: {
            Tile("Permissions", state: StateMark(.danger, label: "Settings file unreadable"), layout: .content, maxHeight: Metrics.Tile.spineMaxHeight,
                 stretches: true, isOpen: open("spine")) {
                Text(text).spaceVibeText(.prose, tone: .secondary).fixedSize(horizontal: false, vertical: true).lineBox(.prose)
            }
        }
    }

    private func open(_ id: String) -> Binding<Bool> { store.binding(page: RulesModel.page, id: id, byDefault: true) }

    // MARK: Answer

    @ViewBuilder
    private func answerCard(_ page: RulesPage) -> some View {
        let answer = page.answer
        if let band = answer.family, let fact = band.fact {
            AnswerCard(sentence: answer.sentence, isOpen: open("answer")) {
                VStack(alignment: .leading, spacing: Metrics.Tile.contentSpacing) {
                    ListRows {
                        ListRow("Claude Code", leading: { CLIMark(CoreCLI.claude, size: .control) }, trailing: {
                            VerdictMenuButton(model: model, target: .family(band.family), heading: "\(band.family.title) in Claude Code",
                                              current: band.allStance.single, label: band.allStance.single.map(RulesWording.title) ?? "Mixed", size: .regular)
                        })
                        ListRow("Codex", leading: { CLIMark(CoreCLI.codex, size: .control) }, trailing: {
                            HStack(spacing: Metrics.Rules.headSpacing) {
                                Text(fact.text).spaceVibeText(.meta, tone: .tertiary).lineLimit(1)
                                SpaceVibeIcon(content: .lock, ink: TextTone.tertiary.color, label: "read only")
                            }
                        })
                    }
                    .padding(.horizontal, -Metrics.Rules.fixesBleed)
                    if let line = answer.alsoLine {
                        Text(line).spaceVibeText(.meta, tone: .tertiary).lineBox(.meta)
                    }
                }
            }
        } else if answer.showsRetry || answer.detail != nil {
            AnswerCard(sentence: answer.sentence, isOpen: open("answer")) {
                VStack(alignment: .leading, spacing: Metrics.Tile.contentSpacing) {
                    if let detail = answer.detail {
                        Text(detail).spaceVibeText(.prose, tone: .secondary).fixedSize(horizontal: false, vertical: true).lineBox(.prose)
                    }
                    if answer.showsRetry { Button { model.retry() } label: { ActionLabel("Retry") }.buttonStyle(ActionButtonStyle()) }
                }
            }
        } else {
            AnswerCard(sentence: answer.sentence, isOpen: open("answer"))
        }
    }

    // MARK: Redundant rules

    private func redundantCard(_ redundant: [RedundantRule]) -> some View {
        Tile("Redundant rules", count: RulesTabWording.countLabel(redundant.count), maxHeight: Metrics.Tile.rulesSmallMaxHeight, isOpen: open("redundant")) {
            ListRows {
                ForEach(redundant) { item in
                    ListRow(item.rule.rule, onActivate: { model.reveal(item.rule, store: store) }, accessibilityName: "\(item.rule.rule), \(RulesTabWording.coveredBy(item.by))") {
                        MetaCell(text: RulesTabWording.coveredBy(item.by))
                        Button { model.removeRule(item.rule) } label: { ActionLabel("Remove", glyph: .trash) }
                            .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
                            .accessibilityLabel("Remove \(item.rule.rule)")
                    }
                    .help(item.rule.rule)
                }
            }
        }
    }

    // MARK: The spine

    private func spineCard(_ page: RulesPage, current: CoreRule?) -> some View {
        Tile("Permissions", maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, scrollTarget: current?.id, isOpen: open("spine")) {
            if page.isListEmpty {
                QuietEmptyState("Nothing matches", message: "No rule fits these filters.", placement: .card) {
                    Button { model.clearFilters() } label: { ActionLabel("Clear filters") }.buttonStyle(ActionButtonStyle(size: .compact))
                }
            } else {
                ColumnHead(reading: page.reading)
                BandStack {
                    ForEach(Array(page.layout.bands.enumerated()), id: \.element.id) { offset, band in
                        Band(band.family.title, count: band.rules.count,
                             state: band.holdsProblem ? StateMark(.warn, label: "Open in one CLI and denied in the other") : nil,
                             isOpen: store.binding(page: RulesModel.page, id: band.id, byDefault: opensByDefault(page.layout, offset))) {
                            ListRows { ForEach(band.rules) { rule in row(rule, band: band, current: current) } }
                        } lead: {
                            EmptyView()
                        } extras: {
                            HStack(spacing: Metrics.ListRow.spacing) {
                                Text(band.stance.summary).frame(width: Metrics.Rules.columnWidth, alignment: .leading)
                                Text(band.fact?.text ?? "").frame(width: Metrics.Rules.columnWidth, alignment: .leading).help(band.fact?.text ?? "")
                            }
                            .spaceVibeText(.meta, tone: .tertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .offset(x: Metrics.Rules.extrasBleed)
                        }
                    }
                }
                if let note = page.reading.note {
                    Text(note)
                        .spaceVibeText(.metaLine, tone: .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineBox(.metaLine)
                        .padding(.horizontal, Metrics.ListRow.leading)
                        .padding(.top, Metrics.Rules.noteTop)
                }
            }
        }
    }

    /// V5-R55: a family open in one CLI and denied in the other opens; when nothing needs the user, the first opens; a Filter opens
    /// every band it leaves rows in, so a match is never hidden.
    private func opensByDefault(_ layout: RulesLayout, _ offset: Int) -> Bool {
        model.filter.isOn || Self.opensByDefault(layout, offset)
    }

    static func opensByDefault(_ layout: RulesLayout, _ offset: Int) -> Bool {
        OpenStateStore.defaultOpen(holdsProblem: layout.bands[offset].holdsProblem, isFirst: offset == 0, pageNeedsUser: !layout.mismatches.isEmpty)
    }

    /// The rows the user can see, in order: the rows of every open band.
    static func visibleRules(_ layout: RulesLayout, store: OpenStateStore, filterIsOn: Bool = false) -> [CoreRule] {
        let open = Dictionary(uniqueKeysWithValues: layout.bands.enumerated().map { offset, band in
            (band.id, store.isOpen(page: RulesModel.page, id: band.id, byDefault: filterIsOn || opensByDefault(layout, offset)))
        })
        return layout.rows { open[$0.id] ?? false }
    }

    // MARK: Rows

    private func row(_ rule: CoreRule, band: RuleBand, current: CoreRule?) -> some View {
        ListRow(rule.rule, isCurrent: rule.id == current?.id, onActivate: { model.open(rule) }, accessibilityName: RulesTabWording.spoken(rule)) {
            CountCell(text: RulesWording.title(rule.verdict), width: Metrics.Rules.columnWidth, alignment: .leading)
            Color.clear.frame(width: Metrics.Rules.columnWidth, height: 0).accessibilityHidden(true)
        }
        .help(rule.rule)
        .id(rule.id)
        .anchoredOverlay(isPresented: model.detailID == rule.id && model.verdictMenu != .rule(rule.id), id: "\(RulesModel.page):detail", placement: .popover, onOutsideTap: { model.detailID = nil }) {
            detail(rule, family: band.family)
        }
        // The detail's verdict menu hangs from the row, not from the button (an overlay drawn inside another overlay has no host to place
        // it), and takes the popover's place while it is open: Esc brings the popover back.
        .anchoredOverlay(isPresented: model.verdictMenu == .rule(rule.id), id: "rules.verdict:\(VerdictTarget.rule(rule.id).id)", placement: .menu(.trailing),
                         onOutsideTap: { model.verdictMenu = nil }) {
            VerdictMenu(model: model, target: .rule(rule.id), heading: "Verdict in Claude Code", current: rule.verdict, onClose: { _ in model.verdictMenu = nil })
        }
    }

    // MARK: The row detail (V5-R57, V5-R68)

    private func detail(_ rule: CoreRule, family: RuleFamily) -> some View {
        PopoverSurface(onExit: { model.detailID = nil }) {
            PopoverHead(name: rule.rule, sub: "\(family.title) \u{00B7} Claude Code") { CLIMark(CoreCLI.claude, size: .logo) }
            PopoverSentence(RulesTabWording.meaning(rule.verdict))
            PopoverPath("\(RulesTabWording.settingsFile) \u{00B7} permissions.\(rule.verdict.rawValue)")
            ViewThatFits(in: .horizontal) {
                PopoverActions { actions(rule).fixedSize() }
                VStack(alignment: .leading, spacing: Metrics.Popover.actionSpacing) { actions(rule) }.buttonStyle(ActionButtonStyle(size: .compact))
            }
        }
    }

    @ViewBuilder
    private func actions(_ rule: CoreRule) -> some View {
        VerdictMenuButton(model: model, target: .rule(rule.id), heading: "Verdict in Claude Code", current: rule.verdict, label: RulesWording.title(rule.verdict), size: .compact)
        Button { model.removeRule(rule) } label: { ActionLabel("Remove", glyph: .trash, key: "R") }
            .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
    }

    // MARK: Keys

    /// `j`/`k` and the arrows move, Return opens the detail, `r` and Delete remove, `/` opens Filter, Esc closes the detail (V5-R36).
    /// A key acts on the current row.
    private func keys(visible: [CoreRule], current: CoreRule?) -> some View {
        Group {
            HiddenKey(KeyboardShortcut("j", modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut(.downArrow, modifiers: [])) { model.move(by: 1, in: visible) }
            HiddenKey(KeyboardShortcut("k", modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.upArrow, modifiers: [])) { model.move(by: -1, in: visible) }
            HiddenKey(KeyboardShortcut(.return, modifiers: [])) { model.toggleDetail(of: current) }
            HiddenKey(KeyboardShortcut("r", modifiers: [])) { if let current { model.removeRule(current) } }
            HiddenKey(KeyboardShortcut(.delete, modifiers: [])) { if let current { model.removeRule(current) } }
            HiddenKey(KeyboardShortcut("/", modifiers: [])) { model.isFilterOpen = true }
            if model.detailID != nil { HiddenKey(KeyboardShortcut(.escape, modifiers: [])) { model.detailID = nil } }
        }
    }
}

/// The spine's column head: Claude Code, and Codex with a lock (read only), or "Codex not installed" (V5-R67). It sits over the
/// two 168 columns of the bands and the rows.
private struct ColumnHead: View {
    let reading: CodexReading

    var body: some View {
        HStack(spacing: Metrics.ListRow.spacing) {
            Spacer(minLength: 0)
            cell { CLIMark(CoreCLI.claude, size: .glyph); Text("Claude Code") }
            cell {
                CLIMark(CoreCLI.codex, size: .glyph)
                if reading == .notInstalled {
                    Text("Codex not installed")
                } else {
                    Text("Codex")
                    SpaceVibeIcon(content: .lock, size: .inline, ink: TextTone.tertiary.color, label: "read only")
                }
            }
        }
        .spaceVibeText(.meta, tone: .tertiary)
        .padding(.horizontal, Metrics.ListRow.leading)
        .padding(.trailing, Metrics.ListRow.trailing - Metrics.ListRow.leading)
        .frame(height: Metrics.Rules.headHeight)
        .accessibilityElement(children: .combine)
    }

    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Metrics.Rules.headSpacing) { content() }
            .lineLimit(1)
            .frame(width: Metrics.Rules.columnWidth, alignment: .leading)
    }
}

/// A button that opens the Allow/Ask/Deny menu for one rule or a whole family (V5-R67, V5-R68). A family's menu hangs from the button;
/// a rule's button sits in a popover, so its menu is the row's (`RulesCanvas.row`). Esc closes the menu and gives the focus back to the button.
struct VerdictMenuButton: View {
    @Bindable var model: RulesModel
    let target: VerdictTarget
    let heading: String
    /// The verdict the rule has, or the family when its rules agree; nil ticks nothing.
    let current: CoreVerdict?
    let label: String
    let size: ActionButtonSize

    @FocusState private var focused: Bool

    var body: some View {
        Button { model.toggleVerdictMenu(target) } label: { ActionLabel(label) }
            .buttonStyle(ActionButtonStyle(size: size))
            .focused($focused)
            .accessibilityLabel("Change \(heading), now \(label)")
            .anchoredOverlay(isPresented: isFamily && model.verdictMenu == target, id: "rules.verdict:\(target.id)", placement: .menu(.trailing),
                             onOutsideTap: { model.verdictMenu = nil }) {
                VerdictMenu(model: model, target: target, heading: heading, current: current, onClose: { refocus in
                    model.verdictMenu = nil
                    if refocus { focused = true }
                })
            }
    }

    private var isFamily: Bool {
        if case .family = target { true } else { false }
    }
}

/// The menu itself: a heading and Allow, Ask, Deny with the current one ticked. A pick closes it and writes.
private struct VerdictMenu: View {
    let model: RulesModel
    let target: VerdictTarget
    let heading: String
    let current: CoreVerdict?
    let onClose: (_ returnFocus: Bool) -> Void

    var body: some View {
        RadioMenu(entries: entries, onPick: pick, onClose: onClose)
    }

    private var entries: [MenuEntry] {
        [MenuEntry(id: "heading", title: heading, kind: .heading)]
            + CoreVerdict.allCases.map { MenuEntry(id: $0.rawValue, title: RulesWording.title($0), kind: .radio(isOn: current == $0)) }
    }

    private func pick(_ id: String) {
        model.verdictMenu = nil
        guard let verdict = CoreVerdict(rawValue: id) else { return }
        switch target {
        case .family(let family): model.set(family, to: verdict)
        case .rule(let ruleID):
            if let rule = model.page.rules.first(where: { $0.id == ruleID }) { model.set(rule, to: verdict) }
        }
    }
}
