import SwiftUI

/// A dot in a CLI's colour, 8 pt (6 pt as a badge on an icon button). Spoken as the CLI's name unless `decorative` (when a
/// text label sits next to it).
struct CLIDot: View {
    let cli: InventoryCLI
    var decorative = false
    var size: CGFloat = Space.s8

    init(_ cli: InventoryCLI, decorative: Bool = false, size: CGFloat = Space.s8) {
        self.cli = cli
        self.decorative = decorative
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(cli.fill)
            .frame(width: size, height: size)
            .accessibilityLabel(cli.label)
            .accessibilityHidden(decorative)
    }
}
