import SwiftUI

/// A state the gallery's button sheet forces on a control so every state shows at once (DL10). Nil everywhere in the app,
/// where hover, press and focus come from the pointer and the keyboard.
enum ForcedControlState {
    case hover, pressed, focus
}

private struct ForcedControlStateKey: EnvironmentKey {
    static let defaultValue: ForcedControlState? = nil
}

private struct ControlLoadingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forcedControlState: ForcedControlState? {
        get { self[ForcedControlStateKey.self] }
        set { self[ForcedControlStateKey.self] = newValue }
    }

    /// A button that is working: its leading icon turns into a spinner and it takes no clicks (`ButtonLabel`).
    var controlLoading: Bool {
        get { self[ControlLoadingKey.self] }
        set { self[ControlLoadingKey.self] = newValue }
    }
}

extension View {
    func forcedControlState(_ state: ForcedControlState?) -> some View {
        environment(\.forcedControlState, state)
    }

    /// Marks the buttons inside as working (spec v4, Buttons: Loading).
    func controlLoading(_ loading: Bool = true) -> some View {
        environment(\.controlLoading, loading)
    }
}

/// How a raised block reads (spec v4, "Buttons: a raised block").
enum ControlLook {
    /// A neutral block: `controlFill`, the hairline, the shadow and the top highlight.
    case neutral
    /// The primary button: `accentSolid` with its own highlight, a black hairline and an accent-tinted shadow.
    case primary
    /// A chosen card button or filter chip: the accent with white content, a highlight and a hairline, no shadow.
    case chosen
    /// A chosen segment inside the sunken track: its fill (the accent, or a verdict's tone), a highlight and a shadow.
    case segment(Color)
}

/// The v4 raised block behind a control: a fill, a 0.5 pt hairline, a shadow 1 pt down with a 2 pt blur and a 1 pt
/// highlight along the top edge. Pressed, it sinks 0.5 pt (the control applies `pressedOffset`) and its shadow turns inner.
/// Disabled keeps the hairline and shadow and drops the highlight.
struct ControlBlock: View {
    var look: ControlLook = .neutral
    var cornerRadius: CGFloat = Metrics.controlRadius
    var hovered = false
    var pressed = false
    var enabled = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if pressed {
                shape.fill(fill)
                InnerShadow(shape: shape, color: innerShadow)
            } else {
                shape.fill(fill).shadow(color: dropShadow, radius: Metrics.controlShadowRadius, y: Metrics.controlShadowOffset)
                if enabled {
                    TopEdge(cornerRadius: cornerRadius)
                        .fill(highlight, style: FillStyle(eoFill: true))
                        .clipShape(shape)
                }
            }
            shape.strokeBorder(hairline, lineWidth: Metrics.controlHairlineWidth)
        }
        .allowsHitTesting(false)
    }

    private var fill: Color {
        switch look {
        case .neutral: pressed ? Palette.controlFillPressed : (hovered ? Palette.controlFillHover : Palette.controlFill)
        case .primary: pressed ? Palette.accentPressed : (hovered ? Palette.accentHover : Palette.accentSolid)
        case .chosen: Palette.accentSolid
        case .segment(let color): color
        }
    }

    private var hairline: Color {
        switch look {
        case .neutral: Palette.controlHairline
        case .primary: pressed ? .clear : Palette.accentHairline
        case .chosen: Palette.accentHairline
        case .segment: .clear
        }
    }

    private var dropShadow: Color {
        switch look {
        case .neutral: Palette.controlShadow
        case .primary: Palette.accentShadow
        case .chosen: .clear
        case .segment: Palette.chosenShadow
        }
    }

    private var innerShadow: Color {
        switch look {
        case .neutral: Palette.controlShadow
        case .primary, .chosen, .segment: Palette.chosenShadow
        }
    }

    private var highlight: Color {
        switch look {
        case .neutral: Palette.controlHighlight
        case .primary, .chosen, .segment: Palette.accentHighlight
        }
    }
}

/// The highlight band along a block's top edge: the block minus itself moved down by the band's width, filled even-odd and
/// clipped to the block, so the band follows the corners.
private struct TopEdge: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        path.addPath(Path(roundedRect: rect.offsetBy(dx: 0, dy: Metrics.controlHighlightWidth), cornerRadius: cornerRadius, style: .continuous))
        return path
    }
}

/// An inner shadow, 1 pt down with a 2 pt blur: the shape's outline in `color`, blurred, moved down and clipped to the
/// shape. The pressed block and the segmented control's sunken track draw it.
struct InnerShadow<S: Shape>: View {
    let shape: S
    let color: Color

    var body: some View {
        shape
            .stroke(color, lineWidth: Metrics.controlShadowRadius * 2)
            .blur(radius: Metrics.controlShadowRadius)
            .offset(y: Metrics.controlShadowOffset)
            .mask(shape)
            .allowsHitTesting(false)
    }
}

/// A working control's spinner: a three-quarter ring turning once every 0.8 s, 14 pt, in the current foreground style.
/// Still in headless shots, which draw one frame.
struct Spinner: View {
    @State private var turning = false
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        Circle()
            .inset(by: Metrics.spinnerStroke / 2)
            .trim(from: 0, to: 0.75)
            .stroke(style: StrokeStyle(lineWidth: Metrics.spinnerStroke))
            .frame(width: Metrics.spinnerSize, height: Metrics.spinnerSize)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                guard !isShotRendering else { return }
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { turning = true }
            }
            .accessibilityHidden(true)
    }
}

/// A button's label: an optional leading page icon and the title. While `controlLoading` is set the spinner takes the
/// icon's place, or sits over the hidden title when there is no icon, so the label and the width stay (spec v4, Loading).
struct ButtonLabel: View {
    let title: String
    var icon: PageGlyph?
    @Environment(\.controlLoading) private var loading

    init(_ title: String, icon: PageGlyph? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        if let icon {
            HStack(spacing: Space.s6) {
                if loading {
                    Spinner().frame(width: IconSize.control.points, height: IconSize.control.points)
                } else {
                    PageIcon(icon)
                }
                Text(title)
            }
        } else {
            Text(title)
                .opacity(loading ? 0 : 1)
                .overlay { if loading { Spinner() } }
        }
    }
}
