import SwiftUI

/// An 8 pt dot in a CLI's colour. Spoken as the CLI's name unless `decorative` (when a text label sits next to it).
struct CLIDot: View {
    let cli: CLIKind
    var decorative = false

    init(_ cli: CLIKind, decorative: Bool = false) {
        self.cli = cli
        self.decorative = decorative
    }

    var body: some View {
        Circle()
            .fill(cli.fill)
            .frame(width: 8, height: 8)
            .accessibilityLabel(cli.label)
            .accessibilityHidden(decorative)
    }
}
