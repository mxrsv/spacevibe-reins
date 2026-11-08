import SwiftUI

/// The surface every popover shares (V5-R27, V5-R57): 272 wide, padding 12, its parts 12 apart, `bgPop` with a `hair2`
/// edge, the top-edge highlight and the pop shadow. It rises 2 pt into place in 120 ms; reduced motion and headless shots
/// show it in place (V5-R42). Draw it through `anchoredOverlay(isPresented:id:placement: .popover)` so the window's
/// `overlayHost()` places it below its anchor, above it near the bottom edge, clamped 8 inside the window.
///
///     PopoverSurface(onHover: { presence.surface($0) }, onExit: { close(refocus: true) }) {
///         PopoverSentence("Never ran in Claude Code. Added 3 weeks ago.")
///         PopoverActions { Button { … } label: { ActionLabel("Remove", glyph: .trash) } }
///     }
struct PopoverSurface<Content: View>: View {
    /// The pointer entered or left the surface: a hover popover stays open while the pointer is on it.
    var onHover: ((Bool) -> Void)?
    /// Esc inside the popover: close it and give the focus back to its anchor (V5-R37).
    var onExit: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isShotRendering) private var isShotRendering
    @State private var risen = false

    var body: some View {
        let inPlace = risen || reduceMotion || isShotRendering
        VStack(alignment: .leading, spacing: Metrics.Popover.spacing) { content }
            .padding(Metrics.Popover.padding)
            .frame(width: Metrics.Popover.width, alignment: .leading)
            .blockSurface(Palette.bgPop, edge: Palette.hair2)
            .overlayShadow(.pop)
            .environment(\.logoRing, Palette.bgPop)
            .opacity(inPlace ? 1 : 0)
            .offset(y: inPlace ? 0 : Metrics.Popover.rise)
            .onAppear { withAnimation(.easeOut(duration: Metrics.Motion.quick)) { risen = true } }
            .onHover { onHover?($0) }
            .onExitCommand { onExit?() }
            .accessibilityElement(children: .contain)
    }
}

/// A popover's head (V5-R57): the logo or glyph (20), the name (13/20 500) and a sub line (12/16 `fg2`), with the success
/// dot before it when `subIsReading`.
struct PopoverHead<Lead: View>: View {
    let name: String
    var sub: String?
    var subIsReading = false
    @ViewBuilder var lead: Lead

    var body: some View {
        HStack(spacing: Metrics.Popover.headSpacing) {
            lead
            VStack(alignment: .leading, spacing: 0) {
                Text(name).spaceVibeText(.control, tone: .primary).lineLimit(1).lineBox(.control)
                if let sub {
                    HStack(spacing: Metrics.Popover.dotSpacing) {
                        if subIsReading {
                            Circle().fill(Palette.ok).frame(width: Metrics.Popover.dotSize, height: Metrics.Popover.dotSize)
                        }
                        Text(sub).spaceVibeText(.meta, tone: .secondary).lineLimit(1).lineBox(.meta)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One plain sentence in a popover (13/20 `fg`): a warning's explanation, one line per CLI of a row's detail.
struct PopoverSentence: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .spaceVibeText(.prose, tone: .primary)
            .lineSpacing(SpaceVibeType.prose.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .lineBox(.prose)
    }
}

/// A file path under a popover's sentence (11/16 `fg3`), 8 below it rather than 12; it breaks anywhere.
struct PopoverPath: View {
    let path: String

    init(_ path: String) { self.path = path }

    var body: some View {
        Text(path)
            .spaceVibeText(.small, tone: .tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .lineBox(.small)
            .padding(.top, -Metrics.Popover.pathRise)
    }
}

/// A quiet note in a popover: a 14 pt glyph in `fg3` and 12/16 `fg2` text ("Owned by the neon plugin. Read only.").
struct PopoverNote: View {
    let glyph: ContentGlyph
    let text: String

    init(_ text: String, glyph: ContentGlyph) {
        self.text = text
        self.glyph = glyph
    }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Popover.noteSpacing) {
            SpaceVibeIcon(content: glyph, size: .inline, ink: Palette.fg3)
                .padding(.top, Metrics.Radius.edge)
            Text(text).spaceVibeText(.meta, tone: .secondary).fixedSize(horizontal: false, vertical: true).lineBox(.meta)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A popover's actions, 8 apart: 28-high buttons (`ActionButtonStyle` size `.compact`) with their key caps.
struct PopoverActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Metrics.Popover.actionSpacing) { content }
            .buttonStyle(ActionButtonStyle(size: .compact))
    }
}

/// When a hover popover opens and closes (the kit's `popover.show` and `hide`): the pointer on the anchor or keyboard focus
/// on it opens it after 150 ms; leaving both the anchor and the surface closes it after 100 ms, so the pointer can cross the
/// gap; Esc closes it at once and gives the focus back to the anchor without opening it again. A click toggles it. Pure,
/// so `PopoverPresenceTests` can drive it; the view runs the effects.
struct PopoverPresence: Equatable {
    enum Event: Equatable {
        case anchorHover(Bool)
        case surfaceHover(Bool)
        case anchorFocus(Bool)
        case activate
        case escape
    }

    enum Effect: Equatable {
        /// Nothing changes.
        case none
        /// Cancel a pending change and set `isOpen` after this delay (`settle()` then reads what the inputs want).
        case settle(after: Duration)
        /// Changed now; `refocusAnchor` gives the keyboard focus back to the anchor.
        case changed(refocusAnchor: Bool)
    }

    private(set) var isOpen = false
    private var overAnchor = false
    private var overSurface = false
    private var anchorFocused = false
    /// Set by Esc: the anchor keeps (or gets back) the focus but must not open the popover again until the focus leaves it
    /// or the pointer comes back.
    private var muted = false

    private var wanted: Bool { overAnchor || overSurface || (anchorFocused && !muted) }

    mutating func handle(_ event: Event) -> Effect {
        switch event {
        case .anchorHover(let inside): overAnchor = inside
        case .surfaceHover(let inside): overSurface = inside
        case .anchorFocus(let focused):
            anchorFocused = focused
            if !focused { muted = false }
        case .activate:
            muted = false
            isOpen.toggle()
            return .changed(refocusAnchor: false)
        case .escape:
            guard isOpen else { return .none }
            isOpen = false
            overAnchor = false
            overSurface = false
            muted = true
            return .changed(refocusAnchor: true)
        }
        if wanted == isOpen { return .settle(after: .zero) }
        return .settle(after: wanted ? Metrics.Popover.openDelay : Metrics.Popover.closeDelay)
    }

    /// After the delay: open while something still wants it, closed otherwise.
    mutating func settle() {
        isOpen = wanted
    }
}
