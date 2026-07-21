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
    let blue = NSColor(srgbRed: 0.46, green: 0.68, blue: 0.93, alpha: 1)
    blue.setFill()
    outerPath.fill()

    let markSize = CGFloat(pixels) * 0.30
    let markRect = NSRect(
        x: (CGFloat(pixels) - markSize) / 2,
        y: (CGFloat(pixels) - markSize) / 2 + CGFloat(pixels) * 0.01,
        width: markSize,
        height: markSize
    )
    let markPath = NSBezierPath(
        roundedRect: markRect,
        xRadius: markSize * 0.24,
        yRadius: markSize * 0.24
    )
    NSColor.white.setFill()
    markPath.fill()

    let slotRect = NSRect(
        x: markRect.midX - markSize * 0.13,
        y: markRect.minY + markSize * 0.60,
        width: markSize * 0.26,
        height: max(1, markSize * 0.055)
    )
    let slotPath = NSBezierPath(
        roundedRect: slotRect,
        xRadius: slotRect.height / 2,
        yRadius: slotRect.height / 2
    )
    blue.setFill()
    slotPath.fill()

    let smilePath = NSBezierPath()
    smilePath.move(to: NSPoint(
        x: markRect.midX - markSize * 0.13,
        y: markRect.minY + markSize * 0.37
    ))
    smilePath.curve(
        to: NSPoint(
            x: markRect.midX + markSize * 0.13,
            y: markRect.minY + markSize * 0.37
        ),
        controlPoint1: NSPoint(
            x: markRect.midX - markSize * 0.07,
            y: markRect.minY + markSize * 0.27
        ),
        controlPoint2: NSPoint(
            x: markRect.midX + markSize * 0.07,
            y: markRect.minY + markSize * 0.27
        )
    )
    smilePath.lineWidth = max(1, CGFloat(pixels) * 0.012)
    smilePath.lineCapStyle = .round
    blue.setStroke()
    smilePath.stroke()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
}
