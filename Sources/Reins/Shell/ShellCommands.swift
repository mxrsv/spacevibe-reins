import SwiftUI

/// Menu items and their shortcuts: `⌘1`..`⌘9` for the tabs, `⌘K` for the palette. They live in the View menu,
/// so they work from any focus and show up for VoiceOver and Full Keyboard Access.
struct ShellCommands: Commands {
    let shell: ShellModel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(Array(shell.tabs.enumerated()), id: \.element.id) { index, tab in
                if index < 9, let key = String(index + 1).first {
                    Button(tab.title) { shell.select(index: index) }
                        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
                }
            }
            Divider()
            Button("Search or Run a Command") { shell.togglePalette() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Switch to \(shell.appearance.choice.toggled.rawValue.capitalized) Theme") { shell.appearance.toggle() }
        }
    }
}
