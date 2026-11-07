import Foundation

/// One line of a v5 menu (V5-R39): a heading, a checkbox value (Filter), a radio value (Group by, Order by) or a field that
/// opens a submenu of values (the first level of Filter).
struct MenuEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading
        case check(isOn: Bool)
        case radio(isOn: Bool)
        /// Opens its values in a submenu; `picked` is how many of them are on (the count beside it).
        case field(picked: Int)
    }

    /// What leads a line: a content glyph (16, `fg2`) or a verdict glyph (14), as the kit's Status values carry.
    enum Lead: Equatable {
        case glyph(ContentGlyph)
        case verdict(VerdictGlyph.Kind)
    }

    let id: String
    let title: String
    var kind: Kind
    var lead: Lead?

    var isSelectable: Bool { kind != .heading }

    /// What VoiceOver reads as the line's value (V5-R43): "checked", "not checked", "selected", "2 picked".
    var spokenValue: String {
        switch kind {
        case .heading: ""
        case .check(let isOn): isOn ? "checked" : "not checked"
        case .radio(let isOn): isOn ? "selected" : ""
        case .field(let picked): picked == 0 ? "none picked" : "\(picked) picked"
        }
    }
}

/// The keyboard model of a menu and its one submenu (V5-R39, the kit's `keys`): Up and Down move through the lines of the
/// list the keyboard is in, wrapping and skipping headings; Right on a field opens its submenu and moves into it; Left leaves
/// the submenu; Return toggles a value (or opens a field); Esc closes the menu and gives the focus back to its button. The
/// pointer moves the same highlight. Pure, so `MenuNavigatorTests` drives it; the menu view runs the outcomes.
struct MenuNavigator: Equatable {
    enum Key: Equatable {
        case up, down, left, right, enter, escape
    }

    enum Outcome: Equatable {
        case none
        /// A value was picked: `field` is the open field's id, nil for a value in the first list.
        case toggle(field: String?, entry: String)
        case openField(String)
        case closeSubmenu
        case close(returnFocus: Bool)
    }

    /// The highlighted line of the first list and of the submenu, as indexes into the entries given to `handle`.
    private(set) var main: Int?
    private(set) var sub: Int?
    private(set) var openField: String?
    /// The keyboard is in the submenu.
    private(set) var inSubmenu = false

    init(entries: [MenuEntry]) {
        main = Self.step(from: nil, by: 1, in: entries)
    }

    mutating func handle(_ key: Key, entries: [MenuEntry], values: [MenuEntry] = []) -> Outcome {
        switch key {
        case .up, .down:
            let by = key == .down ? 1 : -1
            if inSubmenu { sub = Self.step(from: sub, by: by, in: values) } else { main = Self.step(from: main, by: by, in: entries) }
            return .none
        case .right:
            guard !inSubmenu, let main, case .field = entries[main].kind else { return .none }
            return open(entries[main].id, values: values)
        case .left:
            guard inSubmenu else { return .none }
            inSubmenu = false
            openField = nil
            sub = nil
            return .closeSubmenu
        case .enter:
            if inSubmenu {
                guard let sub, values.indices.contains(sub), values[sub].isSelectable else { return .none }
                return .toggle(field: openField, entry: values[sub].id)
            }
            guard let main, entries.indices.contains(main) else { return .none }
            if case .field = entries[main].kind { return open(entries[main].id, values: values) }
            return entries[main].isSelectable ? .toggle(field: nil, entry: entries[main].id) : .none
        case .escape:
            inSubmenu = false
            openField = nil
            sub = nil
            return .close(returnFocus: true)
        }
    }

    /// The pointer rests on a line of the first list; on a field it opens that field's submenu (the kit's mouseover),
    /// without moving the keyboard into it.
    mutating func hoverMain(_ index: Int, entries: [MenuEntry]) {
        guard entries.indices.contains(index), entries[index].isSelectable else { return }
        main = index
        inSubmenu = false
        if case .field = entries[index].kind {
            if openField != entries[index].id { sub = nil }
            openField = entries[index].id
        }
    }

    mutating func hoverSub(_ index: Int, values: [MenuEntry]) {
        guard values.indices.contains(index), values[index].isSelectable else { return }
        sub = index
        inSubmenu = true
    }

    private mutating func open(_ field: String, values: [MenuEntry]) -> Outcome {
        openField = field
        inSubmenu = true
        sub = Self.step(from: nil, by: 1, in: values)
        return .openField(field)
    }

    /// The next selectable line from `index` in direction `by`, wrapping; the first (or last) one from nil.
    static func step(from index: Int?, by: Int, in entries: [MenuEntry]) -> Int? {
        guard entries.contains(where: \.isSelectable) else { return nil }
        var next = index ?? (by > 0 ? -1 : entries.count)
        repeat {
            next = (next + by + entries.count) % entries.count
        } while !entries[next].isSelectable
        return next
    }
}
