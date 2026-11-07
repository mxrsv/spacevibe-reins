import Foundation

// Entry point. The screenshot mode has to run before SwiftUI creates a window, so `SpaceVibeApp` is not `@main`.
switch LaunchMode.current() {
case .shots(let directory):
    MainActor.assumeIsolated { ShotRenderer.run(into: directory) }
case .normal, .gallery:
    SpaceVibeApp.main()
}
