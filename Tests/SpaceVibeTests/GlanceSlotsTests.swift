import CoreGraphics
import Foundation
import Testing
@testable import SpaceVibe

/// GW13, GW14, GW16, GW-R7: the glance widget's 8 slots, its list toward the centre, the nearest slot on drop and the saved
/// placement. AppKit coordinates: origin bottom left, so the menu bar trims the top of the visible frame and the Dock the
/// bottom.
@Suite("Glance slots (GW13, GW14, GW16, GW-R7)", .fixtureCLIs)
struct GlanceSlotsTests {
    /// A 1440 x 900 main screen: 24 of menu bar on top, 70 of Dock at the bottom.
    static let main = GlanceScreen(
        id: GlanceScreenID(displayID: 1, name: "Built-in Retina Display"),
        visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 806))
    /// A 1920 x 1080 screen to the right of the main one: its own menu bar, no Dock.
    static let second = GlanceScreen(
        id: GlanceScreenID(displayID: 2, name: "Studio Display"),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1056))

    static let rowSize = CGSize(width: 120, height: 30)
    static let columnSize = CGSize(width: 30, height: 120)
    static let listSize = CGSize(width: 360, height: 240)

    static func widgetSize(_ slot: GlanceSlot) -> CGSize { slot.axis == .vertical ? columnSize : rowSize }

    static func widgetFrame(_ slot: GlanceSlot, on screen: GlanceScreen = main) -> CGRect {
        slot.frame(for: widgetSize(slot), in: screen.visibleFrame)
    }

    @Test("the margin and the list gap come from the spacing scale")
    func constants() {
        #expect(GlanceLayout.margin == Space.s12)
        #expect(GlanceLayout.listGap == Space.s6)
    }

    // The inner frame is the visible frame less 12: x 12...1428, y 82...864, centre (720, 473).
    @Test("all 8 slots sit 12 inside the visible frame, clear of the menu bar and the Dock",
          arguments: [
              (GlanceSlot.topLeft, CGPoint(x: 12, y: 864), CGRect(x: 12, y: 834, width: 120, height: 30)),
              (.topCenter, CGPoint(x: 720, y: 864), CGRect(x: 660, y: 834, width: 120, height: 30)),
              (.topRight, CGPoint(x: 1428, y: 864), CGRect(x: 1308, y: 834, width: 120, height: 30)),
              (.leftMiddle, CGPoint(x: 12, y: 473), CGRect(x: 12, y: 413, width: 30, height: 120)),
              (.rightMiddle, CGPoint(x: 1428, y: 473), CGRect(x: 1398, y: 413, width: 30, height: 120)),
              (.bottomLeft, CGPoint(x: 12, y: 82), CGRect(x: 12, y: 82, width: 120, height: 30)),
              (.bottomCenter, CGPoint(x: 720, y: 82), CGRect(x: 660, y: 82, width: 120, height: 30)),
              (.bottomRight, CGPoint(x: 1428, y: 82), CGRect(x: 1308, y: 82, width: 120, height: 30)),
          ])
    func slotFrames(slot: GlanceSlot, anchor: CGPoint, frame: CGRect) {
        let visible = Self.main.visibleFrame
        #expect(slot.anchor(in: visible) == anchor)
        let widget = Self.widgetFrame(slot)
        #expect(widget == frame)
        #expect(visible.contains(widget))
        #expect(widget.maxY <= visible.maxY - GlanceLayout.margin, "under the menu bar")
        #expect(widget.minY >= visible.minY + GlanceLayout.margin, "over the Dock")
    }

    @Test("there are exactly 8 slots, each on its own spot")
    func eightDistinctSlots() {
        #expect(GlanceSlot.allCases.count == 8)
        let frames = Set(GlanceSlot.allCases.map { "\(Self.widgetFrame($0))" })
        #expect(frames.count == 8)
    }

    @Test("left and right edge middles stack vertically, every other slot is a row (GW14)")
    func axisPerSlot() {
        for slot in GlanceSlot.allCases {
            let vertical: Set<GlanceSlot> = [.leftMiddle, .rightMiddle]
            #expect(slot.axis == (vertical.contains(slot) ? .vertical : .horizontal), "\(slot)")
        }
    }

    @Test("the list opens toward the centre, 6 from the widget, on the widget's outer side",
          arguments: [
              (GlanceSlot.topLeft, GlanceListDirection.down, CGRect(x: 12, y: 588, width: 360, height: 240)),
              (.topCenter, .down, CGRect(x: 540, y: 588, width: 360, height: 240)),
              (.topRight, .down, CGRect(x: 1068, y: 588, width: 360, height: 240)),
              (.leftMiddle, .right, CGRect(x: 48, y: 353, width: 360, height: 240)),
              (.rightMiddle, .left, CGRect(x: 1032, y: 353, width: 360, height: 240)),
              (.bottomLeft, .up, CGRect(x: 12, y: 118, width: 360, height: 240)),
              (.bottomCenter, .up, CGRect(x: 540, y: 118, width: 360, height: 240)),
              (.bottomRight, .up, CGRect(x: 1068, y: 118, width: 360, height: 240)),
          ])
    func listDirection(slot: GlanceSlot, direction: GlanceListDirection, frame: CGRect) {
        #expect(slot.listDirection == direction)
        let list = slot.listFrame(for: Self.listSize, widgetFrame: Self.widgetFrame(slot), in: Self.main.visibleFrame)
        #expect(list == frame)
        let centre = CGPoint(x: Self.main.visibleFrame.midX, y: Self.main.visibleFrame.midY)
        let widget = Self.widgetFrame(slot)
        let toward = hypot(list.midX - centre.x, list.midY - centre.y) < hypot(widget.midX - centre.x, widget.midY - centre.y)
        #expect(toward, "the list's centre is nearer the screen centre than the widget's")
    }

    @Test("in every slot a list of any size stays inside the margin, clear of the widget, on the centre side",
          arguments: GlanceSlot.allCases)
    func listClamped(slot: GlanceSlot) {
        let visible = Self.main.visibleFrame
        let inner = visible.insetBy(dx: GlanceLayout.margin, dy: GlanceLayout.margin)
        let widget = Self.widgetFrame(slot)
        let gap = GlanceLayout.listGap
        let sizes = [Self.listSize, CGSize(width: 2000, height: 2000), CGSize(width: 1416, height: 782), CGSize(width: 1, height: 1)]
        for size in sizes {
            let list = slot.listFrame(for: size, widgetFrame: widget, in: visible)
            #expect(inner.contains(list), "\(slot) \(size): \(list) leaves \(inner)")
            #expect(!list.intersects(widget), "\(slot) \(size): \(list) covers the widget \(widget)")
            #expect(list.width <= size.width && list.height <= size.height, "never larger than asked")
            #expect(list.width > 0 && list.height > 0)
            switch slot.listDirection {
            case .down: #expect(list.maxY == widget.minY - gap)
            case .up: #expect(list.minY == widget.maxY + gap)
            case .right: #expect(list.minX == widget.maxX + gap)
            case .left: #expect(list.maxX == widget.minX - gap)
            }
        }
    }

    @Test("a list too big for the screen is cut to the room on its side and to the screen across")
    func listCutToTheRoom() {
        let visible = Self.main.visibleFrame
        let huge = CGSize(width: 2000, height: 2000)
        let top = GlanceSlot.topCenter.listFrame(for: huge, widgetFrame: Self.widgetFrame(.topCenter), in: visible)
        #expect(top == CGRect(x: 12, y: 82, width: 1416, height: 746), "834 - 6 - 82 high, the inner width wide")
        let left = GlanceSlot.leftMiddle.listFrame(for: huge, widgetFrame: Self.widgetFrame(.leftMiddle), in: visible)
        #expect(left == CGRect(x: 48, y: 82, width: 1380, height: 782), "1428 - 48 wide, the inner height high")
    }

    @Test("a list that would cross the margin across its opening side slides back inside")
    func listSlidesInside() {
        let visible = Self.main.visibleFrame
        // A centred list under a widget pushed near the left edge: centred it would start at -100.
        let nearLeft = CGRect(x: 20, y: 834, width: 120, height: 30)
        let list = GlanceSlot.topCenter.listFrame(for: Self.listSize, widgetFrame: nearLeft, in: visible)
        #expect(list == CGRect(x: 12, y: 588, width: 360, height: 240))
        // An edge-middle list beside a widget near the top: centred it would end above the inner frame.
        let nearTop = CGRect(x: 12, y: 760, width: 30, height: 100)
        let side = GlanceSlot.leftMiddle.listFrame(for: Self.listSize, widgetFrame: nearTop, in: visible)
        #expect(side == CGRect(x: 48, y: 624, width: 360, height: 240), "864 - 240")
    }

    @Test("a drop picks the nearest slot over every screen (GW13)",
          arguments: [
              (CGPoint(x: 100, y: 800), GlanceScreenID(displayID: 1, name: "Built-in Retina Display"), GlanceSlot.topLeft),
              (CGPoint(x: 700, y: 120), GlanceScreenID(displayID: 1, name: "Built-in Retina Display"), .bottomCenter),
              (CGPoint(x: 1300, y: 500), GlanceScreenID(displayID: 1, name: "Built-in Retina Display"), .rightMiddle),
              // Just past the seam, on the second screen: its left middle (1452, 528) beats the first's right middle.
              (CGPoint(x: 1500, y: 600), GlanceScreenID(displayID: 2, name: "Studio Display"), .leftMiddle),
              (CGPoint(x: 3340, y: 20), GlanceScreenID(displayID: 2, name: "Studio Display"), .bottomRight),
              (CGPoint(x: 2400, y: 1000), GlanceScreenID(displayID: 2, name: "Studio Display"), .topCenter),
          ])
    func nearestSlot(point: CGPoint, screen: GlanceScreenID, slot: GlanceSlot) throws {
        let found = try #require(GlanceSlot.nearest(to: point, on: [Self.main, Self.second]))
        #expect(found.screen.id == screen)
        #expect(found.slot == slot)
    }

    @Test("a drop with no screen finds nothing")
    func nearestWithoutScreens() {
        #expect(GlanceSlot.nearest(to: .zero, on: []) == nil)
    }

    @Test("the saved placement survives JSON, the slot as a stable name")
    func savedRoundTrip() throws {
        let saved = GlancePlacement(screen: Self.second.id, slot: .rightMiddle)
        let data = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(GlancePlacement.self, from: data) == saved)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"rightMiddle\""))
        let dropped = try #require(GlanceSlot.nearest(to: CGPoint(x: 3340, y: 528), on: [Self.main, Self.second]))
        #expect(dropped.saved == GlancePlacement(screen: Self.second.id, slot: .rightMiddle))
    }

    @Test("a saved placement comes back on its screen after a relaunch")
    func resolvesSavedScreen() {
        let saved = GlancePlacement(screen: Self.second.id, slot: .topLeft)
        #expect(GlancePlacement.resolve(saved, screens: [Self.main, Self.second])
            == GlancePlacement.Resolved(screen: Self.second, slot: .topLeft))
    }

    @Test("a screen that came back with a new display id is found by its name")
    func resolvesByName() {
        let saved = GlancePlacement(screen: GlanceScreenID(displayID: 99, name: "Studio Display"), slot: .bottomLeft)
        #expect(GlancePlacement.resolve(saved, screens: [Self.main, Self.second])
            == GlancePlacement.Resolved(screen: Self.second, slot: .bottomLeft))
    }

    @Test("with the saved screen gone the widget keeps its slot on the main screen")
    func fallsBackToMain() {
        let saved = GlancePlacement(screen: Self.second.id, slot: .topRight)
        #expect(GlancePlacement.resolve(saved, screens: [Self.main])
            == GlancePlacement.Resolved(screen: Self.main, slot: .topRight))
    }

    @Test("nothing saved is bottom right on the main screen (GW16)")
    func defaultBottomRight() {
        #expect(GlancePlacement.resolve(nil, screens: [Self.main, Self.second])
            == GlancePlacement.Resolved(screen: Self.main, slot: .bottomRight))
        #expect(GlancePlacement.resolve(nil, screens: []) == nil)
    }
}
