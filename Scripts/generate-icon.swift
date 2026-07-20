import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate-icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
_ = NSApplication.shared
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

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
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.16, green: 0.46, blue: 0.92, alpha: 1),
        ending: NSColor(srgbRed: 0.08, green: 0.25, blue: 0.63, alpha: 1)
    )!
    gradient.draw(in: outerPath, angle: -55)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    outerPath.lineWidth = max(1, CGFloat(pixels) * 0.01)
    outerPath.stroke()

    let configuration = NSImage.SymbolConfiguration(
        pointSize: CGFloat(pixels) * 0.45,
        weight: .semibold
    )
    let palette = NSImage.SymbolConfiguration(paletteColors: [.white])
    if let symbol = NSImage(
        systemSymbolName: "lock.square.stack.fill",
        accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration.applying(palette)) {
        let symbolSize = symbol.size
        let symbolRect = NSRect(
            x: (CGFloat(pixels) - symbolSize.width) / 2,
            y: (CGFloat(pixels) - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: symbolRect)
    }

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
}
