import Testing
@testable import SpaceVibe

/// V5-R39: the menu keyboard, without a window. Up and Down wrap and skip headings, Right opens a field's submenu and moves
/// into it, Left leaves it, Return toggles a value or opens a field, Esc closes and gives the focus back to the button.
@Suite("Menu keyboard (V5-R39)")
struct MenuNavigatorTests {
    static let fields = [
        MenuEntry(id: "status", title: "Status", kind: .field(picked: 1)),
        MenuEntry(id: "cli", title: "CLI", kind: .field(picked: 0)),
        MenuEntry(id: "owner", title: "Owner", kind: .field(picked: 0)),
    ]
    static let status = [MenuEntry(id: "never", title: "Never ran", kind: .check(isOn: true)),
                         MenuEntry(id: "heavy", title: "Heavily used", kind: .check(isOn: false))]
    static let view = [
        MenuEntry(id: "h.group", title: "Group by", kind: .heading),
        MenuEntry(id: "group:none", title: "None", kind: .radio(isOn: true)),
        MenuEntry(id: "group:status", title: "Status", kind: .radio(isOn: false)),
        MenuEntry(id: "h.order", title: "Order by", kind: .heading),
        MenuEntry(id: "order:name", title: "Name", kind: .radio(isOn: false)),
    ]

    @Test("Up and Down move through the lines, wrapping, and skip headings")
    func arrowsWrapAndSkipHeadings() {
        var nav = MenuNavigator(entries: Self.view)
        #expect(nav.main == 1)
        _ = nav.handle(.down, entries: Self.view)
        #expect(nav.main == 2)
        _ = nav.handle(.down, entries: Self.view)
        #expect(nav.main == 4, "the Order by heading is skipped")
        _ = nav.handle(.down, entries: Self.view)
        #expect(nav.main == 1, "wraps to the first value")
        _ = nav.handle(.up, entries: Self.view)
        #expect(nav.main == 4, "wraps back to the last value")
    }

    @Test("Right on a field opens its submenu and moves into it; Left leaves it")
    func rightOpensLeftCloses() {
        var nav = MenuNavigator(entries: Self.fields)
        #expect(nav.handle(.right, entries: Self.fields, values: Self.status) == .openField("status"))
        #expect(nav.inSubmenu && nav.openField == "status" && nav.sub == 0)
        _ = nav.handle(.down, entries: Self.fields, values: Self.status)
        #expect(nav.sub == 1 && nav.main == 0, "arrows move in the submenu, the field keeps its place")
        #expect(nav.handle(.left, entries: Self.fields, values: Self.status) == .closeSubmenu)
        #expect(!nav.inSubmenu && nav.openField == nil && nav.main == 0)
        #expect(nav.handle(.left, entries: Self.fields) == .none, "Left in the first list does nothing")
    }

    @Test("Right on a value and Return on a heading do nothing")
    func rightOnlyOnFields() {
        var nav = MenuNavigator(entries: Self.view)
        #expect(nav.handle(.right, entries: Self.view) == .none)
        #expect(!nav.inSubmenu)
    }

    @Test("Return toggles the highlighted value in the submenu and in a one-level menu, and opens a field")
    func returnToggles() {
        var nav = MenuNavigator(entries: Self.fields)
        #expect(nav.handle(.enter, entries: Self.fields, values: Self.status) == .openField("status"))
        _ = nav.handle(.down, entries: Self.fields, values: Self.status)
        #expect(nav.handle(.enter, entries: Self.fields, values: Self.status) == .toggle(field: "status", entry: "heavy"))
        var radio = MenuNavigator(entries: Self.view)
        _ = radio.handle(.down, entries: Self.view)
        #expect(radio.handle(.enter, entries: Self.view) == .toggle(field: nil, entry: "group:status"))
    }

    @Test("Esc closes the menu, submenu included, and gives the focus back to its button")
    func escapeReturnsFocus() {
        var nav = MenuNavigator(entries: Self.fields)
        _ = nav.handle(.right, entries: Self.fields, values: Self.status)
        #expect(nav.handle(.escape, entries: Self.fields, values: Self.status) == .close(returnFocus: true))
        #expect(!nav.inSubmenu && nav.openField == nil)
    }

    @Test("the pointer on a field opens its submenu without moving the keyboard into it")
    func hoverOpensField() {
        var nav = MenuNavigator(entries: Self.fields)
        nav.hoverMain(1, entries: Self.fields)
        #expect(nav.main == 1 && nav.openField == "cli" && !nav.inSubmenu)
        nav.hoverSub(1, values: Self.status)
        #expect(nav.inSubmenu && nav.sub == 1)
    }

    @Test("a menu of headings only has no line to highlight")
    func headingsOnly() {
        let headings = [MenuEntry(id: "h", title: "Group by", kind: .heading)]
        var nav = MenuNavigator(entries: headings)
        #expect(nav.main == nil)
        #expect(nav.handle(.down, entries: headings) == .none && nav.main == nil)
        #expect(nav.handle(.enter, entries: headings) == .none)
    }

    @Test("each line says what it is to VoiceOver (V5-R43)")
    func spokenValues() {
        #expect(MenuEntry(id: "a", title: "Never ran", kind: .check(isOn: true)).spokenValue == "checked")
        #expect(MenuEntry(id: "a", title: "Never ran", kind: .check(isOn: false)).spokenValue == "not checked")
        #expect(MenuEntry(id: "a", title: "None", kind: .radio(isOn: true)).spokenValue == "selected")
        #expect(MenuEntry(id: "a", title: "Status", kind: .field(picked: 2)).spokenValue == "2 picked")
        #expect(MenuEntry(id: "a", title: "CLI", kind: .field(picked: 0)).spokenValue == "none picked")
    }

    @Test("a field counts the values picked in it")
    func fieldCountsPicks() {
        let field = FilterMenuField(id: "status", title: "Status", values: Self.status + [MenuEntry(id: "h", title: "Tiers", kind: .heading)])
        #expect(field.picked == 1)
        #expect(field.entry.kind == .field(picked: 1))
    }
}
