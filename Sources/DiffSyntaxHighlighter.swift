import AppKit
import Highlighter

final class DiffSyntaxHighlighter {

    // Dynamic colors that resolve per-appearance
    static let baseBg = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    }

    static let addedBg = NSColor(name: nil) { appearance in
        appearance.isDark
            ? blendColors(NSColor(red: 46/255, green: 160/255, blue: 67/255, alpha: 1),
                          over: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1), alpha: 0.15)
            : blendColors(NSColor(red: 46/255, green: 160/255, blue: 67/255, alpha: 1),
                          over: .white, alpha: 0.12)
    }

    static let removedBg = NSColor(name: nil) { appearance in
        appearance.isDark
            ? blendColors(NSColor(red: 248/255, green: 81/255, blue: 73/255, alpha: 1),
                          over: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1), alpha: 0.15)
            : blendColors(NSColor(red: 248/255, green: 81/255, blue: 73/255, alpha: 1),
                          over: .white, alpha: 0.12)
    }

    static let addedInlineBg = NSColor(name: nil) { appearance in
        appearance.isDark
            ? blendColors(NSColor(red: 46/255, green: 160/255, blue: 67/255, alpha: 1),
                          over: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1), alpha: 0.35)
            : blendColors(NSColor(red: 46/255, green: 160/255, blue: 67/255, alpha: 1),
                          over: .white, alpha: 0.25)
    }

    static let removedInlineBg = NSColor(name: nil) { appearance in
        appearance.isDark
            ? blendColors(NSColor(red: 248/255, green: 81/255, blue: 73/255, alpha: 1),
                          over: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1), alpha: 0.35)
            : blendColors(NSColor(red: 248/255, green: 81/255, blue: 73/255, alpha: 1),
                          over: .white, alpha: 0.25)
    }

    private static func blendColors(_ fg: NSColor, over bg: NSColor, alpha: CGFloat) -> NSColor {
        let f = fg.usingColorSpace(.sRGB)!
        let b = bg.usingColorSpace(.sRGB)!
        return NSColor(
            red: b.redComponent + (f.redComponent - b.redComponent) * alpha,
            green: b.greenComponent + (f.greenComponent - b.greenComponent) * alpha,
            blue: b.blueComponent + (f.blueComponent - b.blueComponent) * alpha,
            alpha: 1
        )
    }

    private let highlighter: Highlighter
    private let language: String
    private let isDark: Bool

    private var fallbackAttrs: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: isDark
                ? NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
                : NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1),
        ]
    }

    init(language: String = "swift", isDark: Bool = true) {
        self.language = language
        self.isDark = isDark
        if let hl = Highlighter() {
            hl.setTheme(isDark ? "atom-one-dark" : "atom-one-light")
            highlighter = hl
        } else {
            highlighter = Highlighter()!
        }
    }

    func highlight(line: String) -> NSAttributedString {
        if let result = highlighter.highlight(line, as: language) {
            return result
        }
        return NSAttributedString(string: line, attributes: fallbackAttrs)
    }

    func applyDiffBackground(
        _ attributed: NSAttributedString,
        lineType: DiffLineType,
        inlineChanges: [InlineChange]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: result.length)

        // Ensure monospaced font
        result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)

        // Apply line-level background
        switch lineType {
        case .added:
            result.addAttribute(.backgroundColor, value: Self.addedBg, range: fullRange)
        case .removed:
            result.addAttribute(.backgroundColor, value: Self.removedBg, range: fullRange)
        case .unchanged:
            break
        }

        // Apply inline change highlights
        for change in inlineChanges {
            let clampedLength = min(change.range.length, result.length - change.range.location)
            guard clampedLength > 0, change.range.location < result.length else { continue }
            let safeRange = NSRange(location: change.range.location, length: clampedLength)
            let color = change.isAddition ? Self.addedInlineBg : Self.removedInlineBg
            result.addAttribute(.backgroundColor, value: color, range: safeRange)
        }

        return result
    }
}

// MARK: - Appearance Helpers

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
