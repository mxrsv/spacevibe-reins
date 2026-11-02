import SwiftUI

extension View {
    /// What every root view (the window, a screenshot) needs: the shared services in the environment, the base
    /// type and colours, and the accent for system controls.
    @MainActor
    func reinsRoot(shell: ShellModel, toasts: ToastCenter, env: AppEnvironment? = nil) -> some View {
        self
            .environment(shell)
            .environment(toasts)
            .environment(env ?? .shared)
            .environment(shell.appearance)
            .font(ReinsFont.body)
            .foregroundStyle(Palette.text)
            .tint(Palette.accent)
    }
}
