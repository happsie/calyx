import SwiftUI

struct SubmittedComment: Identifiable, Codable {
    let id: UUID
    var commentText: String
    let fileName: String
    let lineNumber: Int
    let lineContent: String
    let timestamp: Date

    init(commentText: String, fileName: String, lineNumber: Int, lineContent: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.commentText = commentText
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.timestamp = timestamp
    }
}

struct SentCommentBatch: Identifiable, Codable {
    let id: UUID
    let comments: [SubmittedComment]
    let sentAt: Date

    init(comments: [SubmittedComment], sentAt: Date = Date()) {
        self.id = UUID()
        self.comments = comments
        self.sentAt = sentAt
    }
}

// MARK: - Comment Editor

struct DiffCommentEditor: View {
    let fileName: String
    let lineNumber: Int
    let lineContent: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var commentText = ""
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Comment on line \(lineNumber)", systemImage: "text.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Add your comment...", text: $commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .lineLimit(3...8)
                .padding(8)
                .background(.quinary)
                .clipShape(.rect(cornerRadius: 6))
                .focused($isFocused)

            HStack {
                Text("Cmd+Enter to add")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Comment", action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trimmedText.isEmpty)
            }
            .controlSize(.regular)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        }
        .padding(.horizontal, 100)
        .padding(.vertical, 4)
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !trimmedText.isEmpty else { return }
        onSubmit(trimmedText)
    }
}

// MARK: - Comment Bubble

struct DiffCommentBubble: View {
    let comment: SubmittedComment
    var isSent: Bool = false
    var onEdit: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSent ? "checkmark.bubble.fill" : "bubble.left.fill")
                .font(.caption2)
                .foregroundStyle(isSent ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .padding(.top, 2)

            if isEditing {
                editView
            } else {
                displayView
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.separator)
        }
        .opacity(isSent ? 0.6 : 1.0)
        .onHover { isHovering = $0 }
        .padding(.horizontal, 100)
        .padding(.vertical, 2)
    }

    private var displayView: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(comment.commentText)
                    .font(.body.monospaced())
                    .foregroundStyle(isSent ? .secondary : .primary)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    if isSent {
                        Text("Sent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(comment.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if isHovering && !isSent {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if onEdit != nil {
                Button { beginEditing() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.accessoryBar)
                .help("Edit comment")
            }

            if onDelete != nil {
                Button(role: .destructive) { onDelete?() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.accessoryBar)
                .help("Delete comment")
            }
        }
    }

    private var editView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Edit comment...", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .lineLimit(2...6)
                .padding(6)
                .background(.quinary)
                .clipShape(.rect(cornerRadius: 4))
                .focused($editFocused)

            HStack {
                Spacer()
                Button("Cancel") { isEditing = false }
                Button("Save", action: saveEdit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.regular)
        }
    }

    private func beginEditing() {
        editText = comment.commentText
        isEditing = true
        editFocused = true
    }

    private func saveEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onEdit?(trimmed)
        isEditing = false
    }
}

// MARK: - Comment List (shared between unified and side-by-side)

struct CommentListView: View {
    let lineId: String
    let fileName: String
    let lineNumber: Int
    let lineContent: String
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]
    var body: some View {
        if activeCommentLineId == lineId {
            DiffCommentEditor(
                fileName: fileName,
                lineNumber: lineNumber,
                lineContent: lineContent,
                onSubmit: { text in addComment(text) },
                onCancel: { activeCommentLineId = nil }
            )
        }

        if let comments = submittedComments[lineId] {
            ForEach(comments) { comment in
                DiffCommentBubble(
                    comment: comment,
                    onEdit: { newText in updateComment(id: comment.id, newText: newText) },
                    onDelete: { deleteComment(id: comment.id) }
                )
            }
        }
    }

    private func addComment(_ text: String) {
        let comment = SubmittedComment(
            commentText: text,
            fileName: fileName,
            lineNumber: lineNumber,
            lineContent: lineContent
        )
        submittedComments[lineId, default: []].append(comment)
        activeCommentLineId = nil
    }

    private func updateComment(id: UUID, newText: String) {
        guard let idx = submittedComments[lineId]?.firstIndex(where: { $0.id == id }) else { return }
        submittedComments[lineId]?[idx].commentText = newText
    }

    private func deleteComment(id: UUID) {
        submittedComments[lineId]?.removeAll { $0.id == id }
        if submittedComments[lineId]?.isEmpty == true {
            submittedComments.removeValue(forKey: lineId)
        }
    }
}
