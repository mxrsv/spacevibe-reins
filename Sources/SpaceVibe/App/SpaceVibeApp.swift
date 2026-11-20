import SwiftUI

struct SpaceVibeApp: App {
    /// The id of the main `Window` scene, which the app delegate reopens from the Dock.
    static let mainWindowID = "main"

    /// Keeps the app running after the main window closes and reopens it from the Dock (GW17).
    @NSApplicationDelegateAdaptor(SpaceVibeAppDelegate.self) private var appDelegate
    @State private var shell: ShellModel
    @State private var env = AppEnvironment.shared
    private let mode = LaunchMode.current()

    init() {
        // The app's own store applies the theme to `NSApp.appearance` and the font size to every text role.
        let shell = ShellModel(tabs: TabRegistry.makeTabs(), appearance: AppearanceStore(live: true))
        _shell = State(initialValue: shell)
        AppEnvironment.shared.updates.start(mode: mode)
        // The CLIs every page shows come from the core's `clis.list`; it is the first read, so pages rarely wait for it.
        AppEnvironment.shared.startCLIs()
        // A click on the glance widget with no host app opens Activity in this shell (GW6); the app delegate starts the widget.
        GlanceController.shared.shell = shell
    }

    var body: some Scene {
        Window(SpaceVibeMark.productName, id: Self.mainWindowID) {
            Group {
                if case .gallery = mode {
                    ComponentGalleryWindow()
                } else {
                    AppShell()
                }
            }
            .spaceVibeRoot(shell: shell, toasts: env.toasts, env: env)
            .linksMainWindow(to: appDelegate)
            .frame(minWidth: 960, minHeight: 600)
        }
        // Present the main window at every launch, also when it was closed at the last quit and nothing is restored: its
        // content sets the app delegate's `openMainWindow`, which the Dock click and the widget's fallback use (GW17).
        .defaultLaunchBehavior(.presented)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1180, height: 760)
        .commands {
            ShellCommands(shell: shell)
            // The standard About panel, with the licences the app must show (Credits).
            CommandGroup(replacing: .appInfo) {
                Button("About \(SpaceVibeMark.productName)") { Credits.showAboutPanel() }
                Button("Check for Updates\u{2026}") { env.updates.checkForUpdates() }
            }
        }
    }
}
