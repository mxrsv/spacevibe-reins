import ReinsCore
import SwiftUI

/// "Claude Code rules at <scope>": the scope's rules grouped Deny, Ask first, Allow, each the rule as code with its
/// verdict tag after it, a way to change the verdict and a remove button (shown on hover or focus).
struct RulesList: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    var body: some View {
        GroupedList {
            CardHeader("Claude Code rules at \(snapshot.title)", count: snapshot.rules.count, lead: { CLIDot(.claude, decorative: true) })
            if snapshot.rules.isEmpty {
                EmptyRow(emptyText)
            }
            ForEach(RulesWording.listOrder, id: \.self) { verdict in
                let rules = snapshot.rules(verdict)
                if !rules.isEmpty {
                    SectionRow(RulesWording.groupTitle(verdict), count: rules.count)
                    // By offset: a hand-edited file can repeat a rule, and the engine's id is not unique then.
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, item in
                        RulesRuleRow(model: model, item: item)
                    }
                }
            }
        }
    }
}

private extension RulesList {
    var emptyText: String {
        if !snapshot.problems.isEmpty { return "The rules cannot be listed until the file is valid." }
        return snapshot.exists ? "No rules in this file." : "There is no settings file here yet. The first rule creates it."
    }
}

private struct RulesRuleRow: View {
    let model: RulesModel
    let item: RuleItem

    var body: some View {
        // The verdict sits right after its pattern: this card is Claude Code only, so it does not borrow the grid's columns.
        Row(revealActions: model.revealRowActions) {
            RowText(item.rule, mono: true) {
                Tag(RulesWording.title(item.verdict), tone: RulesWording.tone(item.verdict))
            }
        }
        .actions {
            RulesVerdictMenu(item: item) { model.move(item, to: $0) }
            RowActionButton(title: "Remove rule", icon: .trash, iconOnly: true) { model.remove(item) }
        }
    }
}

/// Moves a rule to another verdict. A menu in the app; headless screenshots cannot draw one, so they get a plain button.
private struct RulesVerdictMenu: View {
    let item: RuleItem
    let pick: (RuleVerdict) -> Void
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            Button {} label: { icon }.buttonStyle(.reins(.icon))
        } else {
            Menu {
                ForEach(RulesWording.verdicts.filter { $0 != item.verdict }, id: \.self) { verdict in
                    Button("Move to \(RulesWording.groupTitle(verdict))") { pick(verdict) }
                }
            } label: {
                icon
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.reins(.icon))
            .fixedSize()
            .help("Change verdict")
            .accessibilityLabel("Change verdict")
        }
    }

    private var icon: some View { PageIcon(.swap, label: "Change verdict") }
}
