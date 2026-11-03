import ReinsCore
import SwiftUI

enum ReinsButtonKind {
    /// Surface fill, border. The default.
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
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            configuration.label
                .reinsText(kind == .primary ? .bodyStrong : .body)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .frame(width: kind == .icon ? Metrics.controlHeight : nil, height: Metrics.controlHeight)
                .background(shape.fill(fill))
                .overlay { outline(shape) }
                .overlay(shape.fill(Palette.hover).opacity(hovering && isEnabled && kind != .primary ? 1 : 0).allowsHitTesting(false))
                .brightness(hovering && isEnabled && kind == .primary ? 0.08 : 0)
                .contentShape(shape)
                .opacity(opacity)
                .onHover { hovering = $0 }
        }

        private var horizontalPadding: CGFloat {
            switch kind {
            case .icon: 0
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
            case .normal, .danger, .icon: Palette.surfaceRaised
            case .primary: Palette.accentSolid
            case .ghost: .clear
            case .inverse: Palette.background.opacity(0.14)
            }
        }

        private var foreground: Color {
            switch kind {
            case .normal, .icon: Palette.text
            case .primary: Palette.onAccent
            case .danger: Palette.dangerInk
            case .ghost: Palette.textSecondary
            case .inverse: Palette.background
            }
        }

        @ViewBuilder
        private func outline(_ shape: RoundedRectangle) -> some View {
            switch kind {
            case .normal, .danger, .icon:
                shape.strokeBorder(Palette.border, lineWidth: 1)
            case .primary, .inverse, .ghost:
                EmptyView()
            }
        }
    }
}

extension ButtonStyle where Self == ReinsButtonStyle {
    static func reins(_ kind: ReinsButtonKind = .normal) -> ReinsButtonStyle { ReinsButtonStyle(kind: kind) }
}

/// A small button for a row's trailing actions: revealed on hover, focus or selection (see `Row`).
/// `systemImage` alone makes a square icon button; the title is then its accessibility label and tooltip.
struct RowActionButton: View {
    let title: String
    var systemImage: String?
    var kind: ReinsButtonKind = .normal
    var iconOnly = false
    /// A CLI's dot in the icon button's corner: which CLI this action touches ("Remove from Codex").
    var badge: InventoryCLI?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if iconOnly, let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(kind == .danger ? Palette.dangerInk : Palette.text)
                    .accessibilityLabel(title)
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .overlay(alignment: .topTrailing) {
                        if let badge { CLIDot(badge, decorative: true, size: Space.s6).padding(Space.s4) }
                    }
            } else if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.reins(iconOnly ? .icon : kind))
        .help(title)
    }
}
