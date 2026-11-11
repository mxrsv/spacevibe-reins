import SwiftUI

/// The confirmation in front of a grid write. A scrim over the page and a card in the palette's style, like the Stop
/// confirmation in Activity (a view rather than a system sheet so it renders in the headless shots). It lists the exact
/// rules the write replaces and the rules it writes, and warns when a rule that stays still wins. Confirm holds the focus
/// (the write can be undone from the toast); Esc cancels.
struct RulesConfirmation: View {
    let pending: RulesPending
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ConfirmationDialog(pending.question, message: pending.location, width: Metrics.wideDialogWidth, cancel: cancel) {
            group("Replaces", rules: pending.preview.replaces, empty: "Nothing: no rule here yet.")
            group("Writes", rules: pending.preview.writes, empty: "")
            if let warning = pending.warning { WarningNote(text: warning) }
        } actions: {
            Button("Cancel", action: cancel)
                .buttonStyle(.spaceVibe(.normal))
                .keyboardShortcut(.cancelAction)
            Button("Set to \(RulesWording.title(pending.verdict))", action: confirm)
                .buttonStyle(.spaceVibe(.primary))
                .spaceVibeFocusable(cornerRadius: Metrics.controlRadius, focusOnAppear: true, onSolid: true)
        }
    }

    private func group(_ title: String, rules: [CoreVerdictRule], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            Text(title).spaceVibeText(.captionStrong, tone: .secondary).padding(.top, Space.s6)
            InsetBox {
                if rules.isEmpty { Text(empty).spaceVibeText(.caption, tone: .tertiary) }
                ForEach(rules, id: \.self) { rule in
                    HStack(spacing: Space.s8) {
                        Tag(RulesWording.title(rule.verdict), tone: RulesWording.tone(rule.verdict))
                        Text(rule.rule).spaceVibeText(.code, tone: .primary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
