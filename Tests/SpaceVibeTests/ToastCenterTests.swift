import Testing
@testable import SpaceVibe

@MainActor
@Suite("Toast center")
struct ToastCenterTests {
    @Test("a toast that replaced the one with the Undo leaves the Undo on the stack")
    func replacedToastKeepsUndo() {
        let toasts = ToastCenter(announce: false)
        var runs = 0
        toasts.show("a", undo: { runs += 1 })
        toasts.show("x", tone: .danger)
        #expect(toasts.current?.message == "x")
        toasts.undoLast()
        #expect(runs == 1)
        toasts.undoLast()
        #expect(runs == 1)
        #expect(toasts.undoStack.isEmpty)
    }

    @Test("the toast's own Undo takes its item off the stack, so undoLast never runs it twice")
    func toastButtonRunsOnce() {
        let toasts = ToastCenter(announce: false)
        var runs = 0
        toasts.show("a", undo: { runs += 1 })
        toasts.runCurrentAction()
        #expect(runs == 1)
        #expect(toasts.undoStack.isEmpty)
        toasts.undoLast()
        #expect(runs == 1)
    }

    @Test("undoLast runs the newest first and hides the toast that carried it")
    func newestFirst() {
        let toasts = ToastCenter(announce: false)
        var order: [String] = []
        toasts.show("a", undo: { order.append("a") })
        toasts.show("b", undo: { order.append("b") })
        toasts.undoLast()
        #expect(order == ["b"])
        #expect(toasts.current == nil)
        toasts.undoLast()
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
}
