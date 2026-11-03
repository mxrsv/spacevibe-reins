import ReinsCore
import SwiftUI

/// The CLI's name as a tag, with a dot in the CLI's colour. For rows that mix both CLIs (file history, failed commands).
struct CLITag: View {
    let cli: InventoryCLI

    init(_ cli: InventoryCLI) { self.cli = cli }

    var body: some View {
        Tag(cli.label, tone: cli.tagTone)
    }
}
