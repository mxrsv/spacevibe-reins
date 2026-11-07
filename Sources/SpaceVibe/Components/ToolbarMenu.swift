import SwiftUI

/// A borderless toolbar button of the tab head (V5-R51): `Filter`, `View`, `Refresh`, the scope. 32 high, 12 at the
/// sides, a 16 pt glyph 4 before its 12 pt label in `fg2`; hovered `hover` and `fg`, focused `sel` (D57). An open menu
/// leaves it as it is (the kit draws no expanded state).
struct ToolbarButton: View {
    let title: String
    var glyph: ContentGlyph?
    /// The scope control's caret after the label.
    var trailingCaret = false
    let action: () -> Void

    init(_ title: String, glyph: ContentGlyph? = nil, trailingCaret: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.trailingCaret = trailingCaret
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.ToolbarButton.spacing) {
                if let glyph { SpaceVibeIcon(content: glyph) }
                Text(title)
                if trailingCaret { SpaceVibeIcon(content: .caretDown) }
            }
        }
        .buttonStyle(ToolbarButtonStyle())
        .focusEffectDisabled()
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledLabel(configuration: configuration) }

    private struct StyledLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.specimenInteraction) private var specimen
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let hovered = hovering || specimen.contains(.hover)
            let focused = isFocused || specimen.contains(.focus)
            let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
            configuration.label
                .spaceVibeText(.meta)
                .foregroundStyle(hovered ? Palette.fg : Palette.fg2)
                .lineLimit(1)
                .padding(.horizontal, Metrics.ToolbarButton.padding)
                .frame(height: Metrics.ToolbarButton.height)
                .background(shape.fill(focused || configuration.isPressed ? Palette.sel : (hovered ? Palette.hover : .clear)))
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovered)
        }
    }
}

/// A toolbar button with its menu: it opens the menu under itself, trailing edges aligned, `Metrics.Menu.gap` below;
/// a click outside or Esc closes it, and Esc gives the focus back to the button (V5-R37). The page owns `isOpen`, so its
/// `/` key can open Filter.
///
///     ToolbarMenuButton("Filter", glyph: .filter, isOpen: $filterOpen, id: "skills.filter") { close in
///         FilterMenu(fields: fields, onToggle: toggle, onClose: close)
///     }
struct ToolbarMenuButton<Menu: View>: View {
    let title: String
    var glyph: ContentGlyph?
    var trailingCaret = false
    @Binding var isOpen: Bool
    let id: AnyHashable
    /// The menu, given the action that closes it (`true`: give the focus back to the button).
    let menu: (_ close: @escaping (Bool) -> Void) -> Menu

    @FocusState private var focused: Bool

    init(_ title: String, glyph: ContentGlyph? = nil, trailingCaret: Bool = false, isOpen: Binding<Bool>, id: some Hashable,
         @ViewBuilder menu: @escaping (_ close: @escaping (Bool) -> Void) -> Menu) {
        self.title = title
        self.glyph = glyph
        self.trailingCaret = trailingCaret
        _isOpen = isOpen
        self.id = AnyHashable(id)
        self.menu = menu
    }

    var body: some View {
        ToolbarButton(title, glyph: glyph, trailingCaret: trailingCaret) { isOpen.toggle() }
            .focused($focused)
            .anchoredOverlay(isPresented: isOpen, id: id, placement: .menu(.trailing), onOutsideTap: { isOpen = false }) {
                menu { refocus in
                    isOpen = false
                    if refocus { focused = true }
                }
            }
            .accessibilityValue(isOpen ? "Menu open" : "")
    }
}

/// The surface of a menu (V5-R39): `bgPop` with a `hair2` edge, radius 8, padding 4, the top-edge highlight and the menu
/// shadow; 208 wide, a submenu 232.
struct MenuSurface<Content: View>: View {
    var width: CGFloat = Metrics.Menu.width
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(Metrics.Menu.padding)
            .frame(width: width, alignment: .leading)
            .blockSurface(Palette.bgPop, edge: Palette.hair2)
            .overlayShadow(.menu)
    }
}

