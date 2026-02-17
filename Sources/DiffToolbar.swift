import SwiftUI

struct DiffToolbar: View {
    @Binding var mode: DiffViewMode
    var fileCount: Int = 0
    var commentCount: Int = 0
    var sentCommentHistory: [SentCommentBatch] = []
    var onSendAllComments: (() -> Void)? = nil

    @State private var showHistoryPopover = false

    var body: some View {
        HStack {
            if fileCount > 0 {
                Text("\(fileCount) file\(fileCount == 1 ? "" : "s") changed")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if !sentCommentHistory.isEmpty {
                Button {
                    showHistoryPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                        Text("\(sentCommentHistory.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Sent comment history")
                .popover(isPresented: $showHistoryPopover, arrowEdge: .bottom) {
                    SentCommentHistoryPopover(batches: sentCommentHistory)
                }
            }

            if commentCount > 0, let onSend = onSendAllComments {
                Button {
                    onSend()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11))
                        Text("Send \(commentCount) comment\(commentCount == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Picker("View Mode", selection: $mode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Sent Comment History Popover

private struct SentCommentHistoryPopover: View {
    let batches: [SentCommentBatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sent Comments")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(totalCount) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(batches.reversed()) { batch in
                        SentBatchSection(batch: batch)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 420, height: min(CGFloat(batches.count) * 120 + 40, 500))
    }

    private var totalCount: Int {
        batches.reduce(0) { $0 + $1.comments.count }
    }
}

private struct SentBatchSection: View {
    let batch: SentCommentBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Sent \(batch.comments.count) comment\(batch.comments.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(batch.sentAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("ago")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            ForEach(batch.comments) { comment in
                SentCommentRow(comment: comment)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SentCommentRow: View {
    let comment: SubmittedComment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(shortFileName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(":\(comment.lineNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(comment.commentText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(.rect(cornerRadius: 4))
    }

    private var shortFileName: String {
        (comment.fileName as NSString).lastPathComponent
    }
}
