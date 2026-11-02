import ReinsCore
import SwiftUI

/// The confirmation in front of a grid write. A scrim over the page and a card in the palette's style, like the Stop
/// confirmation in Activity (a view rather than a system sheet so it renders in the headless shots). It lists the exact
/// rules the write replaces and the rules it writes, and warns when a rule that stays still wins. Confirm holds the focus
/// (the write can be undone from the toast); Esc cancels.
struct RulesConfirmation: View {
    let pending: RulesPending
    let cancel: () -> Void
    let confirm: () -> Void

    @FocusState private var confirmFocused: Bool

    var body: some View {
        ZStack {
            Palette.overlay
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
                .accessibilityHidden(true)
            card
        }
        .onAppear { confirmFocused = true }
        .onExitCommand(perform: cancel)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.paletteRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text(pending.question)
                .font(ReinsFont.bodyStrong)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
            Text(pending.location)
                .font(ReinsFont.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            group("Replaces", rules: pending.preview.replaces, empty: "Nothing: no rule here yet.")
            group("Writes", rules: pending.preview.writes, empty: "")
            if let warning = pending.warning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.warnInk).accessibilityHidden(true)
                    Text(warning).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
                .font(ReinsFont.small)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.warnTint))
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.reins(.normal))
                    .keyboardShortcut(.cancelAction)
                Button("Set to \(RulesWording.title(pending.verdict))", action: confirm)
                    .buttonStyle(.reins(.primary))
                    .focused($confirmFocused)
                    .focusEffectDisabled()
                    .focusRing(confirmFocused, cornerRadius: Metrics.controlRadius)
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(width: 460)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.overlayShadow, radius: 30, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(pending.question)
    }

    private func group(_ title: String, rules: [VerdictRule], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(ReinsFont.smallStrong).foregroundStyle(Palette.textSecondary).padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                if rules.isEmpty { Text(empty).font(ReinsFont.small).foregroundStyle(Palette.textTertiary) }
                ForEach(rules, id: \.self) { rule in
                    HStack(spacing: 8) {
                        Tag(RulesWording.title(rule.verdict), tone: RulesWording.tone(rule.verdict))
                        Text(rule.rule).font(ReinsFont.mono).foregroundStyle(Palette.text).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
