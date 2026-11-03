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

/// A one-of-N switch (Allow / Ask / Deny, Global / Project). Always has a selection. Left and Right arrows
/// move it while a segment has focus.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    let options: [SegmentOption<Value>]
    @Binding var selection: Value

    @FocusState private var focused: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
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
            HStack(spacing: 5) {
                Text(option.title)
                if let count = option.count {
                    Text("\(count)").font(ReinsFont.small).foregroundStyle(Palette.textTertiary)
                }
            }
            .font(isOn ? ReinsFont.bodyStrong : ReinsFont.body)
            .foregroundStyle(isOn ? Palette.text : Palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(shape.fill(isOn ? Palette.surfaceRaised : .clear))
            .overlay(shape.strokeBorder(isOn ? Palette.border : .clear, lineWidth: 1))
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
