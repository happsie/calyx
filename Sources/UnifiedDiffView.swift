import SwiftUI
import AppKit

struct UnifiedDiffLineView: View {
    let line: DiffLine
    let highlightedContent: AttributedString

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber.map { String(format: "%4d", $0) } ?? "    ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)

            // New line number
            Text(line.newLineNumber.map { String(format: "%4d", $0) } ?? "    ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)

            // +/- prefix
            Text(prefix)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 20, alignment: .center)

            // Code content with pre-computed syntax highlighting
            Text(highlightedContent)
                .font(.system(size: 13, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        .background(lineBackground)
    }

    private var prefix: String {
        switch line.type {
        case .added: "+"
        case .removed: "-"
        case .unchanged: " "
        }
    }

    private var prefixColor: Color {
        switch line.type {
        case .added: Color(nsColor: .init(red: 46/255, green: 160/255, blue: 67/255, alpha: 0.8))
        case .removed: Color(nsColor: .init(red: 248/255, green: 81/255, blue: 73/255, alpha: 0.8))
        case .unchanged: .clear
        }
    }

    private var lineBackground: Color {
        switch line.type {
        case .added: Color(nsColor: DiffSyntaxHighlighter.addedBg)
        case .removed: Color(nsColor: DiffSyntaxHighlighter.removedBg)
        case .unchanged: .clear
        }
    }
}
