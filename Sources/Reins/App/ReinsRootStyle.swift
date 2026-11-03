import SwiftUI

extension View {
    /// What every root view (the window, a screenshot) needs: the shared services in the environment, the base
    /// type and colours, and the accent for system controls.
    @MainActor
    func reinsRoot(shell: ShellModel, toasts: ToastCenter, env: AppEnvironment? = nil) -> some View {
        let env = env ?? .shared
        return self
            .environment(shell)
            .environment(toasts)
            .environment(env)
            .environment(env.limits)
            .environment(shell.appearance)
            .reinsText(.body, tone: .primary)
            .tint(Palette.accent)
    }
}
