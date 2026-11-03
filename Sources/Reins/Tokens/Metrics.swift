import SwiftUI

/// Sizes, radii and spacing. One place so a number is never typed twice. Spec: `docs/specs/2026-11-03-reins-design-language.md`
/// (Spacing, sizes, radii, colour). Text roles live in `ReinsType`.
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
    static let paletteRadius: CGFloat = 12
    /// Buttons, scope picker, sidebar items.
    static let controlRadius: CGFloat = 8
    /// Search field, palette row and the segmented control's frame.
    static let fieldRadius: CGFloat = 8
    /// A segment inside the segmented control (the frame's radius less its padding).
    static let segmentRadius: CGFloat = 6
    static let tagRadius: CGFloat = 4
    static let kbdRadius: CGFloat = 4

    /// Every row: 6 pt above and below a 20 + 16 two-line block, or around a 28 pt control.
    static let rowMinHeight: CGFloat = 48
    static let rowVerticalPadding: CGFloat = 6
    /// A row of three or more lines.
    static let tallRowVerticalPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let rowHorizontalPadding: CGFloat = 16
    static let rowLeadWidth: CGFloat = 20
    /// Where a separator between rows starts: padding, lead and the gap after it.
    static var separatorInset: CGFloat { rowHorizontalPadding + rowLeadWidth + rowSpacing }

    static let cardHeaderHeight: CGFloat = 48
    static let sectionRowHeight: CGFloat = 32

    /// One CLI's usage column: bar plus number. Header cells use the same width so columns line up.
    static let usageCellWidth: CGFloat = 200
    /// Fits "12,345" in `ReinsType.body`.
    static let usageNumberWidth: CGFloat = 52
    /// Fits "~$148.20" in `ReinsType.number`.
    static let costWidth: CGFloat = 72
    /// Activity's state tag column; fits "not measurable" with its icon.
    static let stateWidth: CGFloat = 120
    /// Loadout's trailing actions: one 28 pt slot per CLI and 4 pt between.
    static let loadoutActionsWidth: CGFloat = 60
    static let barHeight: CGFloat = 6
    static let legendSwatchWidth: CGFloat = 22

    /// Every control: button, chip, segmented frame, scope picker, search field.
    static let controlHeight: CGFloat = 28
    static let chipHeight: CGFloat = 28
    /// A segment inside its 28 pt frame.
    static let segmentHeight: CGFloat = 24
    static let tagHeight: CGFloat = 20
    static let sidebarItemHeight: CGFloat = 32
    static let sidebarIconWidth: CGFloat = 16

    static let emptyStateMessageWidth: CGFloat = 360

    /// Confirmation cards (Stop, a rule write).
    static let dialogWidth: CGFloat = 420
    static let wideDialogWidth: CGFloat = 460
    /// Overlays only (palette, confirmation): elevation everywhere else is a border.
    static let overlayShadowRadius: CGFloat = 30
    static let overlayShadowOffset: CGFloat = 24
    static let toastShadowRadius: CGFloat = 14
    static let toastShadowOffset: CGFloat = 8
    /// File history: the CLI dots and the "edits · sessions · when" text.
    static let fileCLIsWidth: CGFloat = 40
    static let fileMetaWidth: CGFloat = 230

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

/// The old font names, now Inter roles. Kept while views move to `.reinsText(_:tone:)` (design-language plan T4 to T8),
/// then deleted. New code uses `ReinsType`.
enum ReinsFont {
    static var body: Font { ReinsType.body.font }
    static var bodyStrong: Font { ReinsType.bodyStrong.font }
    static var small: Font { ReinsType.caption.font }
    static var smallStrong: Font { ReinsType.captionStrong.font }
    static var tiny: Font { ReinsType.label.font }
    static var title: Font { ReinsType.title.font }
    static var palette: Font { ReinsType.paletteInput.font }
    static var mono: Font { ReinsType.code.font }
    static var monoStrong: Font { ReinsType.codeTitle.font }
    static var kbd: Font { ReinsType.label.font }
    static var emptyStateIcon: Font { ReinsType.symbolLarge.font }
}
