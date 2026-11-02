import SwiftUI

struct ReinsApp: App {
    @State private var appearance: AppearanceStore
    @State private var shell: ShellModel
    @State private var env = AppEnvironment.shared
    private let mode = LaunchMode.current()
    private let updates: UpdateController

    init() {
        let appearance = AppearanceStore()
        _appearance = State(initialValue: appearance)
        _shell = State(initialValue: ShellModel(tabs: TabRegistry.makeTabs(), appearance: appearance))
        updates = UpdateController(toasts: AppEnvironment.shared.toasts)
        updates.start(mode: mode)
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
            .reinsRoot(shell: shell, toasts: env.toasts, env: env)
            .frame(minWidth: 960, minHeight: 600)
            .preferredColorScheme(appearance.choice.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1180, height: 760)
        .commands {
            ShellCommands(shell: shell)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { updates.checkForUpdates() }
            }
        }
    }
}
