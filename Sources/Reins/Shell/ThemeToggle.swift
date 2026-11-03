import SwiftUI

/// Sidebar footer button: switches between dark and light and remembers the choice.
struct ThemeToggle: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let appearance = shell.appearance
        let target = appearance.choice.toggled
        let label = "Switch to \(target.rawValue) theme"
        Button { appearance.toggle() } label: {
            ReinsIcon(target == .light ? .sun : .moon)
        }
        .buttonStyle(.reins(.plainIcon))
        .help(label)
        .accessibilityLabel(label)
    }
}
