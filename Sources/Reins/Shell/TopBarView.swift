import SwiftUI

/// The tab title and the palette entry point. The bar is part of the draggable window background.
struct TopBarView: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        HStack(spacing: 12) {
            Text(shell.activeTab.title)
                .font(ReinsFont.title)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            SearchButton { shell.openPalette() }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

private struct SearchButton: View {
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").imageScale(.small).accessibilityHidden(true)
                Text("Search or run a command")
                Spacer(minLength: 0)
                Kbd("\u{2318}K")
            }
            .font(ReinsFont.body)
            .foregroundStyle(Palette.textTertiary)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(width: Metrics.topBarSearchWidth, height: 30)
            .background(shape.fill(hovering ? Palette.surfaceRaised : Palette.surface))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(focused, cornerRadius: 8)
        .onHover { hovering = $0 }
        .accessibilityLabel("Search or run a command")
        .accessibilityHint("Command K")
    }
}
