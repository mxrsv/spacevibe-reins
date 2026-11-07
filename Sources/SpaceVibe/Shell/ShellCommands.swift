import SwiftUI

/// Menu items and their shortcuts: `⌘1`..`⌘9` for the tabs, `⌘K` for the palette, `⌘L` for Limits in the View menu, and
/// `⌘,` for Settings in the app menu, so they work from any focus and show up for VoiceOver and Full Keyboard Access.
struct ShellCommands: Commands {
    let shell: ShellModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") { shell.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
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
            // In the v5 shell Limits is the third page, `⌘3`, so the View menu has no second way in.
            if !shell.isV5 {
                Button("Show Limits") { shell.openLimits() }
                    .keyboardShortcut("l", modifiers: .command)
            }
            Button("Switch to \(shell.appearance.choice.toggled.rawValue.capitalized) Theme") { shell.appearance.toggle() }
        }
    }
}
