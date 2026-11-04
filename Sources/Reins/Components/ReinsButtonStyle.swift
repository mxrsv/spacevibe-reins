import ReinsCore
import SwiftUI

enum ReinsButtonKind {
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
        @Environment(\.controlGround) private var ground
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            configuration.label
                .reinsText(kind == .primary ? .bodyStrong : .body)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .frame(width: kind == .icon || kind == .plainIcon ? Metrics.controlHeight : nil, height: Metrics.controlHeight)
                .background(shape.fill(fill))
                .overlay(shape.fill(Palette.hover).opacity(hovering && isEnabled && kind != .primary ? 1 : 0).allowsHitTesting(false))
                .brightness(hovering && isEnabled && kind == .primary ? 0.08 : 0)
                .contentShape(shape)
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

    var body: some View {
        Button(action: action) {
            if iconOnly, let icon {
                PageIcon(icon)
                    .foregroundStyle(kind == .danger ? Palette.dangerInk : Palette.text)
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .overlay(alignment: .topTrailing) {
                        if let badge { CLIDot(badge, decorative: true, size: Space.s6).padding(Space.s4) }
                    }
            } else if let icon {
                HStack(spacing: Space.s6) {
                    PageIcon(icon)
                    Text(title)
                }
            } else {
                Text(title)
            }
        }
        .buttonStyle(.reins(iconOnly ? .icon : kind))
        .help(title)
        .accessibilityLabel(title)
    }
}
