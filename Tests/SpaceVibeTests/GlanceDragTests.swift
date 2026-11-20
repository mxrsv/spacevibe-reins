import CoreGraphics
import Foundation
import Testing
@testable import SpaceVibe

/// Dragging the glance widget between drop slots (spec `docs/specs/2026-11-19-session-glance-widget.md`, GW13, GW-R6,
/// GW-R7): a short press stays a click, a longer move drags, the highlighted slot follows the pointer across screens, and
/// the release saves that slot. No window: the panel and the controller only feed these types.
@MainActor
@Suite("Glance drag", .fixtureCLIs)
struct GlanceDragTests {
    /// The main screen (menu bar and Dock taken out) and a larger one to its right, bottoms aligned.
    private let main = GlanceScreen(id: GlanceScreenID(displayID: 1, name: "Built-in Retina Display"),
                                    visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
    private let studio = GlanceScreen(id: GlanceScreenID(displayID: 7, name: "Studio Display"),
                                      visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
    private let sizes = GlanceStripSizes(horizontal: CGSize(width: 120, height: 30), vertical: CGSize(width: 30, height: 120))

    private func session(screens: [GlanceScreen]? = nil) -> GlanceDragSession {
        // Grabbed 10 in from the strip's left edge and 12 up from its bottom, in the main screen's bottom-right slot.
        GlanceDragSession(screens: screens ?? [main, studio], sizes: sizes, pointer: CGPoint(x: 1318, y: 94),
                          stripFrame: CGRect(x: 1308, y: 82, width: 120, height: 30))
    }

    /// A fresh suite and its name; each test removes it with `defer`. The name is an absolute path, so the suite's plist
    /// lives in the temporary folder: a plain name leaves a file in `~/Library/Preferences` even after the removal.
    private func throwawayDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-tests-\(UUID().uuidString)").path
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("a release before the threshold is a click, given the held press; a move past it is a drag the content never sees")
    func clickOrDrag() {
        let start = CGPoint(x: 100, y: 100)
        var click = GlancePointerTracker()
        #expect(click.down(at: start) == .hold)
        #expect(click.dragged(to: CGPoint(x: 102, y: 101)) == .hold)
        #expect(click.dragged(to: CGPoint(x: 103, y: 102)) == .hold)
        #expect(!click.isDragging)
        #expect(click.up(at: CGPoint(x: 103, y: 102)) == .click)

        var drag = GlancePointerTracker()
        #expect(drag.down(at: start) == .hold)
        #expect(drag.dragged(to: CGPoint(x: 101, y: 100)) == .hold)
        #expect(drag.dragged(to: CGPoint(x: 104, y: 100)) == .beginDrag(from: start, to: CGPoint(x: 104, y: 100)))
        #expect(drag.isDragging)
        // Once dragging, coming back near the start stays a drag.
        #expect(drag.dragged(to: CGPoint(x: 100, y: 101)) == .drag(to: CGPoint(x: 100, y: 101)))
        #expect(drag.dragged(to: CGPoint(x: 900, y: 500)) == .drag(to: CGPoint(x: 900, y: 500)))
        #expect(drag.up(at: CGPoint(x: 900, y: 500)) == .drop(at: CGPoint(x: 900, y: 500)))
        #expect(!drag.isDragging)

        // After the release, the next press decides afresh.
        #expect(drag.down(at: start) == .hold)
        #expect(drag.up(at: start) == .click)
    }

    @Test("the threshold is a distance, inclusive, in any direction")
    func threshold() {
        let start = CGPoint(x: 10, y: 10)
        let limit = Metrics.Glance.dragThreshold
        #expect(!GlancePointerTracker.passesThreshold(from: start, to: start))
        #expect(!GlancePointerTracker.passesThreshold(from: start, to: CGPoint(x: 10 + limit - 0.1, y: 10)))
        #expect(GlancePointerTracker.passesThreshold(from: start, to: CGPoint(x: 10, y: 10 - limit)))
        // A diagonal move counts by its length: 0.75 of the limit on each axis is past it, 0.7 is not.
        #expect(GlancePointerTracker.passesThreshold(from: start, to: CGPoint(x: 10 + limit * 0.75, y: 10 + limit * 0.75)))
        #expect(!GlancePointerTracker.passesThreshold(from: start, to: CGPoint(x: 10 + limit * 0.7, y: 10 - limit * 0.7)))
    }

    @Test("events with no press on the strip pass through to its content")
    func noPress() {
        var tracker = GlancePointerTracker()
        #expect(tracker.dragged(to: CGPoint(x: 5, y: 5)) == .pass)
        #expect(tracker.up(at: CGPoint(x: 5, y: 5)) == .pass)
    }

    @Test("the strip keeps the point it was grabbed at under the pointer")
    func follows() {
        let drag = session()
        #expect(drag.stripOrigin(at: CGPoint(x: 1318, y: 94)) == CGPoint(x: 1308, y: 82))
        #expect(drag.stripOrigin(at: CGPoint(x: 2000, y: 600)) == CGPoint(x: 1990, y: 588))
    }

    @Test("the highlighted slot follows the pointer across two screens, one target at a time")
    func highlightAcrossScreens() {
        let drag = session()
        let path: [(CGPoint, GlanceScreenID, GlanceSlot)] = [
            (CGPoint(x: 1318, y: 94), main.id, .bottomRight),
            (CGPoint(x: 800, y: 400), main.id, .bottomCenter),
            (CGPoint(x: 700, y: 840), main.id, .topCenter),
            (CGPoint(x: 1400, y: 850), main.id, .topRight),
            // Over the edge onto the studio display, at its left middle.
            (CGPoint(x: 1480, y: 520), studio.id, .leftMiddle),
            (CGPoint(x: 3300, y: 1000), studio.id, .topRight),
            (CGPoint(x: 3200, y: 530), studio.id, .rightMiddle),
            // Back to the main screen's bottom left.
            (CGPoint(x: 40, y: 90), main.id, .bottomLeft),
        ]
        for (pointer, screen, slot) in path {
            let target = drag.target(at: pointer)
            #expect(target?.screen.id == screen && target?.slot == slot, "at \(pointer)")
            let lit = [main, studio].flatMap { shown in
                drag.outlines(on: shown, target: target).filter(\.isTarget).map { (shown.id, $0.slot) }
            }
            #expect(lit.count == 1 && lit.first?.0 == screen && lit.first?.1 == slot, "at \(pointer)")
        }
    }

    @Test("each screen draws its 8 slots, sized like the widget in that slot's axis, in the overlay's top-left coordinates")
    func outlines() {
        let drag = session()
        let outlines = drag.outlines(on: studio, target: nil)
        #expect(outlines.map(\.slot) == GlanceSlot.allCases)
        #expect(outlines.allSatisfy { !$0.isTarget })
        let margin = GlanceLayout.margin
        let frame = { (slot: GlanceSlot) in outlines.first { $0.slot == slot }?.frame }
        #expect(frame(.topLeft) == CGRect(x: margin, y: margin, width: 120, height: 30))
        #expect(frame(.bottomRight) == CGRect(x: 1920 - margin - 120, y: 1055 - margin - 30, width: 120, height: 30))
        #expect(frame(.leftMiddle) == CGRect(x: margin, y: (1055 - 120) / 2, width: 30, height: 120))
        #expect(frame(.rightMiddle) == CGRect(x: 1920 - margin - 30, y: (1055 - 120) / 2, width: 30, height: 120))
        for outline in outlines {
            #expect(CGRect(origin: .zero, size: studio.visibleFrame.size).contains(outline.frame), "\(outline.slot)")
        }
    }

    @Test("the release saves the nearest slot on its screen, and the next launch reads it back")
    func releaseSaves() {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlancePreferences(defaults: defaults)
        #expect(preferences.placement == nil)

        let placed = session().drop(at: CGPoint(x: 1490, y: 540), into: preferences)
        let expected = GlancePlacement(screen: studio.id, slot: .leftMiddle)
        #expect(placed?.saved == expected)
        #expect(preferences.placement == expected)
        #expect(GlancePreferences(defaults: defaults).placement == expected)

        session().drop(at: CGPoint(x: 20, y: 860), into: preferences)
        #expect(GlancePreferences(defaults: defaults).placement == GlancePlacement(screen: main.id, slot: .topLeft))
    }

    @Test("with no screen the release saves nothing")
    func releaseWithoutScreen() {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlancePreferences(defaults: defaults)
        let before = GlancePlacement(screen: main.id, slot: .topCenter)
        preferences.placement = before
        #expect(session(screens: []).drop(at: CGPoint(x: 10, y: 10), into: preferences) == nil)
        #expect(preferences.placement == before)
    }

    @Test("the snap starts at the release, ends in the slot, and never passes it on the way")
    func snapPath() {
        let start = CGPoint(x: 900, y: 500), end = CGPoint(x: 12, y: 840)
        #expect(GlanceSnap.origin(from: start, to: end, progress: 0) == start)
        #expect(GlanceSnap.origin(from: start, to: end, progress: 1) == end)
        #expect(GlanceSnap.origin(from: start, to: end, progress: 1.5) == end)
        #expect(GlanceSnap.origin(from: start, to: end, progress: -0.5) == start)
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { GlanceSnap.origin(from: start, to: end, progress: $0) }
        for (earlier, later) in zip(steps, steps.dropFirst()) {
            #expect(later.x <= earlier.x && later.y >= earlier.y)
            #expect(later.x >= end.x && later.y <= end.y)
        }
        // Eased out: past halfway by a quarter of the time.
        #expect(GlanceSnap.origin(from: start, to: end, progress: 0.25).x < (start.x + end.x) / 2)
    }
}
