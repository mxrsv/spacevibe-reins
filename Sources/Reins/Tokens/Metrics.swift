import SwiftUI

/// Sizes, radii and type. One place so a number is never typed twice. 13 pt base, system font, tabular digits.
enum Metrics {
    static let sidebarWidth: CGFloat = 232
    /// Space above the sidebar items for the native traffic lights (hidden title bar).
    static let trafficLightsInset: CGFloat = 50
    static let pagePadding: CGFloat = 24
    static let hintBarHeight: CGFloat = 38
    static let topBarSearchWidth: CGFloat = 270

    static let groupRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let tagRadius: CGFloat = 5
    static let paletteRadius: CGFloat = 14

    static let rowMinHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 12
    static let rowHorizontalPadding: CGFloat = 14
    static let rowLeadWidth: CGFloat = 20

    /// One CLI's usage column: bar plus number. Header cells use the same width so columns line up.
    static let usageCellWidth: CGFloat = 200
    static let usageNumberWidth: CGFloat = 44
    static let barHeight: CGFloat = 6

    static let controlHeight: CGFloat = 26
    static let chipHeight: CGFloat = 24

    /// Toast stays about this long unless the pointer rests on it.
    static let toastDuration: Duration = .seconds(7)
    static let toastBottomInset: CGFloat = 54
}

/// Fonts. Every size uses monospaced digits so counts and times line up between rows.
enum ReinsFont {
    static let body = Font.system(size: 13).monospacedDigit()
    static let bodyStrong = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let small = Font.system(size: 12).monospacedDigit()
    static let smallStrong = Font.system(size: 12, weight: .semibold).monospacedDigit()
    static let tiny = Font.system(size: 11.5).monospacedDigit()
    static let title = Font.system(size: 20, weight: .semibold)
    static let palette = Font.system(size: 15)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoStrong = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let kbd = Font.system(size: 11, design: .monospaced)

    // The size order of the Tokens board (spec, Interface: Tokens): one lead total, then the figure per CLI, then one
    // leading number in each card, then a leading row; everything else is body size or smaller. Large figures keep
    // proportional digits, as the mock draws them.
    static let leadTotal = Font.system(size: 40, weight: .semibold)
    static let cliFigure = Font.system(size: 24, weight: .semibold)
    static let cardLeader = Font.system(size: 20, weight: .semibold)
    static let rowLeader = Font.system(size: 15, weight: .semibold)
    /// Rows under a leading row in a Tokens card, and their values.
    static let compact = Font.system(size: 12.5).monospacedDigit()
}
