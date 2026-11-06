import ReinsCore
import SwiftUI

/// The fill a chosen segment takes instead of the accent (spec v4, Segmented control): a verdict picker's tone (Allow,
/// Ask, Deny; Allow, Prompt, Forbidden), or `warn` for a risky option (Never, Full access).
enum SegmentTone {
    case success, warn, danger

    var fill: Color {
        switch self {
        case .success: Palette.success
        case .warn: Palette.warn
        case .danger: Palette.danger
        }
    }

    var text: Color {
        switch self {
        case .success: Palette.onSuccess
        case .warn: Palette.onWarn
        case .danger: Palette.onDanger
        }
    }
}

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var count: Int?
    /// A CLI's bare glyph before the title (the Rules `Claude Code | Codex` switch).
    var cli: InventoryCLI?
    /// Picks this segment from anywhere in the window while the control is enabled (a hidden tab is disabled).
    var shortcut: KeyboardShortcut?
    /// The fill while chosen, instead of the accent.
    var tone: SegmentTone?

    var id: Value { value }

    init(_ title: String, value: Value, count: Int? = nil, cli: InventoryCLI? = nil, shortcut: KeyboardShortcut? = nil,
         tone: SegmentTone? = nil) {
        self.title = title
        self.value = value
        self.count = count
        self.cli = cli
        self.shortcut = shortcut
        self.tone = tone
    }
}

/// A one-of-N switch (Allow / Ask / Deny, Shared / Local). Always has a selection. Left and Right arrows move it while a
/// segment has focus. A 28 pt sunken track (spec v4: the control ground with an inner shadow, `segmentTrack` over it in
/// dark) with 24 pt segments inside it. The chosen segment is a raised block in the accent with white text, or in its
/// option's tone (`SegmentTone`), semibold; every segment reserves its semibold width so the control never changes width.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    let options: [SegmentOption<Value>]
    @Binding var selection: Value

    @FocusState private var focused: Value?
    @State private var hovered: Value?
    @Environment(\.controlGround) private var ground
    @Environment(\.forcedControlState) private var forced

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(Space.s2)
        .frame(height: Metrics.controlHeight)
        .background {
            ZStack {
                frame.fill(ground.fill)
                frame.fill(Palette.segmentTrack)
                InnerShadow(shape: frame, color: Palette.segmentShadow)
            }
        }
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// The gallery's forced state lands on the first segment that is not chosen, as in the mock's sheet.
    private var forcedValue: Value? { options.first { $0.value != selection }?.value }

    private func segment(_ option: SegmentOption<Value>) -> some View {
        let isOn = option.value == selection
        let isHovered = !isOn && (hovered == option.value || (forced == .hover && forcedValue == option.value))
        let isFocused = focused == option.value || (forced == .focus && forcedValue == option.value)
        return Button {
            selection = option.value
        } label: {
            HStack(spacing: Space.s6) {
                if let cli = option.cli { CLIMark(cli, size: .glyph) }
                // The hidden semibold copy holds the width; the visible title sits on it.
                Text(option.title)
                    .reinsText(.bodyStrong)
                    .hidden()
                    .overlay {
                        Text(option.title)
                            .reinsText(isOn ? .bodyStrong : .body)
                            .foregroundStyle(isOn ? (option.tone?.text ?? Palette.onAccent) : (isHovered ? Palette.text : Palette.textSecondary))
                    }
                if let count = option.count { Count(count) }
            }
            .padding(.horizontal, Space.s8)
            .frame(height: Metrics.segmentHeight)
            .background {
                if isOn {
                    ControlBlock(look: .segment(option.tone?.fill ?? Palette.accentSolid), cornerRadius: Metrics.segmentRadius)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.segmentRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(option.shortcut)
        .focused($focused, equals: option.value)
        .focusEffectDisabled()
        .focusRing(isFocused, cornerRadius: Metrics.segmentRadius)
        .onHover { inside in
            if inside { hovered = option.value } else if hovered == option.value { hovered = nil }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel(option.count.map { "\(option.title), \($0)" } ?? option.title)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard focused != nil, let index = options.firstIndex(where: { $0.value == selection }) else { return .ignored }
        let next = options[(index + step + options.count) % options.count].value
        selection = next
        focused = next
        return .handled
    }
}

/// A one-of-N value that is shown, not set (Codex's `sandbox_mode` on the Rules page): the segmented control's frame with
/// every option written out and the real one filled, so the alternatives read at a glance. Nothing is focusable or
/// clickable. The filled segment is `track` (on `surfaceRaised`) with semibold text, or the warn tint and ink for a value
/// that needs a look. `selected` nil fills nothing.
struct SegmentReadout: View {
    let label: String
    let options: [String]
    let selected: String?
    var warn = false

    @Environment(\.controlGround) private var ground

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selected
                Text(option)
                    .reinsText(.bodyStrong)
                    .hidden()
                    .overlay { Text(option).reinsText(isOn ? .bodyStrong : .body, tone: isOn ? (warn ? .warn : .primary) : .tertiary) }
                    .padding(.horizontal, Space.s8)
                    .frame(height: Metrics.segmentHeight)
                    .background(RoundedRectangle(cornerRadius: Metrics.segmentRadius, style: .continuous).fill(isOn ? (warn ? Palette.warnTint : Palette.track) : .clear))
            }
        }
        .padding(Space.s2)
        .frame(height: Metrics.controlHeight)
        .background {
            ZStack {
                frame.fill(ground.fill)
                frame.fill(Palette.segmentTrack)
                InnerShadow(shape: frame, color: Palette.segmentShadow)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(selected ?? "none")
    }
}
