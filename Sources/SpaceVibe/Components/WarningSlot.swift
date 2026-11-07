import SwiftUI

/// The warning slot at a row's end (V5-R27, V5-R14): a 24 square that is empty on a normal row, so the column keeps its
/// place, or holds one `StateMark` (the triangle in the warn or danger tone, the neutral clock, the lock). Hovering it or
/// giving it the keyboard focus opens its popover (`PopoverPresence`); Esc closes the popover and keeps the focus on the
/// slot. Hovered `hover`, focused `sel` (D57). VoiceOver reads the mark's label as the name and `detail`, the popover's
/// sentence, as the value (V5-R43).
///
///     WarningSlot(mark: StateMark(.warn, label: "Never ran"), detail: sentence, id: "warn:\(item.id)") {
///         PopoverSentence(sentence)
///         PopoverActions { … }
///     }
struct WarningSlot<Popover: View>: View {
    let mark: StateMark?
    var detail: String?
    /// Unique among the window's overlays.
    let id: AnyHashable
    @ViewBuilder var popover: Popover

    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.shownWarningSlot) private var shown
    @State private var presence = PopoverPresence()
    @State private var pending: Task<Void, Never>?
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        if let mark {
            slot(mark)
        } else {
            Color.clear
                .frame(width: Metrics.WarningSlot.size, height: Metrics.WarningSlot.size)
                .accessibilityHidden(true)
        }
    }

    private func slot(_ mark: StateMark) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        let fill: Color = focused || specimen.contains(.focus) ? Palette.sel
            : (hovering || specimen.contains(.hover) ? Palette.hover : .clear)
        return Button { apply(presence.handle(.activate)) } label: {
            StateMarkIcon(mark: mark)
                .frame(width: Metrics.WarningSlot.size, height: Metrics.WarningSlot.size)
                .background(shape.fill(fill))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { inside in
            hovering = inside
            apply(presence.handle(.anchorHover(inside)))
        }
        .onChange(of: focused) { _, now in apply(presence.handle(.anchorFocus(now))) }
        .onExitCommand { apply(presence.handle(.escape)) }
        .onDisappear { pending?.cancel() }
        .anchoredOverlay(isPresented: presence.isOpen || shown == id, id: id, placement: .popover) {
            PopoverSurface(onHover: { apply(presence.handle(.surfaceHover($0))) },
                           onExit: { apply(presence.handle(.escape)) }) { popover }
        }
        .accessibilityLabel(mark.label)
        .accessibilityValue(detail ?? "")
        .accessibilityHint("Shows what to do")
    }

    private func apply(_ effect: PopoverPresence.Effect) {
        switch effect {
        case .none:
            return
        case .changed(let refocus):
            pending?.cancel()
            if refocus { focused = true }
        case .settle(let delay):
            pending?.cancel()
            guard delay > .zero else { return }
            pending = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                presence.settle()
            }
        }
    }
}

extension WarningSlot where Popover == EmptyView {
    /// The empty slot of a normal row: it only keeps the column.
    init() {
        self.init(mark: nil, detail: nil, id: AnyHashable("empty")) { EmptyView() }
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct ShownWarningSlotKey: EnvironmentKey {
    static let defaultValue: AnyHashable? = nil
}

extension EnvironmentValues {
    /// The id of the one warning slot whose popover a headless shot draws open: a shot cannot hover. Only shot harnesses set it.
    var shownWarningSlot: AnyHashable? {
        get { self[ShownWarningSlotKey.self] }
        set { self[ShownWarningSlotKey.self] = newValue }
    }
}
