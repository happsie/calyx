import AppKit

/// Renders the Calyx app icon — a leaf.fill SF Symbol with a teal-to-green gradient
/// on a dark rounded-rect background. Used both at runtime (dock icon) and for .icns generation.
enum AppIconRenderer {

    static func makeIcon(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)

        // Background: dark rounded rect (macOS icon shape)
        let cornerRadius = size * 0.22
        let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                                   xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
        bgPath.fill()

        // Subtle inner shadow / border
        NSColor(white: 1, alpha: 0.08).setStroke()
        bgPath.lineWidth = size * 0.005
        bgPath.stroke()

        // Leaf symbol — rendered in a separate image so sourceIn doesn't affect the background
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
                NSColor(red: 0.0, green: 0.75, blue: 0.72, alpha: 1),  // teal
                NSColor(red: 0.2, green: 0.84, blue: 0.4, alpha: 1),   // green
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

    /// Sets the app's dock icon to the rendered leaf icon.
    static func setAsDockIcon() {
        NSApp.applicationIconImage = makeIcon(size: 512)
    }
}
