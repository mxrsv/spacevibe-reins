import Foundation
import SwiftUI
import Testing
@testable import Reins

/// Text on the v4 solid fills stays readable (spec `docs/specs/2026-11-03-reins-design-language.md`, v4 changes, DL11):
/// white on `accentSolid` and on the light success and danger fills, `#141414` on warn and on the dark fills, each at
/// least 4.5:1 by WCAG 2. The colours are read from `Palette` itself, resolved the way a view resolves them.
@MainActor
@Suite("Palette contrast on solid fills")
struct PaletteContrastTests {
    struct RGBA {
        let red, green, blue, alpha: Double
    }

    static func resolved(_ color: Color, _ scheme: ColorScheme) -> RGBA {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let value = color.resolve(in: environment)
        return RGBA(red: Double(value.red), green: Double(value.green), blue: Double(value.blue), alpha: Double(value.opacity))
    }

    /// WCAG 2 relative luminance of a gamma-encoded sRGB colour.
    static func luminance(_ c: RGBA) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    static func ratio(_ text: Color, on fill: Color, _ scheme: ColorScheme) -> Double {
        let a = luminance(resolved(text, scheme)), b = luminance(resolved(fill, scheme))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func hex(_ c: RGBA) -> Int {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return byte(c.red) << 16 | byte(c.green) << 8 | byte(c.blue)
    }

    @Test("the palette resolves per appearance, so the ratios below read both")
    func resolvesPerAppearance() {
        #expect(Self.hex(Self.resolved(Palette.text, .light)) == 0x141414)
        #expect(Self.hex(Self.resolved(Palette.text, .dark)) == 0xF2F2F2)
        #expect(Self.hex(Self.resolved(Palette.accentSolid, .light)) == 0x3250D8)
        #expect(Self.hex(Self.resolved(Palette.accentSolid, .dark)) == 0x4164ED)
    }

    @Test("white on accentSolid, in both appearances")
    func onAccent() {
        for scheme in [ColorScheme.light, .dark] {
            #expect(Self.hex(Self.resolved(Palette.onAccent, scheme)) == 0xFFFFFF)
            let ratio = Self.ratio(Palette.onAccent, on: Palette.accentSolid, scheme)
            #expect(ratio >= 4.5, "white on accentSolid in \(scheme): \(ratio)")
        }
    }

    @Test("white on the light success and danger fills, #141414 on warn and on the dark fills")
    func onStateFills() {
        let cases: [(name: String, text: Color, fill: Color, light: Int, dark: Int)] = [
            ("success", Palette.onSuccess, Palette.success, 0xFFFFFF, 0x141414),
            ("danger", Palette.onDanger, Palette.danger, 0xFFFFFF, 0x141414),
            ("warn", Palette.onWarn, Palette.warn, 0x141414, 0x141414),
        ]
        for item in cases {
            #expect(Self.hex(Self.resolved(item.text, .light)) == item.light, "\(item.name) text in light")
            #expect(Self.hex(Self.resolved(item.text, .dark)) == item.dark, "\(item.name) text in dark")
            for scheme in [ColorScheme.light, .dark] {
                let ratio = Self.ratio(item.text, on: item.fill, scheme)
                #expect(ratio >= 4.5, "text on \(item.name) in \(scheme): \(ratio)")
            }
        }
    }

    @Test("the v4 control tokens hold the spec's values")
    func controlTokens() {
        let solid: [(String, Color, Int, Int)] = [
            ("controlFill", Palette.controlFill, 0xFFFFFF, 0x3D3D3D),
            ("controlFillHover", Palette.controlFillHover, 0xFAFAFA, 0x454545),
            ("controlFillPressed", Palette.controlFillPressed, 0xEBEBEB, 0x323232),
            ("accentHover", Palette.accentHover, 0x4A6CF0, 0x4A6CF0),
            ("accentPressed", Palette.accentPressed, 0x2C47C4, 0x2C47C4),
        ]
        for (name, color, light, dark) in solid {
            #expect(Self.hex(Self.resolved(color, .light)) == light, "\(name) in light")
            #expect(Self.hex(Self.resolved(color, .dark)) == dark, "\(name) in dark")
        }
        let alpha: [(String, Color, Double, Double)] = [
            ("controlHairline", Palette.controlHairline, 0.16, 0.7),
            ("controlShadow", Palette.controlShadow, 0.12, 0.45),
            ("controlHighlight", Palette.controlHighlight, 0.9, 0.09),
        ]
        for (name, color, light, dark) in alpha {
            #expect(abs(Self.resolved(color, .light).alpha - light) < 0.01, "\(name) in light")
            #expect(abs(Self.resolved(color, .dark).alpha - dark) < 0.01, "\(name) in dark")
        }
        #expect(Self.hex(Self.resolved(Palette.segmentTrack, .dark)) == 0x1F1F1F)
        #expect(Self.resolved(Palette.segmentTrack, .light).alpha < 0.01)
        #expect(Metrics.cardButtonHeight == 32 && Metrics.controlHeight == 28)
    }
}
