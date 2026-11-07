import SwiftUI

/// A key cap: "⌘K", "Esc". 20 pt high, `label` type, filled with the control ground and no outline. Purely visual; the
/// control it labels carries the accessibility label.
struct Kbd: View {
    let keys: String
    @Environment(\.controlGround) private var ground

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.kbdRadius, style: .continuous)
        Text(keys)
            .spaceVibeText(.label, tone: .secondary)
            .padding(.horizontal, Space.s6)
            .frame(minWidth: Metrics.kbdHeight, minHeight: Metrics.kbdHeight)
            .background(shape.fill(ground.fill))
            .accessibilityHidden(true)
    }
}

/// Where a key cap sits: on a surface, or on a solid button (`primary`, `solidDanger`).
enum KeyCapTone {
    case plain, onSolid
}

/// The v5 key cap (the kit's `kbd`): 18 high, at least 18 wide, 5 at the sides, radius 4, a 1 pt edge with a 2 pt
/// bottom, the letter 11/16 500 in `fg2` on `kbdBg`. On a solid button the letter is white and the cap has only its white
/// edge (`kbdOnSolidBorder`; the mock's white fill is dropped for contrast, a named departure). A label beside the control
/// says what the key does, so the cap is hidden from VoiceOver.
struct KeyCap: View {
    let keys: String
    @Environment(\.keyCapTone) private var tone

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.small, style: Metrics.Radius.cornerStyle)
        Text(keys)
            .spaceVibeText(.keyCap)
            .foregroundStyle(tone == .onSolid ? Palette.onAccent : Palette.fg2)
            .lineLimit(1)
            .padding(.horizontal, Metrics.KeyCap.padding)
            .padding(.bottom, Metrics.KeyCap.bottomEdge - Metrics.Radius.edge)
            .frame(minWidth: Metrics.KeyCap.minWidth)
            .frame(height: Metrics.KeyCap.height)
            .background(shape.fill(tone == .onSolid ? .clear : Palette.kbdBg))
            .overlay {
                KeyCapEdge(radius: Metrics.Radius.small)
                    .fill(tone == .onSolid ? Palette.kbdOnSolidBorder : Palette.kbdBorder, style: FillStyle(eoFill: true))
            }
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A key cap's edge: the rounded box less its inside, 1 pt at the top and sides and 2 pt at the bottom.
private struct KeyCapEdge: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let edge = Metrics.Radius.edge
        var inner = rect.insetBy(dx: edge, dy: edge)
        inner.size.height -= Metrics.KeyCap.bottomEdge - edge
        var path = RoundedRectangle(cornerRadius: radius, style: Metrics.Radius.cornerStyle).path(in: rect)
        path.addPath(RoundedRectangle(cornerRadius: max(0, radius - edge), style: Metrics.Radius.cornerStyle).path(in: inner))
        return path
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct KeyCapToneKey: EnvironmentKey {
    static let defaultValue = KeyCapTone.plain
}

extension EnvironmentValues {
    /// Set by `ActionButtonStyle`: a solid button's caps take the white form.
    var keyCapTone: KeyCapTone {
        get { self[KeyCapToneKey.self] }
        set { self[KeyCapToneKey.self] = newValue }
    }
}
