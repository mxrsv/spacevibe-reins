import AppKit
import SwiftUI

/// A bare CLI brand mark (`CLIRegistry`'s `mark`; a CLI with none, or a file that is missing, draws its tone's dot), independent of data/semantic colours: a mark keeps the asset's colour, and
/// a monochrome one (Codex) is white in dark mode and black in light mode. No background or border.
/// The transparent layout slot keeps existing row alignment and glyph sizes. Decorative: the name is beside it.
struct CLIMark: View {
    /// `glyph` is the bare mark at 14 beside 12 pt text; `control` the bare mark at 16 beside 13 pt text (a band header's
    /// lead, a row's logo in v5); `logo` the bare mark at 20 (a logo toggle, a popover's head); `ring` the bare mark at 12
    /// inside the reset countdown's ring (the glance widget).
    enum Size { case large, medium, small, glyph, control, logo, ring }

    let cli: CLIID
    var size: Size = .large

    init(_ cli: CLIID, size: Size = .large) {
        self.cli = cli
        self.size = size
    }

    var body: some View {
        if let bare = bareSide {
            glyph(side: bare).accessibilityHidden(true)
        } else {
            let side = switch size {
            case .large: Metrics.cliMarkSize
            case .medium: Metrics.cliMarkMediumSize
            case .small, .glyph, .control, .logo, .ring: Metrics.cliMarkSmallSize
            }
            glyph(side: side * Metrics.cliMarkGlyphFraction)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }

    /// The bare sizes draw the mark alone at that side, with no frame around it.
    private var bareSide: CGFloat? {
        switch size {
        case .glyph: Metrics.iconInline
        case .control: Metrics.iconControl
        case .logo: Metrics.LogoToggle.logo
        case .ring: Metrics.iconSmall
        case .large, .medium, .small: nil
        }
    }

    @ViewBuilder
    private func glyph(side: CGFloat) -> some View {
        let identity = cli.identity
        if let mark = identity.mark, let image = BrandMark.image(mark) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(mark.isMonochrome ? .template : .original)
                .scaledToFit()
                .foregroundStyle(Palette.brandMonochrome)
                .frame(width: side, height: side)
        } else {
            Circle().fill(identity.tone.fill).frame(width: Space.s8, height: Space.s8)
        }
    }
}

/// The brand SVGs in `Resources/Brand` (file names in `CLIRegistry`): inside the app bundle, else (debug builds only) in the
/// checkout. A missing file draws a dot instead of failing.
enum BrandMark {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(_ mark: CLIMarkArt) -> NSImage? {
        let name = mark.fileName
        if let cached = cache[name] { return cached }
        guard let url = [Bundle.main.resourceURL?.appendingPathComponent("Brand/\(name)"), checkoutURL(name)]
                  .compactMap({ $0 })
                  .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    // A release binary must not carry the build machine's source path, so only debug builds look in the checkout.
    #if DEBUG
    private static func checkoutURL(_ name: String) -> URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Components
            .deletingLastPathComponent() // SpaceVibe
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // checkout
            .appendingPathComponent("Resources/Brand/\(name)")
    }
    #else
    private static func checkoutURL(_ name: String) -> URL? { nil }
    #endif
}
