import SwiftUI

/// The page title (the tab's, or Limits) and the palette entry point, 48 pt high. The bar is part of the draggable window
/// background.
struct TopBarView: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        HStack(spacing: Space.s12) {
            Text(shell.title)
                .reinsText(.title, tone: .primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            SearchField(placeholder: "Search or run a command", shortcut: "\u{2318}K", spokenShortcut: "Command K") { shell.openPalette() }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .frame(height: Metrics.topBarHeight)
        .padding(.top, Space.s4)
    }
}
