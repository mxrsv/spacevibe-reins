import Foundation
import Testing
@testable import SpaceVibe

/// V5-R27 and V5-R57: where a popover or a menu lands (the kit's `popover.place`), and when a hover popover opens and
/// closes (the kit's `popover.show` and `hide`, Esc returning the focus to the anchor).
@Suite("Overlay placement and hover popovers (V5-R27, V5-R57)")
struct OverlayPlacementTests {
    static let window = CGSize(width: 1440, height: 900)
    static let popover = CGSize(width: 272, height: 120)

    @Test("a popover sits 6 below its anchor, centred on it")
    func belowAndCentred() {
        let anchor = CGRect(x: 600, y: 200, width: 24, height: 24)
        let origin = OverlayPlacement.popover.origin(anchor: anchor, size: Self.popover, in: Self.window)
        #expect(origin == CGPoint(x: 612 - 136, y: 230))
    }

    @Test("near the bottom edge it goes above its anchor, 6 above it")
    func aboveNearTheBottom() {
        let anchor = CGRect(x: 600, y: 760, width: 24, height: 24)
        let origin = OverlayPlacement.popover.origin(anchor: anchor, size: Self.popover, in: Self.window)
        #expect(origin.y == CGFloat(634), "760 - 120 - 6")
        // 40 from the bottom is the line: a popover that would end 40 above the bottom still goes below.
        let edge = CGRect(x: 600, y: 900 - 40 - 120 - 6 - 24, width: 24, height: 24)
        #expect(OverlayPlacement.popover.origin(anchor: edge, size: Self.popover, in: Self.window).y == edge.maxY + 6)
    }

    @Test("it is kept 8 inside the window at either side")
    func clampedEightInside() {
        let right = CGRect(x: 1420, y: 100, width: 24, height: 24)
        #expect(OverlayPlacement.popover.origin(anchor: right, size: Self.popover, in: Self.window).x == CGFloat(1160), "1440 - 272 - 8")
        let left = CGRect(x: 2, y: 100, width: 24, height: 24)
        #expect(OverlayPlacement.popover.origin(anchor: left, size: Self.popover, in: Self.window).x == CGFloat(8))
    }

    @Test("a menu opens 4 below its button, trailing edges aligned, or leading edges for a leading menu")
    func menuUnderItsButton() {
        let button = CGRect(x: 1200, y: 14, width: 80, height: 32)
        let menu = CGSize(width: 208, height: 180)
        #expect(OverlayPlacement.menu(.trailing).origin(anchor: button, size: menu, in: Self.window) == CGPoint(x: 1280 - 208, y: 50))
        #expect(OverlayPlacement.menu(.leading).origin(anchor: button, size: menu, in: Self.window) == CGPoint(x: 1200, y: 50))
    }

    @Test("the pointer opens a hover popover after 150 ms and leaving closes it after 100 ms")
    func hoverDelays() {
        var presence = PopoverPresence()
        #expect(presence.handle(.anchorHover(true)) == .settle(after: .milliseconds(150)))
        presence.settle()
        #expect(presence.isOpen)
        #expect(presence.handle(.anchorHover(false)) == .settle(after: .milliseconds(100)))
        // The pointer reaches the surface before the delay ends: the close is cancelled and the popover stays.
        #expect(presence.handle(.surfaceHover(true)) == .settle(after: .zero))
        presence.settle()
        #expect(presence.isOpen)
        _ = presence.handle(.surfaceHover(false))
        presence.settle()
        #expect(!presence.isOpen)
    }

    @Test("keyboard focus on the anchor opens it; Esc closes it at once and the focus coming back does not reopen it")
    func escapeReturnsFocus() {
        var presence = PopoverPresence()
        #expect(presence.handle(.anchorFocus(true)) == .settle(after: .milliseconds(150)))
        presence.settle()
        #expect(presence.isOpen)
        #expect(presence.handle(.escape) == .changed(refocusAnchor: true))
        #expect(!presence.isOpen)
        // The anchor has the focus again (or still): no reopen while it stays there.
        #expect(presence.handle(.anchorFocus(true)) == .settle(after: .zero))
        presence.settle()
        #expect(!presence.isOpen)
        // The focus leaves and comes back: it opens again.
        _ = presence.handle(.anchorFocus(false))
        _ = presence.handle(.anchorFocus(true))
        presence.settle()
        #expect(presence.isOpen)
        #expect(PopoverPresence().escapeWhenClosed() == .none)
    }

    @Test("a click toggles it at once")
    func clickToggles() {
        var presence = PopoverPresence()
        #expect(presence.handle(.activate) == .changed(refocusAnchor: false))
        #expect(presence.isOpen)
        _ = presence.handle(.activate)
        #expect(!presence.isOpen)
    }

    @Test("moving keyboard focus from the anchor into the popover cancels closing, in either notification order")
    func focusInsidePopoverKeepsItOpen() {
        for surfaceFirst in [false, true] {
            var presence = PopoverPresence()
            _ = presence.handle(.anchorFocus(true))
            presence.settle()
            if surfaceFirst { _ = presence.handle(.surfaceFocus(true)) }
            _ = presence.handle(.anchorFocus(false))
            if !surfaceFirst { _ = presence.handle(.surfaceFocus(true)) }
            presence.settle()
            #expect(presence.isOpen)

            // A gap between two descendant buttons must cancel closing too.
            #expect(presence.handle(.surfaceFocus(false)) == .settle(after: .milliseconds(100)))
            #expect(presence.handle(.surfaceFocus(true)) == .settle(after: .zero))
            presence.settle()
            #expect(presence.isOpen)

            _ = presence.handle(.surfaceFocus(false))
            presence.settle()
            #expect(!presence.isOpen)
        }
    }

    @Test("Esc from a popover action closes it and late focus notifications cannot reopen it")
    func escapeFromPopoverAction() {
        var presence = PopoverPresence()
        _ = presence.handle(.activate)
        _ = presence.handle(.surfaceFocus(true))
        #expect(presence.handle(.escape) == .changed(refocusAnchor: true))
        _ = presence.handle(.surfaceFocus(true))
        _ = presence.handle(.anchorFocus(true))
        presence.settle()
        #expect(!presence.isOpen)
        _ = presence.handle(.surfaceFocus(false))
        _ = presence.handle(.anchorFocus(false))
        _ = presence.handle(.anchorFocus(true))
        presence.settle()
        #expect(presence.isOpen)
    }
}

private extension PopoverPresence {
    func escapeWhenClosed() -> Effect {
        var copy = self
        return copy.handle(.escape)
    }
}
