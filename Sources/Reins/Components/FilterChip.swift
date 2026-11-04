import SwiftUI

/// A pill that filters a list, 28 pt high like every control: a raised capsule (spec v4), or the accent with white text
/// while on. Several chips side by side act as one single-choice filter; the caller owns the state. `count` is how many rows
/// the filter would show. `code` sets the title as a machine string (a model name in the Model panel).
///
/// The dismissible form is an applied scope ("spacevibe-bench ×"): always on, and only the × acts. The × is its own
/// button with a spoken label, so a keyboard user reaches it directly.
struct FilterChip: View {
    let title: String
    var count: Int?
    var code = false
    let isOn: Bool
    let action: () -> Void
    var onDismiss: (() -> Void)?
    @Environment(\.forcedControlState) private var forced
    @State private var hovering = false
    @State private var pressing = false

    init(_ title: String, count: Int? = nil, code: Bool = false, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.code = code
        self.isOn = isOn
        self.action = action
    }

    /// An applied scope that the × clears.
    init(dismissible title: String, onDismiss: @escaping () -> Void) {
        self.title = title
        isOn = true
        action = {}
        self.onDismiss = onDismiss
    }

    var body: some View {
        if let onDismiss {
            pill(trailing: Space.s8) {
                Text(title)
                Button(action: onDismiss) {
                    PageIcon(.close).foregroundStyle(Palette.onAccent.opacity(0.85))
                }
                .buttonStyle(.plain)
                .reinsFocusable(cornerRadius: Metrics.segmentRadius)
                .help("Clear \(title)")
                .accessibilityLabel("Clear \(title)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                pill(trailing: Space.s12) {
                    Text(title).reinsText(code ? .codeTitle : .body)
                    if let count {
                        if isOn {
                            Text("\(count)").reinsText(.count).foregroundStyle(Palette.onAccent.opacity(0.85))
                        } else {
                            Count(count)
                        }
                    }
                }
            }
            .buttonStyle(PressReporting(pressing: $pressing))
            .reinsFocusable(cornerRadius: Metrics.chipHeight / 2)
            .focusRing(forced == .focus, cornerRadius: Metrics.chipHeight / 2)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
            .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
            .accessibilityHint("Filter")
        }
    }

    private func pill<Content: View>(trailing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let pressed = !isOn && (pressing || forced == .pressed)
        return HStack(spacing: Space.s6) { content() }
            .reinsText(.body)
            .foregroundStyle(isOn ? Palette.onAccent : Palette.text)
            .padding(.leading, Space.s12)
            .padding(.trailing, trailing)
            .frame(height: Metrics.chipHeight)
            .background {
                ControlBlock(look: isOn ? .chosen : .neutral, cornerRadius: Metrics.chipHeight / 2,
                             hovered: !isOn && (hovering || forced == .hover), pressed: pressed)
            }
            .offset(y: pressed ? Metrics.controlPressedOffset : 0)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}

/// A plain button style that reports whether it is held down, for a control that draws its own pressed block.
struct PressReporting: ButtonStyle {
    @Binding var pressing: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in pressing = isPressed }
    }
}