/// One line of a menu: 28 high, radius 6, 12 pt text; the highlighted line (pointer or keyboard) and an open field take
/// `sel`. A value ends in the accent tick while it is on; a field ends in its count of picks and a caret.
struct MenuLine: View {
    let entry: MenuEntry
    var isHighlighted = false
    var isExpanded = false

    var body: some View {
        if entry.kind == .heading {
            Text(entry.title)
                .spaceVibeText(.smallLabel, tone: .tertiary)
                .padding(Metrics.Menu.headingInsets)
                .accessibilityAddTraits(.isHeader)
        } else {
            line
        }
    }

    private var line: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        return HStack(spacing: Metrics.Menu.itemSpacing) {
            lead
            Text(entry.title).spaceVibeText(.meta, tone: .primary).lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Metrics.Menu.itemPadding)
        .frame(height: Metrics.Menu.itemHeight)
        .background(shape.fill(isHighlighted || isExpanded ? Palette.sel : .clear))
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.spokenValue)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var isOn: Bool {
        switch entry.kind {
        case .check(let on), .radio(let on): on
        default: false
        }
    }

    @ViewBuilder
    private var lead: some View {
        switch entry.lead {
        case .glyph(let glyph): SpaceVibeIcon(content: glyph, ink: Palette.fg2)
        case .verdict(let kind): VerdictGlyph(kind, size: .inline)
        case nil: EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch entry.kind {
        case .check(let on), .radio(let on):
            SpaceVibeIcon(content: .check, ink: Palette.accent).opacity(on ? 1 : 0)
        case .field(let picked):
            if picked > 0 {
                Text("\(picked)")
                    .spaceVibeText(.micro)
                    .foregroundStyle(Palette.accentCountText)
                    .padding(.horizontal, Metrics.Menu.countPadding)
                    .frame(minWidth: Metrics.Menu.countSize, minHeight: Metrics.Menu.countSize)
                    .background(Capsule().fill(Palette.accentBg))
            }
            SpaceVibeIcon(content: .caretDown, size: .small, ink: Palette.fg3).rotationEffect(.degrees(-90))
        case .heading:
            EmptyView()
        }
    }
}

/// One field of the Filter menu: its line in the first list and its values.
struct FilterMenuField: Identifiable, Equatable {
    let id: String
    let title: String
    var lead: MenuEntry.Lead?
    /// Checkbox values, and headings between groups of them.
    var values: [MenuEntry]

    var picked: Int {
        values.filter { if case .check(true) = $0.kind { true } else { false } }.count
    }

    var entry: MenuEntry { MenuEntry(id: id, title: title, kind: .field(picked: picked), lead: lead) }
}

/// The Filter menu (V5-R28, V5-R39, V5-R61): a list of fields, each with its count of picks, whose values open in a
/// submenu at the menu's leading side; one level (the values only) when the page has one field. Values are checkboxes:
/// a pick toggles and the menu stays open. Arrows, Right, Left, Return and Esc per `MenuNavigator`.
struct FilterMenu: View {
    let fields: [FilterMenuField]
    let onToggle: (_ field: String, _ value: String) -> Void
    let onClose: (_ returnFocus: Bool) -> Void

    @State private var nav: MenuNavigator
    @FocusState private var focused: Bool

    init(fields: [FilterMenuField], onToggle: @escaping (_ field: String, _ value: String) -> Void,
         onClose: @escaping (_ returnFocus: Bool) -> Void) {
        self.fields = fields
        self.onToggle = onToggle
        self.onClose = onClose
        let first = fields.count == 1 ? fields[0].values : fields.map(\.entry)
        _nav = State(initialValue: MenuNavigator(entries: first))
    }

    private var oneLevel: Bool { fields.count == 1 }
    private var entries: [MenuEntry] { oneLevel ? fields[0].values : fields.map(\.entry) }

