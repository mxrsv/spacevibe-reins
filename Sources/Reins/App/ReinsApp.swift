import SwiftUI

struct ReinsApp: App {
    @State private var appearance: AppearanceStore
    @State private var shell: ShellModel
    @State private var toasts = ToastCenter()
    private let mode = LaunchMode.current()

    init() {
        let appearance = AppearanceStore()
        _appearance = State(initialValue: appearance)
        _shell = State(initialValue: ShellModel(tabs: TabRegistry.makeTabs(), appearance: appearance))
    }

    var body: some Scene {
        Window("Reins", id: "main") {
            Group {
                if case .gallery = mode {
                    ComponentGalleryWindow()
                } else {
                    ShellView()
                }
            }
            .reinsRoot(shell: shell, toasts: toasts)
            .frame(minWidth: 960, minHeight: 600)
            .preferredColorScheme(appearance.choice.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1180, height: 760)
        .commands { ShellCommands(shell: shell) }
    }
}
