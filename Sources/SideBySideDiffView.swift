import SwiftUI
import AppKit

struct SideBySideDiffView: View {
    let pairs: [SideBySidePair]
    var fileName: String = ""
    var workspace: Session? = nil
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { idx, pair in
                CommentableSideBySideRow(
                    pair: pair,
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
}

private struct CommentableSideBySideRow: View {
    let pair: SideBySidePair
    let lineId: String
    let fileName: String
    var workspace: Session?
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

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
                    highlightedContent: pair.leftHighlighted
                )

                Divider()

                SideDiffLineView(
                    line: pair.right,
                    lineType: pair.rightType,
                    highlightedContent: pair.rightHighlighted
                )
            }
            .onTapGesture {
                if workspace != nil {
                    activeCommentLineId = lineId
                }
            }

            if activeCommentLineId == lineId || submittedComments[lineId] != nil {
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
    }
}

private struct SideDiffLineView: View {
    let line: DiffLine?
    let lineType: DiffLineType
    let highlightedContent: AttributedString?

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text(lineNumber)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // Code content with pre-computed highlighting
            if let highlighted = highlightedContent {
                Text(highlighted)
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
}
