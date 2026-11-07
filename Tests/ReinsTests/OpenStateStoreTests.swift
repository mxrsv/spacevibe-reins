import Testing
@testable import Reins

/// V5-R55: open and closed choices per page and band, kept until the app quits, and a write never folds the band of the
/// row it changed. Each test makes its own store, so nothing leaks from the app's shared one.
@Suite("Open-state store: bands keep their state (V5-R55)")
struct OpenStateStoreTests {
    @Test("a band shown open stays open when its problem goes (a write or a refresh never folds it)")
    func problemResolvedStaysOpen() {
        let store = OpenStateStore()
        #expect(store.isOpen(page: "hooks", id: "PostToolUse", byDefault: true))
        #expect(store.isOpen(page: "hooks", id: "PostToolUse", byDefault: false))
    }

    @Test("a band the user closed stays closed after a refresh, problem or not")
    func userChoiceWins() {
        let store = OpenStateStore()
        store.setOpen(false, page: "limits", id: "claude")
        #expect(!store.isOpen(page: "limits", id: "claude", byDefault: true))
        store.setOpen(true, page: "limits", id: "claude")
        #expect(store.isOpen(page: "limits", id: "claude", byDefault: false))
    }

    @Test("a closed band opens when a problem appears in it")
    func newProblemOpens() {
        let store = OpenStateStore()
        #expect(!store.isOpen(page: "rules", id: "Bash", byDefault: false))
        #expect(store.isOpen(page: "rules", id: "Bash", byDefault: true))
    }

    @Test("pages keep their own choices for bands of the same name")
    func pagesAreApart() {
        let store = OpenStateStore()
        store.setOpen(true, page: "subagents", id: "In both")
        #expect(!store.isOpen(page: "skills", id: "In both", byDefault: false))
        #expect(store.isOpen(page: "subagents", id: "In both", byDefault: false))
    }

    @Test("the binding reads the default and writes a choice")
    func binding() {
        let store = OpenStateStore()
        let band = store.binding(page: "activity", id: "codex", byDefault: false)
        #expect(!band.wrappedValue)
        band.wrappedValue = true
        #expect(store.isOpen(page: "activity", id: "codex", byDefault: false))
    }

    @Test("defaults: a problem band opens; with nothing to do the first opens; the rest start closed")
    func defaults() {
        #expect(OpenStateStore.defaultOpen(holdsProblem: true, isFirst: false, pageNeedsUser: true))
        #expect(!OpenStateStore.defaultOpen(holdsProblem: false, isFirst: true, pageNeedsUser: true))
        #expect(OpenStateStore.defaultOpen(holdsProblem: false, isFirst: true, pageNeedsUser: false))
        #expect(!OpenStateStore.defaultOpen(holdsProblem: false, isFirst: false, pageNeedsUser: false))
    }
}
