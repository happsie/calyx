#!/usr/bin/env swift
// Generates AppIcon.icns from the leaf SF Symbol with gradient.
// Usage: swift scripts/generate-icns.swift [output-path]

import AppKit

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // Background: dark rounded rect
    let cornerRadius = size * 0.22
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                               xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
    bgPath.fill()

    // Subtle border
    NSColor(white: 1, alpha: 0.08).setStroke()
    bgPath.lineWidth = size * 0.005
    bgPath.stroke()

    // Leaf symbol
    let symbolSize = size * 0.52
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .thin)
    if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {

        let leafSize = leaf.size
        let leafRect = NSRect(
            x: (size - leafSize.width) / 2,
            y: (size - leafSize.height) / 2 - size * 0.02,
            width: leafSize.width,
            height: leafSize.height
        )

        // Render gradient-filled leaf in an offscreen image
        let leafLayer = NSImage(size: NSSize(width: size, height: size))
        leafLayer.lockFocus()

        // 1) Draw the leaf as a solid shape (acts as alpha mask)
        leaf.draw(in: leafRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // 2) Draw gradient with sourceIn — keeps only where leaf alpha exists
        let gradient = NSGradient(colors: [
            NSColor(red: 0.0, green: 0.75, blue: 0.72, alpha: 1),
            NSColor(red: 0.2, green: 0.84, blue: 0.4, alpha: 1),
        ])
        NSGraphicsContext.current?.cgContext.setBlendMode(.sourceIn)
        gradient?.draw(in: rect, angle: 135)

        leafLayer.unlockFocus()

        // Composite the gradient leaf onto the background
        leafLayer.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, size: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

// Main
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("calyx-icon-\(ProcessInfo.processInfo.processIdentifier)")
try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Required icon sizes for .icns
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",        16),
    ("icon_16x16@2x",     32),
    ("icon_32x32",        32),
    ("icon_32x32@2x",     64),
    ("icon_128x128",      128),
    ("icon_128x128@2x",   256),
    ("icon_256x256",      256),
    ("icon_256x256@2x",   512),
    ("icon_512x512",      512),
    ("icon_512x512@2x",   1024),
]

let masterIcon = makeIcon(size: 1024)

for entry in sizes {
    let url = iconsetDir.appendingPathComponent("\(entry.name).png")
    savePNG(masterIcon, size: entry.px, to: url)
    print("  Generated \(entry.name).png (\(entry.px)x\(entry.px))")
}

// Convert iconset to icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created \(outputPath)")
} else {
    print("Error: iconutil failed with status \(process.terminationStatus)")
    exit(1)
}

// Cleanup
try? FileManager.default.removeItem(at: tempDir)
