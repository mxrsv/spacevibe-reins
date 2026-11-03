import SwiftUI

/// Sidebar footer button: switches between dark and light and remembers the choice.
struct ThemeToggle: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let appearance = shell.appearance
        let target = appearance.choice.toggled
        let label = "Switch to \(target.rawValue) theme"
        Button { appearance.toggle() } label: {
            Image(systemName: target == .light ? "sun.max" : "moon")
                .accessibilityLabel(label)
        }
        .buttonStyle(.reins(.plainIcon))
        .help(label)
    }
}
