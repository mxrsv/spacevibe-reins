import Foundation

/// What one CLI's usage cell shows. The five states of PRODUCT.md, mapped from the engine by each screen:
///
/// - `counted(runs:)` with `runs > 0`: coloured ruler cells and the number.
/// - `counted(runs: 0)`: never ran; empty ruler and a red 0.
/// - `pending`: installed but not counted yet (recently added, or the scan has not reached it); dashed outline.
/// - `unmeasurable`: the CLI does not log this kind of item; icon and label, the reason as help text.
/// - `missing`: not installed in this CLI; "not installed", or an "Add to <CLI>" button when the cell has an add action.
enum UsageCellModel: Equatable {
    case counted(runs: Int)
    case pending(reason: String? = nil)
    case unmeasurable(reason: String)
    case missing

    /// Ruler fill, 0...1. Square-root scale so a few heavy items do not flatten the rest; a counted item
    /// always shows at least 4 percent, a zero shows none. `max` is the largest run count among the rows
    /// compared (usually per kind); the caller computes it once for the list.
    static func barFraction(runs: Int, max: Int) -> Double {
        guard runs > 0, max > 0 else { return 0 }
        return min(1, Swift.max(0.04, (Double(runs) / Double(max)).squareRoot()))
    }
}
