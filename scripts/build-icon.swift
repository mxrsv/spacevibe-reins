import AppKit
import Foundation

// Renders Resources/AppIcon.svg (the Reins mark, same artwork as the site's favicon) into a
// macOS iconset: the 1024-point canvas with the mark on the standard 824-point squircle, so
// the Dock and Finder show it at the same size as every other app icon. The caller passes a
// temporary directory; only the compiled .icns enters the app bundle (scripts/build-app.sh).
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: swift scripts/build-icon.swift <mark.svg> <output.iconset>\n", stderr)
    exit(2)
}
guard let mark = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])), mark.isValid else {
    fputs("Could not read the SVG mark at \(arguments[1])\n", stderr)
    exit(1)
}
let destination = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let inset: CGFloat = 100 // Apple's macOS icon grid: the squircle fills 824 of 1024 points.
let sizes = [16, 32, 128, 256, 512]
for points in sizes {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not allocate the \(pixels) px icon bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let ratio = CGFloat(pixels) / canvas
        let frame = NSRect(x: inset * ratio, y: inset * ratio,
                           width: (canvas - 2 * inset) * ratio, height: (canvas - 2 * inset) * ratio)
        mark.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode the \(pixels) px icon")
        }
        let suffix = scale == 1 ? "" : "@2x"
        try png.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
