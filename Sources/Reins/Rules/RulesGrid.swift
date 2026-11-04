import ReinsCore
import SwiftUI

/// Column widths shared by the heading, the rows and the expanded detail so everything lines up.
enum RulesColumns {
    static let claude = Metrics.rulesClaudeColumn
    static let codex = Metrics.rulesCodexColumn
}

/// The capability grid: an inset grouped table, one row per capability, a Claude Code column you can set and a Codex column that only shows.
struct RulesGrid: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    var body: some View {
        GroupedList {
            CardHeader("What the agent may do", columns: {
                CLIColumnHead(.claude, width: RulesColumns.claude)
                CLIColumnHead(.codex, width: RulesColumns.codex)
            })
            ForEach(snapshot.grid, id: \.capability) { cell in
                let open = model.expanded.contains(cell.capability)
                RulesGridRow(model: model, snapshot: snapshot, cell: cell, isOpen: open)
                if open {
                    RulesGridDetail(cell: cell, codex: CodexCellWording.cell(cell.capability, snapshot.codex))
                        .groupedListPart(.detail)
                }
            }
        }
    }
}

private struct RulesGridRow: View {
    let model: RulesModel
    let snapshot: RulesSnapshot
    let cell: CapabilityCell
    let isOpen: Bool

    var body: some View {
        Row(revealActions: false, onActivate: { model.toggle(cell.capability) }) {
            RowText(cell.label)
        }
        .lead {
            Chevron(isOpen ? .down : .right, size: .row)
        }
        .cells {
            RulesClaudeCell(model: model, cell: cell, isEditable: snapshot.isEditable(cell), problemsInFile: !snapshot.problems.isEmpty)
                .frame(width: RulesColumns.claude, alignment: .leading)
            RulesCodexCell(view: CodexCellWording.cell(cell.capability, snapshot.codex))
                .frame(width: RulesColumns.codex, alignment: .leading)
        }
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows the rules behind this row")
    }
}

/// Allow / Ask / Deny showing the derived state. Nothing is selected for `mixed` or `none`. A click opens the confirmation;
/// it never writes by itself, so the selection only moves once the file says so.
private struct RulesClaudeCell: View {
    let model: RulesModel
    let cell: CapabilityCell
    let isEditable: Bool
    let problemsInFile: Bool

    var body: some View {
        HStack(spacing: Space.s8) {
            SegmentedControl(
                label: "\(cell.label) for Claude Code",
                options: RulesWording.verdicts.map { SegmentOption(RulesWording.title($0), value: Optional($0)) },
                selection: Binding(get: { verdict }, set: { if let picked = $0 { model.requestSet(cell.capability, to: picked) } })
            )
            .disabled(!isEditable)
            .help(problemsInFile ? RulesWording.invalidFileHelp : "")
            switch cell.state {
            case .mixed:
                Tag("mixed", tone: .warn, icon: .info)
                    .help(RulesWording.mixedHelp)
                    .accessibilityHint(RulesWording.mixedHelp)
            case .none:
                // A file that cannot be read says nothing about its rules.
                if !problemsInFile { Tag("no rule") }
            default:
                EmptyView()
            }
        }
    }

    private var verdict: RuleVerdict? {
        switch cell.state {
        case .allow: .allow
        case .ask: .ask
        case .deny: .deny
        case .mixed, .none: nil
        }
    }
}

/// The real Codex setting, display only: a tag and the key name, or "no setting".
private struct RulesCodexCell: View {
    let view: CodexCellView

    var body: some View {
        HStack(spacing: Space.s8) {
            switch view.tone {
            case .none:
                Text(view.label).reinsText(.body, tone: .tertiary)
            case .warn:
                Tag(view.label, tone: .warn)
            case .neutral:
                Tag(view.label)
            }
            if let key = view.keys.first {
                Text(key.shortKey).reinsText(.code, tone: .secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The concrete rules behind a Claude Code cell and the real Codex keys, under the row that was opened.
private struct RulesGridDetail: View {
    let cell: CapabilityCell
    let codex: CodexCellView

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.rowSpacing) {
            ColumnSpacer(width: Metrics.rowLeadWidth)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Space.s6) {
                if cell.rules.isEmpty {
                    Text("No rule behind this cell.").reinsText(.caption, tone: .tertiary)
                }
                ForEach(Array(cell.rules.enumerated()), id: \.offset) { _, rule in
                    HStack(spacing: Space.s8) {
                        Tag(RulesWording.title(rule.verdict), tone: RulesWording.tone(rule.verdict))
                        Text(rule.rule).reinsText(.code, tone: .primary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .frame(width: RulesColumns.claude, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(codex.keys, id: \.key) { key in
                    Text("\(key.key) = \(key.value)").reinsText(.code, tone: .primary).fixedSize(horizontal: false, vertical: true)
                }
                if let note = codex.note {
                    Text(note).reinsText(.caption, tone: .tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: RulesColumns.codex, alignment: .leading)
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
