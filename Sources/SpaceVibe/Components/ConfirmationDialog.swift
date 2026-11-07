import SwiftUI

/// A confirmation in front of an action: a scrim over the page and a card in the palette's style with a title, a plain
/// message, optional details and the buttons. A view rather than a system sheet so the same view renders in the headless
/// screenshots. Esc and a click on the scrim cancel, unless `canCancel` is false (while the action runs).
struct ConfirmationDialog<Details: View, Actions: View>: View {
    let title: String
    var message: String?
    /// What VoiceOver says for the dialog; the title when nil.
    var spokenLabel: String?
    var width: CGFloat = Metrics.dialogWidth
    var canCancel = true
    let cancel: () -> Void
    let details: Details
    let actions: Actions

    init(
        _ title: String, message: String? = nil, spokenLabel: String? = nil, width: CGFloat = Metrics.dialogWidth, canCancel: Bool = true,
        cancel: @escaping () -> Void, @ViewBuilder details: () -> Details, @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.spokenLabel = spokenLabel
        self.width = width
        self.canCancel = canCancel
        self.cancel = cancel
        self.details = details()
        self.actions = actions()
    }

    var body: some View {
        ZStack {
            Palette.overlay
                .ignoresSafeArea()
                .onTapGesture { if canCancel { cancel() } }
                .accessibilityHidden(true)
            card
        }
        .onExitCommand { if canCancel { cancel() } }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.paletteRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.s8) {
            Text(title).spaceVibeText(.bodyStrong, tone: .primary).lineLimit(2)
            if let message {
                Text(message).spaceVibeText(.body, tone: .secondary).fixedSize(horizontal: false, vertical: true)
            }
            details
            HStack(spacing: Rhythm.tools) {
                Spacer(minLength: 0)
                actions
            }
            .padding(.top, Space.s12)
        }
        .padding(Space.s24)
        .frame(width: width)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.overlayShadow, radius: Metrics.overlayShadowRadius, y: Metrics.overlayShadowOffset)
        .controlGround(.card)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(spokenLabel ?? title)
    }
}

extension ConfirmationDialog where Details == EmptyView {
    init(
        _ title: String, message: String? = nil, spokenLabel: String? = nil, width: CGFloat = Metrics.dialogWidth, canCancel: Bool = true,
        cancel: @escaping () -> Void, @ViewBuilder actions: () -> Actions
    ) {
        self.init(title, message: message, spokenLabel: spokenLabel, width: width, canCancel: canCancel, cancel: cancel, details: { EmptyView() }, actions: actions)
    }
}

/// The two buttons of a v5 confirmation and the `Tab` cycle between them (V5-R59): the focus starts on Cancel and `Tab`
/// or `Shift-Tab` moves it to the other button, never out of the dialog.
enum ConfirmationFocus: Hashable {
    case cancel, confirm

    static let initial = ConfirmationFocus.cancel

    var next: ConfirmationFocus { self == .cancel ? .confirm : .cancel }
}

/// The v5 confirmation in front of an action that has no Undo (V5-R59, the Stop dialog): the scrim over the window and a
/// 400-wide card centred on it, `bgPop` with a `hair2` edge, the top-edge highlight and the dialog shadow, padding 20 20 16,
/// its parts 8 apart. The title (14/20 600), the message (13/20 `fg2`; a `Text`, so a pid can be bold), the small line
/// (12/16 `fg3`), then 12 below them the actions at the right: `Cancel` with its `esc` cap and the solid danger button. Esc
/// and a click on the scrim cancel, except while the action runs (`isWorking`). The old screens keep `ConfirmationDialog`
/// until the cut-over (X1).
struct ConfirmationPanel: View {
    let title: String
    let message: Text
    var note: String?
    let confirmTitle: String
    var confirmGlyph: ContentGlyph?
    var isWorking = false
    let cancel: () -> Void
    let confirm: () -> Void

    @FocusState private var focus: ConfirmationFocus?

    var body: some View {
        ZStack {
            Palette.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !isWorking { cancel() } }
                .accessibilityHidden(true)
            card
        }
        .onExitCommand { if !isWorking { cancel() } }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Metrics.Dialog.spacing) {
            Text(title)
                .spaceVibeText(.dialogTitle, tone: .primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            message
                .spaceVibeText(.prose, tone: .secondary)
                .lineSpacing(SpaceVibeType.prose.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(.prose)
            if let note {
                Text(note)
                    .spaceVibeText(.meta, tone: .tertiary)
                    .lineSpacing(SpaceVibeType.meta.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.meta)
            }
            HStack(spacing: Metrics.Dialog.actionSpacing) {
                Spacer(minLength: 0)
                Button(action: cancel) { ActionLabel("Cancel", key: "esc") }
                    .buttonStyle(ActionButtonStyle())
                    .focused($focus, equals: .cancel)
                Button(action: confirm) { ActionLabel(confirmTitle, glyph: confirmGlyph) }
                    .buttonStyle(ActionButtonStyle(kind: .solidDanger))
                    .focused($focus, equals: .confirm)
            }
            .disabled(isWorking)
            .focusEffectDisabled()
            .padding(.top, Metrics.Dialog.actionsAbove)
        }
        .padding(Metrics.Dialog.insets)
        .frame(width: Metrics.Dialog.width)
        .blockSurface(Palette.bgPop, edge: Palette.hair2)
        .overlayShadow(.dialog)
        .onAppear { focus = .initial }
        .onKeyPress(.tab) {
            focus = (focus ?? .initial).next
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(title)
    }
}
