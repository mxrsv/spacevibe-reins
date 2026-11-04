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
            Text(title).reinsText(.bodyStrong, tone: .primary).lineLimit(2)
            if let message {
                Text(message).reinsText(.body, tone: .secondary).fixedSize(horizontal: false, vertical: true)
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
