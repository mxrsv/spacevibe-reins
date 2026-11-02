import SwiftUI

/// Placeholder screens until the real ones land. Delete a stub when its screen replaces it in `TabRegistry`.
@MainActor
final class LoadoutStubTab: ReinsTab {
    let id = "loadout"
    let title = "Loadout"
    let systemImage = "square.stack.3d.up"
    var content: AnyView { AnyView(StubScreen(text: "Skills, agents and hooks of both CLIs: not built yet.")) }
}

@MainActor
final class RulesStubTab: ReinsTab {
    let id = "rules"
    let title = "Rules"
    let systemImage = "checkmark.shield"
    var content: AnyView { AnyView(StubScreen(text: "What each agent may do, per CLI: not built yet.")) }
}

private struct StubScreen: View {
    let text: String

    var body: some View {
        PageLayout {
            Text(text).font(ReinsFont.body).foregroundStyle(Palette.textSecondary)
        }
    }
}
