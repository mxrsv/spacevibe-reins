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
        .buttonStyle(IconToggleStyle())
        .help(label)
    }
}

private struct IconToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledIcon(configuration: configuration)
    }

    private struct StyledIcon: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            configuration.label
                .foregroundStyle(hovering ? Palette.text : Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(shape.fill(hovering ? Palette.hover : .clear))
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
        }
    }
}
