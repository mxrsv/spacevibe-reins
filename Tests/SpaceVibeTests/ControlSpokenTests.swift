import Testing
@testable import SpaceVibe

/// V5-R43 and V5-R59: what VoiceOver reads for the logo toggles and tabs, and the Stop dialog's `Tab` cycle. The live
/// VoiceOver walk is U13's (V5-A8); these are the strings and the order the views use.
@Suite("Control names, values and the dialog's Tab cycle (V5-R43, V5-R59)")
struct ControlSpokenTests {
    @Test("a logo toggle reads the CLI as its name and the state with what a press does as its value")
    func logoToggleValue() {
        #expect(LogoToggle.spokenValue(cli: .codex, isLit: false, mode: .toggles) == "not in Codex, press to add")
        #expect(LogoToggle.spokenValue(cli: .claude, isLit: true, mode: .toggles) == "in Claude Code, press to remove")
        #expect(LogoToggle.spokenValue(cli: .codex, isLit: true, mode: .readOnly) == "in Codex, read-only")
        #expect(LogoToggle.spokenValue(cli: .claude, isLit: true, mode: .onlyCopy) == "in Claude Code, the only copy, use Remove to delete it")
        #expect(CoreLimitsCLI.gemini.label == "Gemini CLI")
    }

    @Test("a tab reads its count and whether it is the selected one")
    func tabValue() {
        #expect(TabChip.spokenValue(count: 13, isActive: true) == "13, selected tab")
        #expect(TabChip.spokenValue(count: 6, isActive: false) == "6, tab")
        #expect(TabChip.spokenValue(count: nil, isActive: false) == "tab")
    }

    @Test("the Stop dialog's focus starts on Cancel and Tab cycles the two buttons, never out")
    func dialogTabCycle() {
        var focus = ConfirmationFocus.initial
        #expect(focus == .cancel)
        focus = focus.next
        #expect(focus == .confirm)
        focus = focus.next
        #expect(focus == .cancel)
    }

    @Test("Undo in a toast carries its Z cap; other toast actions carry none unless they say so")
    func undoKeyCap() {
        #expect(ToastAction.undo {}.keyCap == "Z")
        #expect(ToastAction(title: "View", icon: .download, run: {}).keyCap == nil)
    }
}
