import CoreGraphics
import Testing
@testable import SpaceVibe

/// A press on the glance strip (spec `docs/specs/2026-11-19-session-glance-widget.md`, GW-R6, GW-R7): renders wait while it is
/// held, so the replayed click reaches the entry it went down on, and a press whose release never comes is ended. Pure, no
/// window.
@Suite("Glance press", .fixtureCLIs)
struct GlancePressTests {
    // MARK: Render gate

    @Test("open gate: every render runs at once and nothing is left for the release")
    func openGate() {
        var gate = GlanceRenderGate()
        let r1 = gate.admit(snap: false)
        #expect(r1)
        let r2 = gate.admit(snap: true)
        #expect(r2)
        let r3 = gate.release()
        #expect(r3 == nil)
    }

    @Test("held press: reports arriving before the release draw nothing, and one render runs after it")
    func heldPressDefers() {
        var gate = GlanceRenderGate()
        gate.hold()
        let r4 = gate.admit(snap: false)
        #expect(!r4, "a report while the button is down")
        let r5 = gate.admit(snap: false)
        #expect(!r5, "a second report, a hover, a countdown tick")
        #expect(gate.isHeld && gate.deferred == false)
        let r6 = gate.release()
        #expect(r6 == false, "one plain render right after the click was handed on")
        #expect(!gate.isHeld && gate.deferred == nil)
        let r7 = gate.admit(snap: false)
        #expect(r7, "the next report draws at once")
    }

    @Test("held press with nothing asked: the release runs no render")
    func heldPressNothingAsked() {
        var gate = GlanceRenderGate()
        gate.hold()
        let r8 = gate.release()
        #expect(r8 == nil)
    }

    @Test("a drop's snap survives later plain renders, and a plain render asked before it is upgraded")
    func snapIsKept() {
        var gate = GlanceRenderGate()
        gate.hold()
        let r9 = gate.admit(snap: false)
        #expect(!r9)
        let r10 = gate.admit(snap: true)
        #expect(!r10)
        let r11 = gate.admit(snap: false)
        #expect(!r11)
        let r12 = gate.release()
        #expect(r12 == true)
    }

    // MARK: Lost release

    @Test("a lost release ends the press only after two readings in a row with the button up")
    func lostRelease() {
        var lost = GlanceLostRelease()
        #expect(GlanceLostRelease.upReadings == 2)
        let r13 = lost.observe(leftButtonDown: true)
        #expect(!r13)
        let r14 = lost.observe(leftButtonDown: false)
        #expect(!r14, "one up reading: the release may still be queued")
        let r15 = lost.observe(leftButtonDown: true)
        #expect(!r15, "down again resets the count")
        let r16 = lost.observe(leftButtonDown: false)
        #expect(!r16)
        let r17 = lost.observe(leftButtonDown: false)
        #expect(r17)
    }

    // MARK: Tracker

    @Test("cancel forgets a held press: no click follows, and the release passes through")
    func cancelHeldPress() {
        var tracker = GlancePointerTracker()
        let r18 = tracker.down(at: .zero)
        #expect(r18 == .hold)
        #expect(tracker.isActive && !tracker.isDragging)
        let r19 = tracker.cancel()
        #expect(!r19)
        #expect(!tracker.isActive)
        let r20 = tracker.up(at: .zero)
        #expect(r20 == .pass)
    }

    @Test("cancel ends a drag and says so; a cancel with no press does nothing")
    func cancelDrag() {
        var tracker = GlancePointerTracker()
        _ = tracker.down(at: .zero)
        let far = CGPoint(x: Metrics.Glance.dragThreshold * 3, y: 0)
        let r21 = tracker.dragged(to: far)
        #expect(r21 == .beginDrag(from: .zero, to: far))
        #expect(tracker.isActive && tracker.isDragging)
        let r22 = tracker.cancel()
        #expect(r22)
        #expect(!tracker.isActive)
        let r23 = tracker.dragged(to: far)
        #expect(r23 == .pass)
        let r24 = tracker.cancel()
        #expect(!r24)
    }
}
