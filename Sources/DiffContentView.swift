import SwiftUI
import AppKit

struct DiffContentView: View {
    let fileDiffs: [FileDiff]
    var diffRevision: Int = 0
    var workspace: Session? = nil
    var onSwitchToAgent: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppSettings.self) private var appSettings
    @State private var viewMode: DiffViewMode = .unified
    @State private var didApplyDefault = false
    @State private var computedFiles: [ComputedFileDiff] = []
    @State private var scrollTarget: UUID?
    @State private var activeCommentLineId: String? = nil
    @State private var localComments: [String: [SubmittedComment]] = [:]

    private var commentsBinding: Binding<[String: [SubmittedComment]]> {
        if let workspace {
            Binding(
                get: { workspace.submittedComments },
                set: { workspace.submittedComments = $0 }
            )
        } else {
            $localComments
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffToolbar(
                mode: $viewMode,
                fileCount: fileDiffs.count,
                commentCount: workspace?.totalCommentCount ?? 0,
                sentCommentHistory: workspace?.sentCommentHistory ?? [],
                onSendAllComments: workspace.map { ws in {
                    ws.sendAllComments()
                    let switchTab = onSwitchToAgent
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        await MainActor.run { switchTab?() }
                    }
                } }
            )

            Divider()

            if fileDiffs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No changes yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Diffs will appear here as files are modified")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if computedFiles.isEmpty {
                ProgressView("Computing diffs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    switch viewMode {
                    case .unified:
                        UnifiedMultiFileView(
                            files: computedFiles,
                            scrollTarget: $scrollTarget,
                            workspace: workspace,
                            activeCommentLineId: $activeCommentLineId,
                            submittedComments: commentsBinding
                        )
                    case .sideBySide:
                        SideBySideMultiFileView(
                            files: computedFiles,
                            scrollTarget: $scrollTarget,
                            workspace: workspace,
                            activeCommentLineId: $activeCommentLineId,
                            submittedComments: commentsBinding
                        )
                    }

                    Divider()

                    DiffFileList(files: computedFiles, scrollTarget: $scrollTarget)
                        .frame(width: 240)
                }
            }
        }
        .task(id: DiffComputeKey(revision: diffRevision, colorScheme: colorScheme)) {
            await computeAllDiffs()
        }
        .onAppear {
            guard !didApplyDefault else { return }
            didApplyDefault = true
            viewMode = appSettings.defaultDiffMode
        }
    }

    private func computeAllDiffs() async {
        let isDark = colorScheme == .dark
        let results = await Task.detached {
            fileDiffs.map { file in
                let lines = DiffComputer.computeDiff(old: file.oldText, new: file.newText)
                let highlighter = DiffSyntaxHighlighter(language: file.language, isDark: isDark)
                return ComputedFileDiff(
                    fileName: file.fileName,
                    changeType: file.changeType,
                    diffLines: lines,
                    highlighter: highlighter
                )
            }
        }.value

        await MainActor.run {
            self.computedFiles = results
        }
    }
}

private struct DiffComputeKey: Equatable {
    let revision: Int
    let colorScheme: ColorScheme
}

struct ComputedFileDiff: Identifiable {
    let id = UUID()
    let fileName: String
    let changeType: FileChangeType
    let diffLines: [DiffLine]
    let highlighter: DiffSyntaxHighlighter
}

// MARK: - File Header

struct FileHeaderView: View {
    let fileName: String
    let changeType: FileChangeType

    var body: some View {
        HStack(spacing: 8) {
            Text(changeType.rawValue)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(badgeForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeBackground, in: RoundedRectangle(cornerRadius: 4))

            Text(fileName)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .separatorColor).opacity(0.3))
    }

    private var badgeForeground: Color {
        switch changeType {
        case .modified: Color(nsColor: .init(red: 0.85, green: 0.75, blue: 0.45, alpha: 1))
        case .added: Color(nsColor: .init(red: 0.45, green: 0.80, blue: 0.50, alpha: 1))
        case .deleted: Color(nsColor: .init(red: 0.90, green: 0.45, blue: 0.42, alpha: 1))
        case .renamed: Color(nsColor: .init(red: 0.55, green: 0.70, blue: 0.90, alpha: 1))
        }
    }

    private var badgeBackground: Color {
        switch changeType {
        case .modified: Color(nsColor: .init(red: 0.85, green: 0.75, blue: 0.45, alpha: 0.15))
        case .added: Color(nsColor: .init(red: 0.45, green: 0.80, blue: 0.50, alpha: 0.15))
        case .deleted: Color(nsColor: .init(red: 0.90, green: 0.45, blue: 0.42, alpha: 0.15))
        case .renamed: Color(nsColor: .init(red: 0.55, green: 0.70, blue: 0.90, alpha: 0.15))
        }
    }
}

