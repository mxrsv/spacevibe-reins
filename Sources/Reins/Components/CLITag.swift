import ReinsCore
import SwiftUI

/// The CLI's name in its colour, as a tag. For rows that mix both CLIs (file history, failed commands).
struct CLITag: View {
    let cli: InventoryCLI

    init(_ cli: InventoryCLI) { self.cli = cli }

    var body: some View {
        Tag(cli.label, tone: cli.tagTone)
    }
}
