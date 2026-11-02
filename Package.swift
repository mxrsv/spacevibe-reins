// swift-tools-version: 6.0
import PackageDescription

// The deployment target is load-bearing, not cosmetic. This toolchain defaults to
// `arm64-apple-macosx28.0`, and a binary built against that target refuses to launch on
// macOS 27 with `_LSOpenURLsWithCompletionHandler() failed with error -10825`. Pinning
// `.macOS(.v15)` here is what makes the shipped binary report `minos 15.0`, and
// `LSMinimumSystemVersion` in Resources/Info.plist must stay in step with it.
let package = Package(
    name: "Reins",
    platforms: [.macOS(.v15)],
    targets: [
        // Decompress-only zstd from the official facebook/zstd release; see Sources/CZstd/README.md.
        .target(
            name: "CZstd",
            exclude: ["README.md", "COPYING", "LICENSE"],
            cSettings: [.define("ZSTD_DISABLE_ASM", to: "1"), .define("ZSTD_LEGACY_SUPPORT", to: "0")]
        ),
        // The engine. Foundation only: no UI import, so tests and tools use it without the app.
        .target(
            name: "ReinsCore",
            dependencies: ["CZstd"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Reins",
            dependencies: ["ReinsCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ReinsCoreTests",
            dependencies: ["ReinsCore"],
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