    private func values(of field: String?) -> [MenuEntry] {
        fields.first { $0.id == field }?.values ?? []
    }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Menu.gap) {
            if !oneLevel, let open = nav.openField {
                MenuSurface(width: Metrics.Menu.submenuWidth) {
                    ForEach(Array(values(of: open).enumerated()), id: \.element.id) { index, value in
                        MenuLine(entry: value, isHighlighted: nav.inSubmenu && nav.sub == index)
                            .onHover { if $0 { nav.hoverSub(index, values: values(of: open)) } }
                            .onTapGesture { onToggle(open, value.id) }
                    }
                }
                .offset(y: -Metrics.Menu.submenuRise)
            }
            MenuSurface {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    MenuLine(entry: entry, isHighlighted: !nav.inSubmenu && nav.main == index,
                             isExpanded: nav.openField == entry.id)
                        .onHover { if $0 { nav.hoverMain(index, entries: entries) } }
                        .onTapGesture { tap(index) }
                }
            }
        }
        .menuKeys($focused) { key in run(nav.handle(key, entries: entries, values: valuesForKey(key))) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter")
    }

    /// The values a key acts on: the open submenu's, or the highlighted field's when Right or Return opens it.
    private func valuesForKey(_ key: MenuNavigator.Key) -> [MenuEntry] {
        if nav.inSubmenu { return values(of: nav.openField) }
        guard let main = nav.main, entries.indices.contains(main) else { return [] }
        return values(of: entries[main].id)
    }

    private func tap(_ index: Int) {
        let entry = entries[index]
        if oneLevel { onToggle(fields[0].id, entry.id); return }
        nav.hoverMain(index, entries: entries)
        run(nav.handle(.right, entries: entries, values: values(of: entry.id)))
    }

    private func run(_ outcome: MenuNavigator.Outcome) {
        switch outcome {
        case .toggle(let field, let entry): onToggle(field ?? fields[0].id, entry)
        case .close(let returnFocus): onClose(returnFocus)
        case .none, .openField, .closeSubmenu: break
        }
    }
}

/// A radio menu (V5-R30, V5-R39): sections under headings (`Group by`, `Order by`), the picked value of each with the tick.
/// A pick keeps the menu open, as the kit does. The ids of the entries say which section they belong to.
struct RadioMenu: View {
    let entries: [MenuEntry]
    let onPick: (_ entry: String) -> Void
    let onClose: (_ returnFocus: Bool) -> Void

    @State private var nav: MenuNavigator
    @FocusState private var focused: Bool

    init(entries: [MenuEntry], onPick: @escaping (_ entry: String) -> Void, onClose: @escaping (_ returnFocus: Bool) -> Void) {
        self.entries = entries
        self.onPick = onPick
        self.onClose = onClose
        _nav = State(initialValue: MenuNavigator(entries: entries))
    }

    var body: some View {
        MenuSurface {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                MenuLine(entry: entry, isHighlighted: nav.main == index)
                    .onHover { if $0 { nav.hoverMain(index, entries: entries) } }
                    .onTapGesture { if entry.isSelectable { onPick(entry.id) } }
            }
        }
        .menuKeys($focused) { key in
            switch nav.handle(key, entries: entries) {
            case .toggle(_, let entry): onPick(entry)
            case .close(let returnFocus): onClose(returnFocus)
            case .none, .openField, .closeSubmenu: break
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    /// Takes the keyboard focus when the menu appears and turns the menu keys into `MenuNavigator` keys.
    func menuKeys(_ focused: FocusState<Bool>.Binding, run: @escaping (MenuNavigator.Key) -> Void) -> some View {
        focusable()
            .focused(focused)
            .focusEffectDisabled()
            .onAppear { focused.wrappedValue = true }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .escape]) { press in
                let key: MenuNavigator.Key = switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                case .rightArrow: .right
                case .return: .enter
                default: .escape
                }
                run(key)
                return .handled
            }
    }
}
