import SwiftUI

enum SpaceVibeButtonKind {
    /// Filled, no outline: `surface` on the well, `surfaceRaised` inside a card. The default.
    case normal
    /// Solid accent. One per surface at most.
    case primary
    /// Normal with danger text, for destructive actions.
    case danger
    /// No fill and no outline until hovered, secondary text: "+ Add to Codex" in an empty usage cell.
    case ghost
    /// On the toast, which is an inverted surface.
    case inverse
    /// Square, icon only; always give it an accessibility label.
    case icon
    /// Square, icon only, no fill until hovered: the sidebar's theme toggle.
    case plainIcon
}

/// Row actions are hidden until the row is hovered, focused or selected. `Row` sets this for its `actions` slot.
private struct ActionsConcealedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var actionsConcealed: Bool {
        get { self[ActionsConcealedKey.self] }
        set { self[ActionsConcealedKey.self] = newValue }
    }
}

struct SpaceVibeButtonStyle: ButtonStyle {
    var kind: SpaceVibeButtonKind = .normal

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyle.Configuration
        let kind: SpaceVibeButtonKind
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.actionsConcealed) private var concealed
        @Environment(\.controlGround) private var ground
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            configuration.label
                .spaceVibeText(kind == .primary ? .bodyStrong : .body)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .frame(width: kind == .icon || kind == .plainIcon ? Metrics.controlHeight : nil, height: Metrics.controlHeight)
                .background(shape.fill(fill))
                .overlay(shape.fill(Palette.hover).opacity(hovering && isEnabled && kind != .primary ? 1 : 0).allowsHitTesting(false))
                .brightness(hovering && isEnabled && kind == .primary ? 0.08 : 0)
                .contentShape(shape)
                .pointerCursor()
                .opacity(opacity)
                .onHover { hovering = $0 }
        }

        private var horizontalPadding: CGFloat {
            switch kind {
            case .icon, .plainIcon: 0
            case .ghost: Space.s8
            default: Space.s12
            }
        }

        private var opacity: Double {
            if !isEnabled { return 0.45 }
            // A hidden row action reveals itself when it takes keyboard focus.
            if concealed && !isFocused && !hovering { return 0 }
            return configuration.isPressed ? 0.8 : 1
        }

        private var fill: Color {
            switch kind {
            case .normal, .danger, .icon: ground.fill
            case .primary: Palette.accentSolid
            case .ghost, .plainIcon: .clear
            case .inverse: Palette.background.opacity(0.14)
            }
        }

        private var foreground: Color {
            switch kind {
            case .normal, .icon: Palette.text
            case .primary: Palette.onAccent
            case .danger: Palette.dangerInk
            case .ghost: Palette.textSecondary
            case .plainIcon: hovering ? Palette.text : Palette.textSecondary
            case .inverse: Palette.background
            }
        }
    }
}

extension ButtonStyle where Self == SpaceVibeButtonStyle {
    static func spaceVibe(_ kind: SpaceVibeButtonKind = .normal) -> SpaceVibeButtonStyle { SpaceVibeButtonStyle(kind: kind) }
}

/// A small button for a row's trailing actions: revealed on hover, focus or selection (see `Row`).
/// `iconOnly` with an `icon` makes a square icon button; the title is then its accessibility label and tooltip.
struct RowActionButton: View {
    let title: String
    var icon: SpaceVibeGlyph?
    var kind: SpaceVibeButtonKind = .normal
    var iconOnly = false
    /// A CLI's dot in the icon button's corner: which CLI this action touches ("Remove from Codex").
    var badge: InventoryCLI?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if iconOnly, let icon {
                SpaceVibeIcon(icon)
                    .foregroundStyle(kind == .danger ? Palette.dangerInk : Palette.text)
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .overlay(alignment: .topTrailing) {
                        if let badge { CLIDot(badge, decorative: true, size: Space.s6).padding(Space.s4) }
                    }
            } else if let icon {
                HStack(spacing: Space.s6) {
                    SpaceVibeIcon(icon)
                    Text(title)
                }
            } else {
                Text(title)
            }
        }
        .buttonStyle(.spaceVibe(iconOnly ? .icon : kind))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The v5 buttons (spec, "Components": buttons with an optional key cap). Only the v5 build uses them; the kinds above
/// stay for the screens not yet rebuilt until the cut-over (X1).
enum ActionButtonKind {
    /// `bgRaise` with a `hair2` edge and the top-edge highlight; hovered or focused `sel` with an `fg4` edge.
    case normal
    /// The solid accent (`accentSolid`), white text. One per surface at most.
    case primary
    /// Normal at rest; hovered, the edge turns `bad` and the text `badText`.
    case danger
    /// The solid danger fill (`badSolid`), white text: `Stop session` in the Stop confirmation (V5-R59).
    case solidDanger
    /// A borderless 28 square around a glyph (the kit's `ibtn`): `Refresh` in a card header. Give it an accessibility label.
    case icon

    var isSolid: Bool { self == .primary || self == .solidDanger }
}

/// The v5 button sizes (spec, "Rhythm and sizes": buttons).
enum ActionButtonSize {
    /// 32 high, 13 pt: the Skills pane, the Answer card, the Stop confirmation (as the mock draws it).
    case regular
    /// 28 high, 12 pt, 10 before the label: a popover, a card header.
    case compact
    /// 28 high, 12 pt, 12 before the label: the bottom bar.
    case bar

