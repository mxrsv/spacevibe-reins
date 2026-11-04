import SwiftUI

/// Every button kind in every state it has, on a card (spec v4, DL10; the sheet of `mocks/agents/controls.html`): ten
/// kinds down, seven states across. Hover, pressed and focus are forced (`forcedControlState`) so they show at once; a
/// state a kind does not have reads "—".
struct ButtonSheet: View {
    enum Kind: CaseIterable {
        case primary, secondary, ghost, danger, icon, cardButton, segmented, verdict, chip, scope

        var title: String {
            switch self {
            case .primary: "Primary"
            case .secondary: "Secondary"
            case .ghost: "Ghost"
            case .danger: "Danger"
            case .icon: "Icon"
            case .cardButton: "Card button"
            case .segmented: "Segmented"
            case .verdict: "Verdict picker"
            case .chip: "Filter chip"
            case .scope: "Scope picker"
            }
        }

        func has(_ state: SheetState) -> Bool {
            switch state {
            case .normal, .hover, .pressed, .focus: true
            case .chosen: [.cardButton, .segmented, .verdict, .chip].contains(self)
            case .disabled: [.primary, .secondary, .ghost, .danger, .icon, .scope].contains(self)
            case .loading: [.primary, .secondary, .danger, .icon].contains(self)
            }
        }
    }

    enum SheetState: CaseIterable {
        case normal, hover, pressed, focus, chosen, disabled, loading

        var title: String {
            switch self {
            case .normal: "Default"
            case .hover: "Hover"
            case .pressed: "Pressed"
            case .focus: "Focus"
            case .chosen: "Chosen"
            case .disabled: "Disabled"
            case .loading: "Loading"
            }
        }

        var forced: ForcedControlState? {
            switch self {
            case .hover: .hover
            case .pressed: .pressed
            case .focus: .focus
            default: nil
            }
        }
    }

    var body: some View {
        GroupedList {
            CardHeader("Buttons", detail: "every kind, every state, on a card")
            Grid(alignment: .leading, horizontalSpacing: Space.s24, verticalSpacing: Space.s12) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(SheetState.allCases, id: \.self) { state in
                        Text(state.title).reinsText(.label, tone: .tertiary)
                    }
                }
                ForEach(Kind.allCases, id: \.self) { kind in
                    Rectangle().fill(Palette.divider).frame(height: 1).gridCellColumns(SheetState.allCases.count + 1)
                    GridRow {
                        Text(kind.title).reinsText(.rowTitle, tone: .primary)
                        ForEach(SheetState.allCases, id: \.self) { state in
                            cell(kind, state)
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.vertical, Space.s12)
            .environment(\.actionsConcealed, false)
            .groupedListPart(.plain)
        }
    }

    @ViewBuilder
    private func cell(_ kind: Kind, _ state: SheetState) -> some View {
        if kind.has(state) {
            specimen(kind, state)
                .forcedControlState(state.forced)
                .controlLoading(state == .loading)
                .disabled(state == .disabled)
        } else {
            Text("\u{2014}").reinsText(.caption, tone: .tertiary)
        }
    }

    @ViewBuilder
    private func specimen(_ kind: Kind, _ state: SheetState) -> some View {
        let chosen = state == .chosen
        switch kind {
        case .primary:
            Button {} label: { ButtonLabel("Review and save") }.buttonStyle(.reins(.primary))
        case .secondary:
            Button {} label: { ButtonLabel("Add hook", icon: .add) }.buttonStyle(.reins(.normal))
        case .ghost:
            Button {} label: { ButtonLabel("Discard") }.buttonStyle(.reins(.ghost))
        case .danger:
            Button {} label: { ButtonLabel("Remove 1 dead", icon: .trash) }.buttonStyle(.reins(.danger))
        case .icon:
            Button {} label: {
                if state == .loading { Spinner() } else { PageIcon(.close) }
            }
            .buttonStyle(.reins(.icon))
            .accessibilityLabel("Close")
        case .cardButton:
            CardButton("Permissions", icon: .permissions, value: .count("11"), isOpen: chosen) {}
        case .segmented:
            SegmentedControl(label: "Sandbox", options: [
                SegmentOption("Read only", value: "read-only"),
                SegmentOption("Workspace", value: "workspace-write"),
                SegmentOption("Full", value: "danger-full-access"),
            ], selection: .constant(chosen ? "danger-full-access" : "read-only"))
        case .verdict:
            SegmentedControl(label: "Verdict", options: [
                SegmentOption("Allow", value: "allow", tone: .success),
                SegmentOption("Ask", value: "ask", tone: .warn),
                SegmentOption("Deny", value: "deny", tone: .danger),
            ], selection: .constant(chosen ? "deny" : "allow"))
        case .chip:
            FilterChip("opus", count: 104, code: true, isOn: chosen) {}
        case .scope:
            ScopePicker(options: [ScopeOption(id: nil, label: "Global")], current: ScopeOption(id: nil, label: "Global"),
                        minWidth: Metrics.scopePickerMinWidth) { _ in }
        }
    }
}
