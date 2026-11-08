import SwiftUI

/// An on/off setting (Settings > Update > Check for updates automatically), drawn rather than AppKit's switch so it
/// renders in the screenshots too: a 32 x 20 capsule, `accentSolid` when on and `track` when off, with a 16 pt knob.
/// Space and a click flip it; VoiceOver reads it as a switch with `label`. The row beside it shows the name.
struct SpaceVibeSwitch: View {
    let label: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn && isEnabled ? Palette.accentSolid : Palette.track)
                .frame(width: Metrics.switchWidth, height: Metrics.switchHeight)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isEnabled ? Palette.onAccent : Palette.surface)
                        .frame(width: Metrics.switchKnob, height: Metrics.switchKnob)
                        .padding(Space.s2)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .spaceVibeFocusable(cornerRadius: Metrics.switchHeight / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
