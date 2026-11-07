import Foundation
@testable import Reins

/// Colour arithmetic for `ContrastTests` and `HuePolicyTests`, on the values in `PaletteValue` (sRGB, WCAG 2 relative
/// luminance, OKLCH after Björn Ottosson's reference matrices).
enum Appearance: String, CaseIterable, Sendable {
    case light, dark
}

/// An opaque sRGB colour, 0 to 1 per channel.
struct RGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

extension ColorValue {
    func rgb(_ appearance: Appearance) -> RGB { RGB(hex: appearance == .dark ? dark : light) }
    func alpha(_ appearance: Appearance) -> Double { appearance == .dark ? darkAlpha : lightAlpha }
}

/// One layer of a composited ground: a token at its own alpha, or at `alpha` when a component sets one (a tab chip's
/// category at 26%).
struct Layer: Sendable {
    let value: ColorValue
    var alpha: Double?

    init(_ value: ColorValue, alpha: Double? = nil) {
        self.value = value
        self.alpha = alpha
    }
}

enum ColorMath {
    /// Layers painted bottom to top; the first must be opaque. `brighten` adds to each channel afterwards, as SwiftUI's
    /// `.brightness` does on the primary button's hover (an approximation of its filter).
    static func composite(_ layers: [Layer], _ appearance: Appearance, brighten: Double = 0) -> RGB {
        precondition(layers.first.map { $0.value.alpha(appearance) == 1 && $0.alpha == nil } ?? false, "the bottom layer must be opaque")
        var result = layers[0].value.rgb(appearance)
        for layer in layers.dropFirst() {
            let top = layer.value.rgb(appearance)
            let a = layer.alpha ?? layer.value.alpha(appearance)
            result = RGB(r: top.r * a + result.r * (1 - a), g: top.g * a + result.g * (1 - a), b: top.b * a + result.b * (1 - a))
        }
        guard brighten != 0 else { return result }
        return RGB(r: min(1, result.r + brighten), g: min(1, result.g + brighten), b: min(1, result.b + brighten))
    }

    static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ c: RGB) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    static func contrast(_ x: RGB, _ y: RGB) -> Double {
        let (a, b) = (luminance(x), luminance(y))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// OKLCH lightness, chroma and hue in degrees (0 to 360).
    static func oklch(_ c: RGB) -> (l: Double, c: Double, h: Double) {
        let (r, g, b) = (linear(c.r), linear(c.g), linear(c.b))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let hue = atan2(bb, a) * 180 / .pi
        return (lightness, (a * a + bb * bb).squareRoot(), hue < 0 ? hue + 360 : hue)
    }

    /// The shorter way round the hue circle, 0 to 180.
    static func hueDistance(_ x: Double, _ y: Double) -> Double {
        let d = abs(x - y).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}
