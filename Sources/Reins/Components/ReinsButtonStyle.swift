import ReinsCore
import SwiftUI

enum ReinsButtonKind {
    /// The secondary button, and the default: a raised neutral block (spec v4, Buttons).
    case normal
    /// The raised accent block. One per surface at most.
    case primary
    /// The raised neutral block with danger text, for destructive actions.
    case danger
    /// No fill until hovered, secondary text: "+ Add to Codex" in an empty usage cell, Discard.
    case ghost
    /// On the toast, which is an inverted surface.
    case inverse
    /// Square, icon only, no fill until hovered; always give it an accessibility label.
    case icon
    /// Square, icon only, no fill until hovered: the sidebar's footer. The same look as `icon`.
    case plainIcon

    /// A raised block: the other kinds have no fill until hovered.
    var isRaised: Bool { self == .normal || self == .primary || self == .danger }
    var isSquare: Bool { self == .icon || self == .plainIcon }
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

/// Every button in the app (spec v4, "Buttons: a raised block"): 28 pt, radius 8. The raised kinds sit on a `ControlBlock`;
/// pressed sinks 0.5 pt with an inner shadow; ghost and icon buttons fill with `hover` under the pointer and `track` while
/// pressed; disabled drops the highlight and turns the text tertiary at 60%; a loading button takes no clicks and its
/// `ButtonLabel` shows a spinner. The focus ring is the app's one ring.
struct ReinsButtonStyle: ButtonStyle {
    var kind: ReinsButtonKind = .normal

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyle.Configuration
        let kind: ReinsButtonKind
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.actionsConcealed) private var concealed
        @Environment(\.forcedControlState) private var forced
        @Environment(\.controlLoading) private var loading
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            configuration.label
                .reinsText(kind == .primary ? .bodyStrong : .body)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .frame(width: kind.isSquare ? Metrics.controlHeight : nil, height: Metrics.controlHeight)
                .background { blockBackground(shape) }
                .offset(y: pressed && kind.isRaised ? Metrics.controlPressedOffset : 0)
                .contentShape(shape)
                .focusRing(forced == .focus, cornerRadius: Metrics.controlRadius)
                .opacity(opacity)
                .allowsHitTesting(!loading)
                .onHover { hovering = $0 }
        }

        private var hovered: Bool { isEnabled && !loading && (hovering || forced == .hover) }
        private var pressed: Bool { isEnabled && !loading && (configuration.isPressed || forced == .pressed) }

        @ViewBuilder
        private func blockBackground(_ shape: RoundedRectangle) -> some View {
            switch kind {
            case .normal, .danger:
                ControlBlock(look: .neutral, hovered: hovered, pressed: pressed, enabled: isEnabled)
            case .primary:
                ControlBlock(look: .primary, hovered: hovered, pressed: pressed, enabled: isEnabled)
            case .ghost, .icon, .plainIcon:
                shape.fill(pressed ? Palette.track : (hovered ? Palette.hover : .clear))
            case .inverse:
                shape.fill(Palette.background.opacity(hovered ? 0.22 : 0.14))
            }
        }

        private var horizontalPadding: CGFloat {
            switch kind {
            case .icon, .plainIcon: 0
            case .ghost: Space.s8
            default: Space.s12
            }
        }

        private var opacity: Double {
            if !isEnabled { return Metrics.disabledOpacity }
            // A hidden row action reveals itself when it takes keyboard focus.
            if concealed && !isFocused && !hovering && forced == nil { return 0 }
            return 1
        }

        private var foreground: Color {
            if !isEnabled && kind != .primary && kind != .inverse { return Palette.textTertiary }
            switch kind {
            case .normal: return Palette.text
            case .primary: return Palette.onAccent
            case .danger: return Palette.dangerInk
            case .ghost: return Palette.textSecondary
            case .icon, .plainIcon: return hovered ? Palette.text : Palette.textSecondary
            case .inverse: return Palette.background
            }
        }
    }
}

extension ButtonStyle where Self == ReinsButtonStyle {
    static func reins(_ kind: ReinsButtonKind = .normal) -> ReinsButtonStyle { ReinsButtonStyle(kind: kind) }
}

/// A small button for a row's trailing actions: revealed on hover, focus or selection (see `Row`).
/// `iconOnly` with an `icon` makes a square icon button; the title is then its accessibility label and tooltip.
struct RowActionButton: View {
    let title: String
    var icon: PageGlyph?
    var kind: ReinsButtonKind = .normal
    var iconOnly = false
    /// A CLI's dot in the icon button's corner: which CLI this action touches ("Remove from Codex").
    var badge: InventoryCLI?
    let action: () -> Void

    @Environment(\.controlLoading) private var loading

    var body: some View {
        Button(action: action) {
            if iconOnly, let icon {
                Group {
                    if loading { Spinner() } else { PageIcon(icon) }
                }
                .foregroundStyle(kind == .danger ? Palette.dangerInk : Palette.text)
                .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                .overlay(alignment: .topTrailing) {
                    if let badge { CLIDot(badge, decorative: true, size: Space.s6).padding(Space.s4) }
                }
            } else {
                ButtonLabel(title, icon: icon)
            }
        }
        .buttonStyle(.reins(iconOnly ? .icon : kind))
        .help(title)
        .accessibilityLabel(title)
    }
}
