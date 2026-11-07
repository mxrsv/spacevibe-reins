import CoreText
import Foundation

/// Inter 4 variable (SIL OFL 1.1, `Resources/Fonts/OFL.txt`), the app's only typeface.
///
/// It registers for this process the first time a text role asks for a font, so no entry point (the window, the screenshot
/// mode, a test) can draw before it. A packaged app reads it from `Contents/Resources/Fonts`, which `scripts/build-app.sh`
/// copies in before signing; a debug build run from the checkout (`scripts/dev.sh`, `scripts/dev-fixture.sh`, tests) reads
/// the repo's `Resources/Fonts`. CoreText takes the `.woff2` directly.
///
/// Numbers that line up down a column (runs, cost, counts) take tabular digits. Prose does not: Inter's `tnum` also gives the
/// hyphen a digit's width, which spreads "diagnosing-bugs" and "2026-10-06" apart. A machine string (command, path, key, rule
/// pattern) gets `ss02` and `zero` instead: a slashed zero and distinct l, I and 1, in place of a monospaced face. The v5
/// roles add `cv11` and `ss03` (single-storey a, round quotes and commas), as the frozen mock's body does.
enum InterFont {
    static let fileName = "InterVariable.woff2"

    enum Weight {
        /// 400, 450 (a v5 row name), 500 and 600.
        case regular, book, medium, semibold

        /// The named instances of the variable font. `book` has none: it is the regular instance moved on the weight axis.
        var postScriptName: String {
            switch self {
            case .regular, .book: "InterVariable"
            case .medium: "InterVariable-Medium"
            case .semibold: "InterVariable-SemiBold"
            }
        }

        /// The `wght` axis value for a weight that is not a named instance.
        var axisValue: Double? { self == .book ? 450 : nil }
    }

    /// The OpenType `wght` axis tag as CoreText's numeric identifier.
    static let weightAxis = 0x7767_6874

    /// True once the font is registered for this process. Evaluated once.
    static let isRegistered: Bool = register()

    static func font(_ weight: Weight, size: CGFloat, code: Bool = false, tabular: Bool = false, stylistic: Bool = false) -> CTFont {
        _ = isRegistered
        var settings: [[CFString: Any]] = []
        if tabular { settings.append(feature("tnum")) }
        if code { settings += [feature("ss02"), feature("zero")] }
        if stylistic { settings += [feature("cv11"), feature("ss03")] }
        var attributes: [CFString: Any] = [kCTFontNameAttribute: weight.postScriptName, kCTFontFeatureSettingsAttribute: settings]
        if let axis = weight.axisValue { attributes[kCTFontVariationAttribute] = [weightAxis: axis] }
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }

    /// The font file this process registers: inside the app bundle, else (debug builds only) in the checkout.
    static func fileURL() -> URL? {
        [Bundle.main.resourceURL?.appendingPathComponent("Fonts/\(fileName)"), checkoutURL]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func register() -> Bool {
        guard let url = fileURL() else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        guard let error = error?.takeRetainedValue() else { return false }
        return CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue
    }

    private static func feature(_ tag: String) -> [CFString: Any] {
        [kCTFontOpenTypeFeatureTag: tag, kCTFontOpenTypeFeatureValue: 1]
    }

    // A release binary must not carry the build machine's source path, so only debug builds look in the checkout.
    #if DEBUG
    private static var checkoutURL: URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tokens
            .deletingLastPathComponent() // Reins
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // checkout
            .appendingPathComponent("Resources/Fonts/\(fileName)")
    }
    #else
    private static let checkoutURL: URL? = nil
    #endif
}
