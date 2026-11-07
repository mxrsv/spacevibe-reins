import SwiftUI

extension View {
    /// The v5 surface of a block (V5-R5): a fill, a 1 pt edge inside the bounds and the 1 pt top-edge highlight (`hi`), on
    /// a rounded shape that also clips the content. No drop shadow; overlays add their own. Cards use `bgRaise` with `hair`.
    func blockSurface(_ fill: Color, edge: Color = Palette.hair, radius: CGFloat = Metrics.Radius.block) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: Metrics.Radius.cornerStyle)
        return background(shape.fill(fill))
            .overlay { TopEdgeHighlight(radius: radius).fill(Palette.hi).allowsHitTesting(false) }
            .overlay { shape.strokeBorder(edge, lineWidth: Metrics.Radius.edge).allowsHitTesting(false) }
            .clipShape(shape)
    }
}

/// The drop shadow under an overlay (V5-R5: overlays only; cards have none). The kit's CSS blur is twice the radius SwiftUI
/// takes, so the token's blur is halved here.
enum OverlayShadow {
    /// Popover, toast and bottom bar: `0 8 32` black 40%.
    case pop
    /// A menu: `0 8 32` black 35%.
    case menu
    /// The palette and a confirmation: `0 24 64` black 50%.
    case dialog
}

extension View {
    func overlayShadow(_ kind: OverlayShadow) -> some View {
        let (color, blur, y): (Color, CGFloat, CGFloat) = switch kind {
        case .pop: (Palette.shadowPop, Metrics.Shadow.popRadius, Metrics.Shadow.popOffset)
        case .menu: (Palette.shadowMenu, Metrics.Shadow.popRadius, Metrics.Shadow.popOffset)
        case .dialog: (Palette.shadowDialog, Metrics.Shadow.dialogRadius, Metrics.Shadow.dialogOffset)
        }
        return shadow(color: color, radius: blur / 2, y: y)
    }
}

/// The kit's `box-shadow: inset 0 1px 0 var(--hi)`: the shape inside the 1 pt edge, less the same shape moved down 1 pt.
/// A line 1 pt thick along the top that thins out round the top corners.
struct TopEdgeHighlight: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let edge = Metrics.Radius.edge
        let inner = rect.insetBy(dx: edge, dy: edge)
        let shape = RoundedRectangle(cornerRadius: max(0, radius - edge), style: Metrics.Radius.cornerStyle)
        return shape.path(in: inner).subtracting(shape.path(in: inner.offsetBy(dx: 0, dy: edge)))
    }
}
