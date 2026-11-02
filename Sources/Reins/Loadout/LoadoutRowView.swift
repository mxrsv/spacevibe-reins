import ReinsCore
import SwiftUI

/// Room for one Remove button per CLI. Every row and the header reserve it so the two usage columns line up.
let loadoutActionsWidth: CGFloat = 100

/// One matrix row. Return, Space and a click only select it; the buttons inside it are the only things that change files.
struct LoadoutRowView: View {
    let model: LoadoutModel
    let row: LoadoutRow
    let max: Int
    let events: [String: [String]]
    let selected: Bool

    var body: some View {
        Row(selected: selected, revealActions: model.revealRowActions, onActivate: { model.select(row.key) }) {
            LoadoutRowText(row: row)
        }
        .lead { Image(systemName: row.kind.systemImage).accessibilityHidden(true) }
        .cells {
            ForEach(CLIKind.allCases) { cli in
                UsageCell(
                    cli: cli,
                    model: LoadoutFormat.cellModel(row.cells[cli.engine], scanFailure: model.scanFailure),
                    max: max,
                    onAdd: LoadoutRows.copyPlan(row, to: cli.engine, events: events) == nil ? nil : { model.add(row, to: cli.engine) }
                )
            }
        }
        .actions { actions }
    }

    /// One Remove button per CLI that holds a removable copy, each marked with its CLI dot; a lock when nothing is removable.
    private var actions: some View {
        let members = row.removableMembers
        return HStack(spacing: 4) {
            if members.isEmpty {
                Image(systemName: "lock")
                    .foregroundStyle(Palette.textTertiary)
                    .help(LoadoutRows.readOnlyReason(row))
                    .accessibilityLabel(LoadoutRows.readOnlyReason(row))
            } else {
                ForEach(members, id: \.id) { member in
                    Button { model.remove(row, member: member) } label: {
                        HStack(spacing: 5) {
                            CLIDot(member.cli.uiKind, decorative: true)
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.reins(.danger))
                    .help(LoadoutFormat.removeAction(row: row, member: member))
                    .accessibilityLabel(LoadoutFormat.removeAction(row: row, member: member))
                }
            }
        }
        .frame(width: loadoutActionsWidth, alignment: .trailing)
    }
}

/// The name with its tags, and one muted line: the description, or for a hook the command in monospace.
private struct LoadoutRowText: View {
    let row: LoadoutRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(ReinsFont.bodyStrong)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                ForEach(LoadoutFormat.tags(row), id: \.text) { tag in
                    Tag(tag.text, tone: tag.tone, systemImage: tag.systemImage)
                }
            }
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(row.kind == .hook ? ReinsFont.mono : ReinsFont.small)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