// MARK: - File List Panel

private struct DiffFileList: View {
    let files: [ComputedFileDiff]
    @Binding var scrollTarget: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files) { file in
                        DiffFileListRow(file: file, isActive: scrollTarget == file.id)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    scrollTarget = file.id
                                }
                            }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct DiffFileListRow: View {
    let file: ComputedFileDiff
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Change type indicator dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortName)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let dir = directory {
                    Text(dir)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(changeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
    }

    private var shortName: String {
        (file.fileName as NSString).lastPathComponent
    }

    private var directory: String? {
        let dir = (file.fileName as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    private var dotColor: Color {
        switch file.changeType {
        case .modified: Color(nsColor: .init(red: 0.85, green: 0.75, blue: 0.45, alpha: 1))
        case .added: Color(nsColor: .init(red: 0.45, green: 0.80, blue: 0.50, alpha: 1))
        case .deleted: Color(nsColor: .init(red: 0.90, green: 0.45, blue: 0.42, alpha: 1))
        case .renamed: Color(nsColor: .init(red: 0.55, green: 0.70, blue: 0.90, alpha: 1))
        }
    }

    private var changeLabel: String {
        let added = file.diffLines.filter { $0.type == .added }.count
        let removed = file.diffLines.filter { $0.type == .removed }.count
        var parts: [String] = []
        if added > 0 { parts.append("+\(added)") }
        if removed > 0 { parts.append("-\(removed)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Multi-file Unified View

private struct UnifiedMultiFileView: View {
    let files: [ComputedFileDiff]
    @Binding var scrollTarget: UUID?
    var workspace: Session?
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            FileHeaderView(fileName: file.fileName, changeType: file.changeType)
                                .frame(minWidth: geo.size.width, alignment: .leading)
                                .id(file.id)

                            ForEach(Array(file.diffLines.enumerated()), id: \.offset) { idx, line in
                                let lineId = "\(file.fileName):\(idx)"
                                let displayLineNumber = line.newLineNumber ?? line.oldLineNumber ?? idx

                                CommentableDiffLineView(
                                    line: line,
                                    highlighter: file.highlighter,
                                    lineId: lineId,
                                    fileName: file.fileName,
                                    displayLineNumber: displayLineNumber,
                                    workspace: workspace,
                                    activeCommentLineId: $activeCommentLineId,
                                    submittedComments: $submittedComments
                                )
                                .frame(minWidth: geo.size.width, alignment: .leading)
                            }

                            Color(nsColor: .textBackgroundColor)
                                .frame(height: 16)
                                .frame(minWidth: geo.size.width)
                        }
                    }
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .onChange(of: scrollTarget) { _, target in
                    if let target {
                        withAnimation {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Wraps a UnifiedDiffLineView with hover comment button and inline comment UI.
private struct CommentableDiffLineView: View {
    let line: DiffLine
    let highlighter: DiffSyntaxHighlighter
    let lineId: String
    let fileName: String
    let displayLineNumber: Int
    var workspace: Session?
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UnifiedDiffLineView(line: line, highlighter: highlighter)
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
                lineContent: line.content,
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

// MARK: - Multi-file Side-by-Side View

private struct SideBySideMultiFileView: View {
    let files: [ComputedFileDiff]
    @Binding var scrollTarget: UUID?
    var workspace: Session?
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files) { file in
                        FileHeaderView(fileName: file.fileName, changeType: file.changeType)
                            .id(file.id)

                        SideBySideDiffView(
                            diffLines: file.diffLines,
                            highlighter: file.highlighter,
                            fileName: file.fileName,
                            workspace: workspace,
                            activeCommentLineId: $activeCommentLineId,
                            submittedComments: $submittedComments
                        )

                        Color(nsColor: .textBackgroundColor)
                            .frame(height: 16)
                    }
                }
            }
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

