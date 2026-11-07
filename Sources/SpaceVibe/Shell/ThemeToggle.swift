import SwiftUI

/// Sidebar footer button: switches to the other of dark and light and remembers it, which leaves System (Settings).
struct ThemeToggle: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let appearance = shell.appearance
        // What shows now, also under System, where only the environment knows it live.
        let target: AppearanceChoice = scheme == .dark ? .light : .dark
        let label = "Switch to \(target.rawValue) theme"
        if shell.isV5 {
            SidebarIconButton(glyph: target == .light ? ContentGlyph.sun : ContentGlyph.moon, label: label) {
                appearance.theme = ThemeSetting(target)
            }
        } else {
            Button { appearance.theme = ThemeSetting(target) } label: {
                SpaceVibeIcon(target == .light ? .sun : .moon)
            }
            .buttonStyle(.spaceVibe(.plainIcon))
            .help(label)
            .accessibilityLabel(label)
        }
    }
}
