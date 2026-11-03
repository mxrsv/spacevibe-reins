import SwiftUI

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var count: Int?

    var id: Value { value }

    init(_ title: String, value: Value, count: Int? = nil) {
        self.title = title
        self.value = value
        self.count = count
    }
}

/// A one-of-N switch (Allow / Ask / Deny, Shared / Local). Always has a selection. Left and Right arrows move it while a
/// segment has focus. A 28 pt frame with 24 pt segments inside it, no outline: the frame takes the control ground's fill and
/// the selected segment the `selection` tint. The selected segment is semibold, and every segment reserves its semibold
/// width so the control never changes width.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    let options: [SegmentOption<Value>]
    @Binding var selection: Value

    @FocusState private var focused: Value?
    @Environment(\.controlGround) private var ground

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(Space.s2)
        .frame(height: Metrics.controlHeight)
        .background(frame.fill(ground.fill))
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: SegmentOption<Value>) -> some View {
        let isOn = option.value == selection
        let shape = RoundedRectangle(cornerRadius: Metrics.segmentRadius, style: .continuous)
        return Button {
            selection = option.value
        } label: {
            HStack(spacing: Space.s6) {
                // The hidden semibold copy holds the width; the visible title sits on it.
                Text(option.title)
                    .reinsText(.bodyStrong)
                    .hidden()
                    .overlay { Text(option.title).reinsText(isOn ? .bodyStrong : .body, tone: isOn ? .primary : .secondary) }
                if let count = option.count { Count(count) }
            }
            .padding(.horizontal, Space.s8)
            .frame(height: Metrics.segmentHeight)
            .background(shape.fill(isOn ? Palette.selection : .clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focused, equals: option.value)
        .focusEffectDisabled()
        .focusRing(focused == option.value, cornerRadius: Metrics.segmentRadius)
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
