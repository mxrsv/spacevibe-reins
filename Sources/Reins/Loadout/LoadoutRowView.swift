import SwiftUI

/// One matrix row. Return, Space and a click only select it; the buttons inside it are the only things that change files.
struct LoadoutRowView: View {
    let model: LoadoutModel
    let row: LoadoutRow
    let max: Int
    let events: [String: [String]]
    let selected: Bool

    var body: some View {
        Row(selected: selected, revealActions: model.revealRowActions, onActivate: { model.select(row.key) }) {
            // A hook's second line is its command; everything else has a description.
            RowText(row.name, subtitle: row.detail.isEmpty ? nil : row.detail, codeSubtitle: row.kind == .hook) {
                ForEach(LoadoutFormat.tags(row), id: \.text) { tag in
                    Tag(tag.text, tone: tag.tone, icon: tag.icon)
                }
            }
        }
        .lead { ReinsIcon(row.kind.icon, size: .row) }
        .cells {
            ForEach(CoreCLI.allCases, id: \.self) { cli in
                UsageCell(
                    cli: cli,
                    model: LoadoutFormat.cellModel(row.cells[cli], scanFailure: model.scanFailure),
                    max: max,
                    onAdd: LoadoutRows.copyPlan(row, to: cli, events: events) == nil ? nil : { model.add(row, to: cli) }
                )
            }
        }
        .actions { actions }
    }

    /// One 28 pt slot per CLI: Remove, badged with that CLI's dot, where a removable copy exists; a lock when nothing is
    /// removable.
    private var actions: some View {
        let members = row.removableMembers
        return HStack(spacing: Space.s4) {
            if members.isEmpty {
                EmptyActionSlot()
                ReadOnlyMark(reason: LoadoutRows.readOnlyReason(row))
            } else {
                ForEach(CoreCLI.allCases, id: \.self) { cli in
                    if let member = members.first(where: { $0.cli == cli }) {
                        RowActionButton(title: LoadoutFormat.removeAction(row: row, member: member), icon: .trash, kind: .danger, iconOnly: true, badge: cli) {
                            model.remove(row, member: member)
                        }
                    } else {
                        EmptyActionSlot()
                    }
                }
            }
        }
        .frame(width: Metrics.loadoutActionsWidth, alignment: .trailing)
    }
}
