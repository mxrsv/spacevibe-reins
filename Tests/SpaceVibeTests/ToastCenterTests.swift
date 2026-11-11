import Testing
@testable import SpaceVibe

@MainActor
@Suite("Toast center")
struct ToastCenterTests {
    /// Waits until the Undo that is running has returned.
    private func settle(_ toasts: ToastCenter) async {
        while toasts.isUndoing { await Task.yield() }
    }

    @Test("a toast that replaced the one with the Undo leaves the Undo on the stack")
    func replacedToastKeepsUndo() async {
        let toasts = ToastCenter(announce: false)
        var runs = 0
        toasts.show("a", undo: { runs += 1 })
        toasts.show("x", tone: .danger)
        #expect(toasts.current?.message == "x")
        toasts.undoLast()
        await settle(toasts)
        #expect(runs == 1)
        toasts.undoLast()
        await settle(toasts)
        #expect(runs == 1)
        #expect(toasts.undoStack.isEmpty)
    }

    @Test("the toast's own Undo takes its item off the stack, so undoLast never runs it twice")
    func toastButtonRunsOnce() async {
        let toasts = ToastCenter(announce: false)
        var runs = 0
        toasts.show("a", undo: { runs += 1 })
        toasts.runCurrentAction()
        await settle(toasts)
        #expect(runs == 1)
        #expect(toasts.undoStack.isEmpty)
        toasts.undoLast()
        await settle(toasts)
        #expect(runs == 1)
    }

    @Test("undoLast runs the newest first and hides the toast that carried it")
    func newestFirst() async {
        let toasts = ToastCenter(announce: false)
        var order: [String] = []
        toasts.show("a", undo: { order.append("a") })
        toasts.show("b", undo: { order.append("b") })
        toasts.undoLast()
        await settle(toasts)
        #expect(order == ["b"])
        #expect(toasts.current == nil)
        toasts.undoLast()
        await settle(toasts)
        #expect(order == ["b", "a"])
    }

    @Test("the stack keeps the newest undoDepth items")
    func depthIsBounded() {
        let toasts = ToastCenter(announce: false)
        for n in 0..<(ToastCenter.undoDepth + 3) { toasts.show("w\(n)", undo: {}) }
        #expect(toasts.undoStack.count == ToastCenter.undoDepth)
        #expect(toasts.undoStack.first?.label == "w3")
        #expect(toasts.undoStack.last?.label == "w\(ToastCenter.undoDepth + 2)")
    }

    @Test("a second undoLast while the first Undo runs does nothing; after it completes the next one runs")
    func undosRunOneAtATime() async {
        let toasts = ToastCenter(announce: false)
        var order: [String] = []
        var release: CheckedContinuation<Void, Never>?
        toasts.show("a", asyncUndo: { order.append("a") })
        toasts.show("b", asyncUndo: {
            order.append("b")
            await withCheckedContinuation { release = $0 }
        })
        toasts.undoLast()
        toasts.undoLast()
        toasts.undoLast()
        while release == nil { await Task.yield() }
        #expect(order == ["b"])
        #expect(toasts.isUndoing)
        #expect(toasts.undoStack.map(\.label) == ["a"])
        release?.resume()
        await settle(toasts)
        #expect(!toasts.isUndoing)
        toasts.undoLast()
        await settle(toasts)
        #expect(order == ["b", "a"])
    }

    @Test("a toast shown with sessionUndo false keeps its Undo off the stack but still runs it")
    func dismissUndoStaysOnItsToast() async {
        let toasts = ToastCenter(announce: false)
        var runs = 0
        toasts.show("Dismissed", sessionUndo: false, undo: { runs += 1 })
        #expect(toasts.undoStack.isEmpty)
        #expect(toasts.current?.action != nil)
        toasts.undoLast()
        await settle(toasts)
        #expect(runs == 0)
        toasts.runCurrentAction()
        #expect(runs == 1)   // an in-memory Undo has run by the time the call returns
    }

    @Test("the Z key runs the Undo on the toast showing when it is off the stack, and leaves the stack alone")
    func zKeyRunsTheDismissUndo() async {
        let toasts = ToastCenter(announce: false)
        var ran: [String] = []
        toasts.show("Removed", asyncUndo: { ran.append("W1") })
        toasts.show("Dismissed", sessionUndo: false, undo: { ran.append("dismiss") })
        #expect(toasts.canUndoByKey)
        toasts.undoKey()
        await settle(toasts)
        #expect(ran == ["dismiss"])
        #expect(toasts.undoStack.map(\.label) == ["Removed"])
        #expect(toasts.current == nil)
        // With no off-stack toast showing, the key runs the stack as before.
        toasts.undoKey()
        await settle(toasts)
        #expect(ran == ["dismiss", "W1"])
        #expect(!toasts.canUndoByKey)
    }

    @Test("the toast's Undo pressed while another Undo runs leaves the toast up and runs nothing")
    func busyButtonKeepsTheToast() async {
        let toasts = ToastCenter(announce: false)
        var ran: [String] = []
        var release: CheckedContinuation<Void, Never>?
        toasts.show("a", asyncUndo: { ran.append("a") })
        toasts.show("b", asyncUndo: {
            ran.append("b")
            await withCheckedContinuation { release = $0 }
        })
        toasts.undoLast()
        while release == nil { await Task.yield() }
        toasts.show("c", asyncUndo: { ran.append("c") })
        let shown = toasts.current?.id
        toasts.runCurrentAction()
        #expect(toasts.current?.id == shown)
        #expect(ran == ["b"])
        release?.resume()
        await settle(toasts)
        toasts.runCurrentAction()
        await settle(toasts)
        #expect(ran == ["b", "c"])
        #expect(toasts.current == nil)
    }
}
