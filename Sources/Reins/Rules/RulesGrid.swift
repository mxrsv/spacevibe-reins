import ReinsCore
import SwiftUI

/// The Claude Code capability grid: an inset grouped table, one row per capability with Allow / Ask / Deny and how many
/// rules sit behind it. Codex has its own page: it keeps no verdict per capability.
struct RulesGrid: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    var body: some View {
        GroupedList {
            CardHeader("What Claude Code may do")
            ForEach(snapshot.grid, id: \.capability) { cell in
                let open = model.expanded.contains(cell.capability)
                RulesGridRow(model: model, snapshot: snapshot, cell: cell, isOpen: open)
                if open {
                    RulesGridDetail(cell: cell)
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
                .frame(width: Metrics.rulesClaudeColumn, alignment: .leading)
            FixedCell {
                Text(RulesWording.ruleCount(cell.rules.count)).reinsText(.caption, tone: .tertiary)
            }
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
                options: RulesWording.verdicts.map { SegmentOption(RulesWording.title($0), value: Optional($0), tone: RulesWording.segmentTone($0)) },
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

/// The concrete rules behind a cell, under the row that was opened, each pattern followed by its verdict.
private struct RulesGridDetail: View {
    let cell: CapabilityCell

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            if cell.rules.isEmpty {
                Text("No rule behind this row.").reinsText(.caption, tone: .tertiary)
            }
            ForEach(Array(cell.rules.enumerated()), id: \.offset) { _, rule in
                HStack(spacing: Space.s8) {
                    Text(rule.rule).reinsText(.code, tone: .primary).lineLimit(1).truncationMode(.middle)
                    Tag(RulesWording.title(rule.verdict), tone: RulesWording.tone(rule.verdict))
                }
            }
        }
        .padding(.leading, Metrics.rowTextInset)
        .padding(.trailing, Metrics.rowHorizontalPadding)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
