import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Scripts/generate-app-icon.swift Resources")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvasSize = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create the app icon canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let tile = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 205, yRadius: 205)
NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.075, alpha: 1).setFill()
tile.fill()

let factory = NSAttributedString(
    string: "🏭",
    attributes: [.font: NSFont(name: "Apple Color Emoji", size: 690)!]
)
let glyphSize = factory.size()
factory.draw(at: NSPoint(x: (CGFloat(canvasSize) - glyphSize.width) / 2, y: (CGFloat(canvasSize) - glyphSize.height) / 2 + 35))

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the app icon")
}
try png.write(to: outputDirectory.appendingPathComponent("AppIcon.png"))

let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    guard let resized = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let resizedContext = NSGraphicsContext(bitmapImageRep: resized) else {
        fatalError("Could not resize the app icon")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = resizedContext
    resizedContext.imageInterpolation = .high
    bitmap.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    resizedContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = resized.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode an app icon size")
    }
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("Could not build AppIcon.icns")
}
try fileManager.removeItem(at: iconset)