    var height: CGFloat { self == .regular ? Metrics.ActionButton.height : Metrics.ActionButton.compactHeight }
    var leading: CGFloat { self == .compact ? Metrics.ActionButton.compactLeading : Metrics.ActionButton.leading }
    var type: SpaceVibeType { self == .regular ? .control : .metaLabel }
}

/// The v5 button: radius 6, padding 0 8 0 12 (`compact` 0 8 0 10), every state one fill (D57: focus is a fill, never a
/// ring); pressed it moves down half a point; disabled at 45%. The label is usually an `ActionLabel`.
///
///     Button { remove() } label: { ActionLabel("Remove", glyph: .trash, key: "R") }
///         .buttonStyle(ActionButtonStyle(kind: .danger))
struct ActionButtonStyle: ButtonStyle {
    var kind: ActionButtonKind = .normal
    var size: ActionButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        ActionButton(configuration: configuration, kind: kind, size: size)
    }

    private struct ActionButton: View {
        let configuration: ButtonStyle.Configuration
        let kind: ActionButtonKind
        let size: ActionButtonSize
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.specimenInteraction) private var specimen
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let hovered = (hovering || specimen.contains(.hover)) && isEnabled
            let focused = isFocused || specimen.contains(.focus)
            let pressed = (configuration.isPressed || specimen.contains(.press)) && isEnabled
            let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
            configuration.label
                .spaceVibeText(size.type)
                .foregroundStyle(foreground(hovered: hovered))
                .lineLimit(1)
                .environment(\.keyCapTone, kind.isSolid ? .onSolid : .plain)
                .environment(\.actionButtonSize, size)
                .padding(.leading, kind == .icon ? 0 : size.leading)
                .padding(.trailing, kind == .icon ? 0 : Metrics.ActionButton.trailing)
                .frame(width: kind == .icon ? Metrics.ActionButton.iconSide : nil, height: kind == .icon ? Metrics.ActionButton.iconSide : size.height)
                .background(shape.fill(fill(hovered: hovered, focused: focused, pressed: pressed)))
                .brightness(kind.isSolid && (hovered || focused) ? Metrics.ActionButton.solidHoverBrightness : 0)
                .focusFill(focused, cornerRadius: Metrics.Radius.control, onSolid: kind.isSolid)
                .overlay {
                    if kind != .icon {
                        TopEdgeHighlight(radius: Metrics.Radius.control).fill(kind.isSolid ? Palette.hiOnSolid : Palette.hi).allowsHitTesting(false)
                    }
                }
                .overlay {
                    if let edge = edge(hovered: hovered, focused: focused) {
                        shape.strokeBorder(edge, lineWidth: Metrics.Radius.edge).allowsHitTesting(false)
                    }
                }
                .contentShape(shape)
                .pointerCursor()
                .offset(y: pressed ? Metrics.ActionButton.pressOffset : 0)
                .opacity(isEnabled ? 1 : Metrics.ActionButton.disabledOpacity)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovered)
        }

        private func fill(hovered: Bool, focused: Bool, pressed: Bool) -> Color {
            switch kind {
            case .primary: return Palette.accentSolid
            case .solidDanger: return Palette.badSolid
            case .icon:
                if pressed || focused { return Palette.sel }
                return hovered ? Palette.hover : .clear
            case .normal, .danger:
                // The kit replaces the raised fill with the translucent one, so a hovered button shows its ground.
                if pressed { return Palette.hover }
                return hovered || focused ? Palette.sel : Palette.bgRaise
            }
        }

        private func edge(hovered: Bool, focused: Bool) -> Color? {
            switch kind {
            case .primary, .solidDanger, .icon: return nil
            case .danger where hovered: return Palette.bad
            case .normal, .danger: return hovered || focused ? Palette.fg4 : Palette.hair2
            }
        }

        private func foreground(hovered: Bool) -> Color {
            switch kind {
            case .primary, .solidDanger: Palette.onAccent
            case .danger: hovered ? Palette.badText : Palette.fg
            case .normal: Palette.fg
            case .icon: hovered ? Palette.fg : Palette.fg2
            }
        }
    }
}

/// A v5 button's label: an optional 16 pt glyph, the title, an optional key cap, 8 apart (a popover's button puts 2 more
/// before the cap).
struct ActionLabel: View {
    let title: String
    var glyph: ContentGlyph?
    var key: String?

    @Environment(\.actionButtonSize) private var size

    init(_ title: String, glyph: ContentGlyph? = nil, key: String? = nil) {
        self.title = title
        self.glyph = glyph
        self.key = key
    }

    var body: some View {
        HStack(spacing: Metrics.ActionButton.spacing) {
            if let glyph { SpaceVibeIcon(content: glyph) }
            Text(title)
            if let key {
                KeyCap(key).padding(.leading, size == .compact ? Metrics.ActionButton.popoverKeyExtra : 0)
            }
        }
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct ActionButtonSizeKey: EnvironmentKey {
    static let defaultValue = ActionButtonSize.regular
}

extension EnvironmentValues {
    /// Set by `ActionButtonStyle` for its label.
    var actionButtonSize: ActionButtonSize {
        get { self[ActionButtonSizeKey.self] }
        set { self[ActionButtonSizeKey.self] = newValue }
    }
}
