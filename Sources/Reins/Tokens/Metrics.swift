import SwiftUI

/// Sizes, radii and spacing. One place so a number is never typed twice. Spec: `docs/specs/2026-11-03-reins-design-language.md`
/// (Spacing, sizes, radii, colour). Text roles live in `ReinsType`. A width measured for text grows with the Font size
/// setting (`TypeScale.width(_:at:)`, the size it was measured at) and never shrinks below the measured value.
enum Metrics {
    static let sidebarWidth: CGFloat = 232
    /// Space above the sidebar items for the native traffic lights (hidden title bar). Set by the window chrome, not the scale.
    static let trafficLightsInset: CGFloat = 50
    static let pagePadding: CGFloat = 24
    static let pageBottomPadding: CGFloat = 32
    static let topBarHeight: CGFloat = 48
    static let hintBarHeight: CGFloat = 32
    static let topBarSearchWidth: CGFloat = 270
    static let scopePickerMinWidth: CGFloat = 120

    /// Card, banner, toast and palette.
    static let groupRadius: CGFloat = 12
    /// A row's hover and selection block inside a card.
    static let rowRadius: CGFloat = 8
    static let paletteRadius: CGFloat = 12
    /// Buttons, scope picker, sidebar items.
    static let controlRadius: CGFloat = 8
    /// Search field, palette row and the segmented control's frame.
    static let fieldRadius: CGFloat = 8
    /// A segment inside the segmented control (the frame's radius less its padding).
    static let segmentRadius: CGFloat = 6
    static let tagRadius: CGFloat = 6
    static let kbdRadius: CGFloat = 4

    /// Every row: 6 pt above and below a 20 + 16 two-line block, or around a 28 pt control.
    static let rowMinHeight: CGFloat = 48
    static let rowVerticalPadding: CGFloat = 6
    /// A row of three or more lines.
    static let tallRowVerticalPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    /// Where a card's content starts: the row block's inset plus the row's own padding inside it.
    static let rowHorizontalPadding: CGFloat = 16
    /// A row is a block inset this far from the card's edges, so its hover and selection fill never touch them.
    static let rowInset: CGFloat = 8
    /// Inside that block, before the lead slot and after the last cell.
    static var rowInnerPadding: CGFloat { rowHorizontalPadding - rowInset }
    static let rowLeadWidth: CGFloat = 20
    /// Where a row's text starts, from the card's edge: padding, lead and the gap after it.
    static var rowTextInset: CGFloat { rowHorizontalPadding + rowLeadWidth + rowSpacing }
    /// The divider between two rows starts this far from the row block's leading edge (where the text starts) and ends this
    /// far from its trailing edge.
    static let dividerLeadingInset: CGFloat = 40
    static let dividerTrailingInset: CGFloat = 8

    static let cardHeaderHeight: CGFloat = 56
    /// Space under a card's last row.
    static let cardBottomPadding: CGFloat = 8
    static let sectionRowHeight: CGFloat = 32

    /// One CLI's usage column: bar plus number. Header cells use the same width so columns line up.
    static let usageCellWidth: CGFloat = 200
    /// Fits "12,345" in `ReinsType.body`.
    static var usageNumberWidth: CGFloat { TypeScale.shared.width(52, at: 14) }
    /// Fits "~$148.20" in `ReinsType.number`.
    static var costWidth: CGFloat { TypeScale.shared.width(72, at: 14) }
    /// Activity's state tag column; fits "not measurable" with its 16 pt icon (125 measured in Inter 12/500, v3 tag).
    static var stateWidth: CGFloat { TypeScale.shared.width(128, at: 12) }
    /// Loadout's trailing actions: one 28 pt slot per CLI and 4 pt between.
    static let loadoutActionsWidth: CGFloat = 60
    /// Rules: the Claude Code grid's value column (segmented control plus a "mixed" tag), and the value column of the Codex
    /// page (its widest readout, "Unless allowed | When needed | Never", is 275 in Inter 14/600).
    static var rulesClaudeColumn: CGFloat { TypeScale.shared.width(280, at: 14) }
    static var rulesCodexColumn: CGFloat { TypeScale.shared.width(300, at: 14) }
    /// The tinted tile that leads a `StatusLead`.
    static let statusTileSize: CGFloat = 40
    static let legendSwatchWidth: CGFloat = 22

    /// The usage and limit ruler: ten cells, each a tenth of the real track width with this gap at its trailing end.
    /// The usage bar of Loadout and Activity: one continuous capsule, 6 pt. Only Limits uses the ten-cell ruler below.
    static let barHeight: CGFloat = 6
    static let rulerCellCount = 10
    static let rulerHeight: CGFloat = 8
    /// The ruler under the Limits page's figure.
    static let rulerDetailHeight: CGFloat = 32
    static let rulerCellGap: CGFloat = 3
    /// The ruler's two outer ends round by this share of its height: 2 in the list, 8 under the figure (the fact tiles' radius).
    static let rulerEndRadiusFraction: CGFloat = 0.25

