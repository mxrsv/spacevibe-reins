import SwiftUI

/// Where an anchored overlay goes, given its anchor and its own size, inside the host's bounds (the window). Pure, so the
/// rules are tested without a window (`OverlayPlacementTests`).
enum OverlayPlacement: Equatable {
    /// A popover (V5-R27, V5-R57): centred under its anchor, `Metrics.Popover.offset` below it; above it instead when its
    /// bottom would come within `bottomMargin` of the bottom edge; kept `windowMargin` inside the window (the kit's
    /// `popover.place`).
    case popover
    /// A menu under its button, `Metrics.Menu.gap` below it, its leading or trailing edge on the button's.
    case menu(HorizontalEdge)

    func origin(anchor: CGRect, size: CGSize, in bounds: CGSize) -> CGPoint {
        let margin = Metrics.Popover.windowMargin
        var x: CGFloat
        var y: CGFloat
        switch self {
        case .popover:
            x = anchor.midX - size.width / 2
            y = anchor.maxY + Metrics.Popover.offset
            if y + size.height > bounds.height - Metrics.Popover.bottomMargin {
                y = anchor.minY - size.height - Metrics.Popover.offset
            }
        case .menu(let edge):
            x = edge == .leading ? anchor.minX : anchor.maxX - size.width
            y = anchor.maxY + Metrics.Menu.gap
        }
        x = max(margin, min(x, bounds.width - size.width - margin))
        y = max(margin, min(y, bounds.height - size.height - margin))
        return CGPoint(x: x, y: y)
    }
}

/// One overlay a view asks the host to draw: its anchor's bounds, where it goes and what it shows.
struct OverlayItem: Identifiable {
    let id: AnyHashable
    let anchor: Anchor<CGRect>
    let placement: OverlayPlacement
    /// A menu closes on a click anywhere else: the host lays a clear layer under it that takes that click.
    let onOutsideTap: (() -> Void)?
    let content: AnyView
}

private struct OverlayItemsKey: PreferenceKey {
    static let defaultValue: [OverlayItem] = []
    static func reduce(value: inout [OverlayItem], nextValue: () -> [OverlayItem]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Draws the anchored overlays (menus, popovers) of every view inside, above everything, so a card that clips its
    /// content (`blockSurface`) never cuts a popover off. Put it once at the window's root; the gallery puts it at its own.
    func overlayHost() -> some View {
        overlayPreferenceValue(OverlayItemsKey.self) { items in
            GeometryReader { proxy in
                ForEach(items) { item in
                    ZStack {
                        if let onOutsideTap = item.onOutsideTap {
                            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onOutsideTap).accessibilityHidden(true)
                        }
                        OverlayPlacementLayout(anchor: proxy[item.anchor], placement: item.placement) { item.content }
                    }
                }
            }
        }
        // Drawn here: a host further out must not draw them again.
        .transformPreference(OverlayItemsKey.self) { $0.removeAll() }
    }

    /// Asks the nearest `overlayHost()` to draw `content` against this view while `isPresented` is true. The caller owns
    /// the state; the content brings its own surface (`PopoverSurface`, `MenuSurface`).
    func anchoredOverlay<Content: View>(isPresented: Bool, id: some Hashable, placement: OverlayPlacement,
                                        onOutsideTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        let view = isPresented ? AnyView(content()) : nil
        let key = AnyHashable(id)
        return transformAnchorPreference(key: OverlayItemsKey.self, value: .bounds) { items, anchor in
            if let view {
                items.append(OverlayItem(id: key, anchor: anchor, placement: placement, onOutsideTap: onOutsideTap, content: view))
            }
        }
    }
}

/// Places its one subview at its ideal size where `placement` says, inside the host's bounds. A layout rather than a
/// measured `@State`, so the overlay lands in the same pass, in a window and in a headless shot alike.
private struct OverlayPlacementLayout: Layout {
    let anchor: CGRect
    let placement: OverlayPlacement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let size = view.sizeThatFits(.unspecified)
        let origin = placement.origin(anchor: anchor, size: size, in: bounds.size)
        view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(size))
    }
}
