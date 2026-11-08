import SwiftUI

/// What pressing a logo does (V5-R25).
enum LogoToggleMode: Equatable {
    /// Lit: remove the item from that CLI; dim: add it there. Each write shows a toast with Undo.
    case toggles
    /// A plugin owns the item, or SpaceVibe cannot write to that CLI: nothing to press.
    case readOnly
    /// The item's last lit logo: not a toggle; `Remove` in the pane or the warning popover is the explicit action.
    case onlyCopy
}

/// One CLI's logo in a row, the Skills pane or the bottom bar (V5-R24 to V5-R26): a 24 box (radius 6) holding the 20 pt
/// logo. Lit, the item is in that CLI and a 10 pt success badge with a check sits at the corner, ringed in the ground's
/// colour (`logoRing`). Dim, it is not: 35% and greyscale. Pressing toggles it; there is no popover and no tooltip.
///
/// States, one fill at a time: hovered `hover` (a dim logo brightens to 70%; a removable lit logo's badge turns danger),
/// pressed or focused `sel` (D57). Read-only and only-copy logos take no fill and show the not-allowed pointer.
/// `justChanged` plays the pop once (logo 0.8 to 1, then the badge); reduced motion drops it (V5-R42).
struct LogoToggle: View {
    let cli: CoreLimitsCLI
    let isLit: Bool
    var mode: LogoToggleMode = .toggles
    var justChanged = false
    /// What VoiceOver reads as the value when the default sentence does not fit (the bottom bar's "all picked skills are
    /// in Codex, press to remove them").
    var spokenValue: String?
    let action: () -> Void

    @Environment(\.logoRing) private var ring
    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isShotRendering) private var isShotRendering
    @State private var hovering = false
    @State private var popped = true
    @FocusState private var focused: Bool

    var body: some View {
        let hovered = (hovering || specimen.contains(.hover)) && mode == .toggles
        let isFocused = focused || specimen.contains(.focus)
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                CLIMark(cli, size: .logo)
                    .grayscale(isLit ? 0 : 1)
                    .opacity(logoOpacity(hovered: hovered))
                    .scaleEffect(popped ? 1 : Metrics.LogoToggle.popFrom)
                    .frame(width: Metrics.LogoToggle.box, height: Metrics.LogoToggle.box)
                if isLit {
                    LogoBadge(fill: hovered ? Palette.bad : Palette.ok, ring: ring)
                        .scaleEffect(popped ? 1 : 0)
                        .opacity(popped ? 1 : 0)
                }
            }
            .frame(width: Metrics.LogoToggle.box, height: Metrics.LogoToggle.box)
            .background(shape.fill(fill(hovered: hovered, focused: isFocused || specimen.contains(.press))))
            .contentShape(shape)
        }
        .buttonStyle(LogoPressStyle())
        .disabled(mode != .toggles)
        .pointerStyle(mode == .toggles ? .link : .notAllowed)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .onAppear { if justChanged { pop() } }
        .onChange(of: justChanged) { _, now in if now { pop() } }
        .accessibilityLabel(cli.label)
        .accessibilityValue(spokenValue ?? Self.spokenValue(cli: cli, isLit: isLit, mode: mode))
        .accessibilityAddTraits(.isToggle)
    }

    private func logoOpacity(hovered: Bool) -> Double {
        if isLit { return 1 }
        return hovered ? Metrics.LogoToggle.dimHoverOpacity : Metrics.LogoToggle.dimOpacity
    }

    private func fill(hovered: Bool, focused: Bool) -> Color {
        if focused && mode == .toggles { return Palette.sel }
        return hovered ? Palette.hover : .clear
    }

    private func pop() {
        guard !reduceMotion, !isShotRendering else { return }
        popped = false
        withAnimation(.easeOut(duration: Metrics.Motion.logoPop)) { popped = true }
    }

    /// The value VoiceOver reads after the CLI's name (V5-R43): "not in Codex, press to add".
    static func spokenValue(cli: CoreLimitsCLI, isLit: Bool, mode: LogoToggleMode) -> String {
        let presence = isLit ? "in \(cli.label)" : "not in \(cli.label)"
        switch mode {
        case .toggles: return "\(presence), press to \(isLit ? "remove" : "add")"
        case .readOnly: return "\(presence), read-only"
        case .onlyCopy: return "\(presence), the only copy, use Remove to delete it"
        }
    }
}

/// The success badge: a 10 pt circle with a white check, ringed 1.5 pt in the ground's colour so it reads apart from the
/// logo under it (the kit's `BADGE`). The badge's fill carries the state against the ring (`ContrastTests`); the check
/// repeats it.
private struct LogoBadge: View {
    let fill: Color
    let ring: Color

    var body: some View {
        let badge = Metrics.LogoToggle.badge
        let scale = Metrics.LogoToggle.badgeGlyph / Metrics.LogoToggle.checkBox
        ZStack {
            Circle().fill(ring).frame(width: badge + 2 * Metrics.LogoToggle.badgeRing, height: badge + 2 * Metrics.LogoToggle.badgeRing)
            Circle().fill(fill).frame(width: badge, height: badge)
            BadgeCheck()
                .stroke(Palette.onAccent, style: StrokeStyle(lineWidth: Metrics.LogoToggle.checkStroke * scale, lineCap: .round, lineJoin: .round))
                .frame(width: Metrics.LogoToggle.badgeGlyph, height: Metrics.LogoToggle.badgeGlyph)
        }
        .frame(width: badge, height: badge)
        .accessibilityHidden(true)
    }
}

/// The badge's check in its 12 box: M2.5 6.3 L5 8.8 L9.5 3.6.
private struct BadgeCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / Metrics.LogoToggle.checkBox
        var path = Path()
        path.addLines([CGPoint(x: 2.5, y: 6.3), CGPoint(x: 5, y: 8.8), CGPoint(x: 9.5, y: 3.6)].map {
            CGPoint(x: rect.minX + $0.x * unit, y: rect.minY + $0.y * unit)
        })
        return path
    }
}

/// Pressed, a logo takes the `sel` fill (the kit's `:active`).
private struct LogoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background {
            if configuration.isPressed {
                RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle).fill(Palette.sel)
            }
        }
    }
}

/// The logos of the CLIs detected on the machine, 4 apart (V5-R24). The caller passes one `LogoToggle` per CLI.
struct LogoStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Metrics.LogoToggle.spacing) { content }
            .accessibilityElement(children: .contain)
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct LogoRingKey: EnvironmentKey {
    static let defaultValue = Palette.bgPanel
}

extension EnvironmentValues {
    /// The colour of the ring around a logo's badge: the ground the strip sits on. `bgPanel` by default (the kit's
    /// `--ring`); a popover and the bottom bar set `bgPop`.
    var logoRing: Color {
        get { self[LogoRingKey.self] }
        set { self[LogoRingKey.self] = newValue }
    }
}
