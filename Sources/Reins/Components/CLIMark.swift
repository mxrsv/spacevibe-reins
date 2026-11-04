import AppKit
import ReinsCore
import SwiftUI

/// The colour a CLI carries on the Limits surface. Gemini CLI has no brand colour in the app, so it reads neutral.
extension LimitsCLI {
    var fill: Color {
        switch self {
        case .claude: Palette.claude
        case .codex: Palette.codex
        case .gemini: Palette.textSecondary
        }
    }

    var ink: Color {
        switch self {
        case .claude: Palette.claudeInk
        case .codex: Palette.codexInk
        case .gemini: Palette.textSecondary
        }
    }

    var tint: Color {
        switch self {
        case .claude: Palette.claudeTint
        case .codex: Palette.codexTint
        case .gemini: Palette.surfaceRaised
        }
    }
}

extension LimitsCLI {
    /// The same CLI as the inventory names it (Claude Code or Codex).
    init(_ cli: InventoryCLI) { self = cli == .claude ? .claude : .codex }
}

/// A CLI's brand mark in a tinted rounded square: 40 pt (`large`), 28 pt (`medium`) on the Limits page's tiles and detail
/// title, 24 pt (`small`) in a sidebar tile and the Rules summary bar. `glyph` is the bare 14 pt glyph in the CLI's ink, with
/// no square, for a segment label. Claude Code and Codex are drawn as a template in the CLI's ink on its tint; Gemini CLI
/// keeps its own colours. Decorative: the name is always written beside it.
struct CLIMark: View {
    enum Size { case large, medium, small, glyph }

    let cli: LimitsCLI
    var size: Size = .large

    init(_ cli: LimitsCLI, size: Size = .large) {
        self.cli = cli
        self.size = size
    }

    init(_ cli: InventoryCLI, size: Size = .large) {
        self.init(LimitsCLI(cli), size: size)
    }

    var body: some View {
        if size == .glyph {
            glyph(side: Metrics.iconInline).accessibilityHidden(true)
        } else {
            let side = switch size {
            case .large: Metrics.cliMarkSize
            case .medium: Metrics.cliMarkMediumSize
            case .small, .glyph: Metrics.cliMarkSmallSize
            }
            let shape = RoundedRectangle(cornerRadius: size == .large ? Metrics.groupRadius : Metrics.controlRadius, style: .continuous)
            ZStack {
                shape.fill(cli.tint)
                glyph(side: side * Metrics.cliMarkGlyphFraction)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func glyph(side: CGFloat) -> some View {
        if let image = BrandMark.image(cli) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(cli == .gemini ? .original : .template)
                .scaledToFit()
                .foregroundStyle(cli.ink)
                .frame(width: side, height: side)
        } else {
            Circle().fill(cli.fill).frame(width: Space.s8, height: Space.s8)
        }
    }
}

/// The brand SVGs in `Resources/Brand`: inside the app bundle, else (debug builds only) in the checkout. A missing file
/// draws a dot instead of failing.
enum BrandMark {
    private static let fileNames: [LimitsCLI: String] = [
        .claude: "claude-spark-clay.svg",
        .codex: "codex-blossom-white.svg",
        .gemini: "gemini.svg",
    ]

    @MainActor private static var cache: [LimitsCLI: NSImage] = [:]

    @MainActor
    static func image(_ cli: LimitsCLI) -> NSImage? {
        if let cached = cache[cli] { return cached }
        guard let name = fileNames[cli],
              let url = [Bundle.main.resourceURL?.appendingPathComponent("Brand/\(name)"), checkoutURL(name)]
                  .compactMap({ $0 })
                  .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[cli] = image
        return image
    }

    // A release binary must not carry the build machine's source path, so only debug builds look in the checkout.
    #if DEBUG
    private static func checkoutURL(_ name: String) -> URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Components
            .deletingLastPathComponent() // Reins
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // checkout
            .appendingPathComponent("Resources/Brand/\(name)")
    }
    #else
    private static func checkoutURL(_ name: String) -> URL? { nil }
    #endif
}