    /// Every control: button, chip, segmented frame, scope picker, search field.
    static let controlHeight: CGFloat = 28
    /// The agent card's buttons into its panels (v4 card button): the one exception to the 28 pt control height.
    static let cardButtonHeight: CGFloat = 32
    /// The raised block (v4): its hairline, its shadow's blur radius and drop, the top highlight, and how far it sinks
    /// while pressed.
    static let controlHairlineWidth: CGFloat = 0.5
    static let controlShadowRadius: CGFloat = 1
    static let controlShadowOffset: CGFloat = 1
    static let controlHighlightWidth: CGFloat = 1
    static let controlPressedOffset: CGFloat = 0.5
    /// The spinner that stands in for a loading button's leading icon, and its ring.
    static let spinnerSize: CGFloat = 14
    static let spinnerStroke: CGFloat = 2
    /// A disabled control, the hairline and shadow kept.
    static let disabledOpacity: Double = 0.6
    static let chipHeight: CGFloat = 28
    /// A segment inside its 28 pt frame.
    static let segmentHeight: CGFloat = 24
    static let tagHeight: CGFloat = 24
    /// The state dot at a tag's leading edge.
    static let tagDotSize: CGFloat = 6
    static let kbdHeight: CGFloat = 20
    static let sidebarItemHeight: CGFloat = 48
    static let sidebarItemSpacing: CGFloat = 8
    /// Inside a sidebar item, before the icon and after the count.
    static let sidebarItemPadding: CGFloat = 16

    /// Icon sizes (`IconSize`): sidebar 22, row lead and banner 20, buttons, tags and fields 16, beside 12 pt text 14 (the
    /// smallest: Solar Bold Duotone loses detail below it), an empty state's mark 24.
    static let iconSidebar: CGFloat = 22
    static let iconRow: CGFloat = 20
    static let iconControl: CGFloat = 16
    static let iconInline: CGFloat = 14
    static let iconLarge: CGFloat = 24

    static let emptyStateMessageWidth: CGFloat = 360

    /// Limits: the CLI mark (40, 28 in the page's list and detail title, 24 in a sidebar tile).
    static let cliMarkSize: CGFloat = 40
    static let cliMarkMediumSize: CGFloat = 28
    static let cliMarkSmallSize: CGFloat = 24
    /// The Limits page's window list; the selected window's detail takes the rest of the width.
    static let limitsListWidth: CGFloat = 340
    /// The glyph's share of its mark square.
    static let cliMarkGlyphFraction: CGFloat = 0.6

    /// Settings: the window buttons at the top left (hidden title bar) and the gap after them, where the back button starts;
    /// the centred column of cards; one rail tab (icon over name); a Theme tile's picture, width over height.
    static let trafficLightsWidth: CGFloat = 92
    static let settingsColumnWidth: CGFloat = 720
    static let railTabWidth: CGFloat = 96
    static let railTabHeight: CGFloat = 60
    static let themeThumbnailAspect: CGFloat = 1.6
    /// The on/off switch: its capsule and the knob inside it, 2 pt from the edge.
    static let switchWidth: CGFloat = 32
    static let switchHeight: CGFloat = 20
    static let switchKnob: CGFloat = 16
    /// The Reins mark on the Update card, and its corner as a share of its side (`Resources/AppIcon.svg`: 57.5 of 256).
    static let reinsMarkSize: CGFloat = 56
    static let reinsMarkRadiusFraction: CGFloat = 57.5 / 256

    /// The Agents page's inspector (spec, Interface: Panel): dragged between 420 and 720, 480 when first opened and 720 for
    /// Advanced; the agent cards beside it never narrower than 440; the grip over its leading edge; a 1 pt divider.
    static let inspectorMinWidth: CGFloat = 420
    static let inspectorMaxWidth: CGFloat = 720
    static let inspectorDefaultWidth: CGFloat = 480
    static let agentCardsMinWidth: CGFloat = 440
    static let inspectorGripWidth: CGFloat = 8
    static let dividerWidth: CGFloat = 1
    /// The Advanced editor: one line of the `code` role in its 20 pt box, the line-number gutter, and the editors' least
    /// height; the both-models choice card's ring.
    static let codeLineHeight: CGFloat = 20
    static let gutterWidth: CGFloat = 40
    static let editorMinHeight: CGFloat = 240
    static let choiceRingWidth: CGFloat = 1.5

    /// Confirmation cards (Stop, a rule write).
    static let dialogWidth: CGFloat = 420
    static let wideDialogWidth: CGFloat = 460
    /// Overlays only (palette, confirmation, toast). Cards are fill on the well, with no border and no shadow.
    static let overlayShadowRadius: CGFloat = 30
    static let overlayShadowOffset: CGFloat = 24
    static let toastShadowRadius: CGFloat = 14
    static let toastShadowOffset: CGFloat = 8
    /// File history: the CLI dots and the "edits · sessions · when" text.
    static let fileCLIsWidth: CGFloat = 40
    static var fileMetaWidth: CGFloat { TypeScale.shared.width(230, at: 12) }

    /// The gallery's frame for an overlay specimen (a confirmation, the sidebar).
    static let galleryOverlayHeight: CGFloat = 300
    static let paletteWidth: CGFloat = 600
    static let paletteFieldHeight: CGFloat = 48
    static let paletteFooterHeight: CGFloat = 36
    static let paletteListMaxHeight: CGFloat = 360
    /// The palette's top edge, as a share of the window height.
    static let paletteTopFraction: CGFloat = 0.14
    static let paletteRowHeight: CGFloat = 36
    /// Estimated height of a section title in the palette list (8 pt above, 4 pt below, one line); it only sizes the list.
    static let paletteSectionHeight: CGFloat = 28

    /// Toast stays about this long unless the pointer rests on it.
    static let toastDuration: Duration = .seconds(7)
    static let toastBottomInset: CGFloat = 48
}

/// The spacing scale. 2 and 6 are used only inside one component; between components the steps are 4 to 32.
enum Space {
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
}
