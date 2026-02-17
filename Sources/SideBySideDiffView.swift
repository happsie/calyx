import SwiftUI
import AppKit

struct SideBySideDiffView: View {
    let diffLines: [DiffLine]
    let highlighter: DiffSyntaxHighlighter
    var fileName: String = ""
    var workspace: Session? = nil
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(buildPairs().enumerated()), id: \.offset) { idx, pair in
                CommentableSideBySideRow(
                    pair: pair,
                    highlighter: highlighter,
                    lineId: "\(fileName):sbs:\(idx)",
                    fileName: fileName,
                    workspace: workspace,
                    activeCommentLineId: $activeCommentLineId,
                    submittedComments: $submittedComments
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    struct LinePair {
        let left: DiffLine?
        let right: DiffLine?
        let leftType: DiffLineType
        let rightType: DiffLineType
    }

    func buildPairs() -> [LinePair] {
        var pairs: [LinePair] = []
        var i = 0

        while i < diffLines.count {
            let line = diffLines[i]

            switch line.type {
            case .unchanged:
                pairs.append(LinePair(left: line, right: line, leftType: .unchanged, rightType: .unchanged))
                i += 1

            case .removed:
                if i + 1 < diffLines.count, diffLines[i + 1].type == .added {
                    pairs.append(LinePair(
                        left: line, right: diffLines[i + 1],
                        leftType: .removed, rightType: .added
                    ))
                    i += 2
                } else {
                    pairs.append(LinePair(left: line, right: nil, leftType: .removed, rightType: .unchanged))
                    i += 1
                }

            case .added:
                pairs.append(LinePair(left: nil, right: line, leftType: .unchanged, rightType: .added))
                i += 1
            }
        }

        return pairs
    }
}

private struct CommentableSideBySideRow: View {
    let pair: SideBySideDiffView.LinePair
    let highlighter: DiffSyntaxHighlighter
    let lineId: String
    let fileName: String
    var workspace: Session?
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    @State private var isHovering = false

    private var commentLine: DiffLine? {
        pair.right ?? pair.left
    }

    private var displayLineNumber: Int {
        commentLine?.newLineNumber ?? commentLine?.oldLineNumber ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                SideDiffLineView(
                    line: pair.left,
                    lineType: pair.leftType,
                    highlighter: highlighter
                )

                Divider()

                SideDiffLineView(
                    line: pair.right,
                    lineType: pair.rightType,
                    highlighter: highlighter
                )
            }
            .overlay(alignment: .leading) {
                if workspace != nil && isHovering {
                    addCommentButton
                }
            }
            .onHover { isHovering = $0 }
            .onTapGesture {
                if workspace != nil {
                    activeCommentLineId = lineId
                }
            }

            CommentListView(
                lineId: lineId,
                fileName: fileName,
                lineNumber: displayLineNumber,
                lineContent: commentLine?.content ?? "",
                activeCommentLineId: $activeCommentLineId,
                submittedComments: $submittedComments
            )
        }
    }

    private var addCommentButton: some View {
        Button { activeCommentLineId = lineId } label: {
            Image(systemName: "plus.bubble")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.6))
                .clipShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .help("Add comment")
    }
}

private struct SideDiffLineView: View {
    let line: DiffLine?
    let lineType: DiffLineType
    let highlighter: DiffSyntaxHighlighter

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text(lineNumber)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // Code content
            if let line {
                Text(attributedContent(for: line))
                    .font(.system(size: 13, design: .monospaced))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        .background(lineBackground)
    }

    private var lineNumber: String {
        guard let line else { return "    " }
        let num = line.oldLineNumber ?? line.newLineNumber
        return num.map { String(format: "%4d", $0) } ?? "    "
    }

    private var lineBackground: Color {
        switch lineType {
        case .added: Color(nsColor: DiffSyntaxHighlighter.addedBg)
        case .removed: Color(nsColor: DiffSyntaxHighlighter.removedBg)
        case .unchanged: .clear
        }
    }

    private func attributedContent(for line: DiffLine) -> AttributedString {
        let nsAttr = highlighter.highlight(line: line.content)
        let withDiff = highlighter.applyDiffBackground(
            nsAttr,
            lineType: lineType,
            inlineChanges: line.inlineChanges
        )
        return (try? AttributedString(withDiff, including: \.appKit)) ?? AttributedString(line.content)
    }
}
