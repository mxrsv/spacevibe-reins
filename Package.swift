// swift-tools-version: 6.0
import PackageDescription

// The deployment target is load-bearing, not cosmetic. This toolchain defaults to
// `arm64-apple-macosx28.0`, and a binary built against that target refuses to launch on
// macOS 27 with `_LSOpenURLsWithCompletionHandler() failed with error -10825`. Pinning
// `.macOS(.v15)` here is what makes the shipped binary report `minos 15.0`, and
// `LSMinimumSystemVersion` in Resources/Info.plist must stay in step with it.
let package = Package(
    name: "SpaceVibe",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Linked by the app target only. The engine is the Go helper `Contents/Helpers/spacevibe`, not a Swift target.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpaceVibe",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // scripts/build-app.sh copies Sparkle.framework to Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "SpaceVibeTests",
            dependencies: ["SpaceVibe"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
