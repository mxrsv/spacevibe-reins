import SwiftUI

/// The Skills list (V5-R21 to V5-R27, V5-R55): flat by default, bands only while a grouping is on. Each row is a `ListRow`
/// with the category glyph (a checkbox on hover and in multi-select), the name, the logo strip and the warning slot.
struct SkillsList: View {
    let model: SkillsModel
    let layout: SkillsQuery.Layout
    let current: LoadoutRow?
    let detected: [CoreCLI]

    @Environment(\.openStateStore) private var store

    static let page = "skills"

    var body: some View {
        if !model.isLoaded {
            LoadingSkeleton()
        } else if layout.rows.isEmpty {
            empty
        } else if layout.isGrouped {
            BandStack {
                ForEach(Array(layout.groups.enumerated()), id: \.element.id) { offset, group in
                    Band(group.title, count: group.rows.count,
                         isOpen: store.binding(page: Self.page, id: group.id, byDefault: Self.opensByDefault(layout, offset))) {
                        ListRows { ForEach(group.rows) { row in listRow(row) } }
                    } lead: {
                        groupLead(group)
                    }
                }
            }
        } else {
            ListRows { ForEach(layout.rows) { row in listRow(row) } }
        }
    }

    /// V5-R55: a band holding a problem opens; when nothing needs the user, the first opens; the others start closed.
    static func opensByDefault(_ layout: SkillsQuery.Layout, _ offset: Int) -> Bool {
        OpenStateStore.defaultOpen(holdsProblem: layout.groups[offset].holdsProblem, isFirst: offset == 0,
                                   pageNeedsUser: layout.groups.contains { $0.holdsProblem })
    }

    /// The rows the user can see, in order: the rows of every open band (all of them when flat).
    static func visibleRows(_ layout: SkillsQuery.Layout, store: OpenStateStore) -> [LoadoutRow] {
        guard layout.isGrouped else { return layout.rows }
        return layout.groups.enumerated().flatMap { offset, group in
            store.isOpen(page: page, id: group.id, byDefault: opensByDefault(layout, offset)) ? group.rows : []
        }
    }

    // MARK: Rows

    private func listRow(_ row: LoadoutRow) -> some View {
        let picked = model.picked.contains(row.key)
        return ListRow(row.name, lead: CategoryGlyph.skill, isCurrent: row.key == current?.key, isPicked: picked,
                       showsCheckboxes: !model.picked.isEmpty, onPick: { model.togglePick(row.key) },
                       onActivate: { model.select(row.key) }, accessibilityName: spoken(row)) {
            LogoStrip {
                ForEach(detected, id: \.self) { cli in
                    LogoToggle(cli: CoreLimitsCLI(cli), isLit: row.members[cli] != nil, mode: model.mode(row, cli: cli),
                               justChanged: model.changed.contains("\(row.key):\(cli.rawValue)")) { model.toggle(row, cli: cli) }
                }
            }
            warningSlot(row)
        }
        .id(row.key)
    }

    @ViewBuilder
    private func warningSlot(_ row: LoadoutRow) -> some View {
        if let warning = SkillsWording.warning(for: row) {
            WarningSlot(mark: StateMark(warning.kind == .neverRan ? .warn : .clock, label: warning.label), detail: warning.sentence,
                        id: Self.slotID(row)) {
                PopoverSentence(warning.sentence)
                if let plugin = warning.plugin { PopoverNote("Owned by the \(plugin) plugin. Read only.", glyph: .lock) }
                PopoverActions {
                    if warning.offersRemove {
                        Button { model.remove([row]) } label: { ActionLabel("Remove", glyph: .trash) }
                            .buttonStyle(ActionButtonStyle(kind: .danger, size: .compact))
                    }
                    Button { model.openFile(of: row) } label: { ActionLabel("Open file", glyph: .open) }
                }
            }
        } else {
            WarningSlot()
        }
    }

    static func slotID(_ row: LoadoutRow) -> String { "\(page):warn:\(row.key)" }

    private func spoken(_ row: LoadoutRow) -> String {
        let status = SkillsWording.warning(for: row)?.label
        return [row.name, status].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Groups and the empty states

    @ViewBuilder
    private func groupLead(_ group: SkillsQuery.Group) -> some View {
        if let status = group.status {
            VerdictGlyph(status.verdict, size: .control)
        } else {
            SpaceVibeIcon(content: groupGlyph(group), ink: TextTone.secondary.color)
        }
    }

    private func groupGlyph(_ group: SkillsQuery.Group) -> ContentGlyph {
        switch group.id {
        case "owner:plugin": .lock
        case "owner:mine": .file
        case let id where id.hasPrefix("tier:"): .rank
        default: .stack
        }
    }

    @ViewBuilder
    private var empty: some View {
        if model.query.filter.isOn {
            QuietEmptyState("Nothing matches", message: "No skill fits these filters.", placement: .list) {
                Button { model.clearFilters() } label: { ActionLabel("Clear filters") }
                    .buttonStyle(ActionButtonStyle(size: .compact))
            }
        } else {
            QuietEmptyState("No skills", message: "This category is empty.", placement: .list)
        }
    }
}
