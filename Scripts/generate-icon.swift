import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift generate-icon.swift <iconset-directory> <source-image>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
_ = NSApplication.shared
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load icon source: \(sourceURL.path)\n", stderr)
    exit(2)
}

// The source is a screenshot. This rectangle isolates the white app icon and
// excludes the surrounding blue screenshot background.
let sourceIconRect = NSRect(x: 10, y: 6, width: 220, height: 220)

let variants: [(pixels: Int, filename: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    context.imageInterpolation = .high
    context.shouldAntialias = true

    let size = NSSize(width: pixels, height: pixels)

    let outerRect = NSRect(origin: .zero, size: size).insetBy(
        dx: CGFloat(pixels) * 0.035,
        dy: CGFloat(pixels) * 0.035
    )
    let outerPath = NSBezierPath(
        roundedRect: outerRect,
        xRadius: CGFloat(pixels) * 0.22,
        yRadius: CGFloat(pixels) * 0.22
    )
    outerPath.addClip()
    sourceImage.draw(
        in: outerRect,
        from: sourceIconRect,
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSColor.white.withAlphaComponent(0.92).setStroke()
    outerPath.lineWidth = max(1, CGFloat(pixels) * 0.012)
    outerPath.stroke()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
}
