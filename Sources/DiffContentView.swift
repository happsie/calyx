import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

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
    @State private var showCommitSheet = false

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
                } },
                hasChanges: workspace?.hasUncommittedChanges ?? false,
                onCommit: workspace != nil ? { showCommitSheet = true } : nil
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
                            editor: appSettings.defaultEditor,
                            activeCommentLineId: $activeCommentLineId,
                            submittedComments: commentsBinding
                        )
                    case .sideBySide:
                        SideBySideMultiFileView(
                            files: computedFiles,
                            scrollTarget: $scrollTarget,
                            workspace: workspace,
                            editor: appSettings.defaultEditor,
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
        .sheet(isPresented: $showCommitSheet) {
            if let workspace {
                CommitSheet(session: workspace)
            }
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
    var workingDirectory: String? = nil
    var editor: CodeEditor? = nil

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

            if let dir = workingDirectory, let editor {
                Menu {
                    ForEach(CodeEditor.allCases) { ed in
                        Button {
                            let fullPath = (dir as NSString).appendingPathComponent(fileName)
                            ed.open(file: fullPath)
                        } label: {
                            if let icon = ed.appIcon {
                                Label {
                                    Text(ed.rawValue)
                                } icon: {
                                    Image(nsImage: icon)
                                }
                            } else {
                                Text(ed.rawValue)
                            }
                        }
                    }
                } label: {
                    if let icon = editor.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 12))
                    }
                } primaryAction: {
                    let fullPath = (dir as NSString).appendingPathComponent(fileName)
                    editor.open(file: fullPath)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in \(editor.rawValue)")
            }
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
    var editor: CodeEditor? = nil
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            FileHeaderView(
                                fileName: file.fileName,
                                changeType: file.changeType,
                                workingDirectory: workspace?.workingDirectory,
                                editor: editor
                            )
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
    var editor: CodeEditor? = nil
    @Binding var activeCommentLineId: String?
    @Binding var submittedComments: [String: [SubmittedComment]]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files) { file in
                        FileHeaderView(
                            fileName: file.fileName,
                            changeType: file.changeType,
                            workingDirectory: workspace?.workingDirectory,
                            editor: editor
                        )
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

// MARK: - Commit Sheet

struct CommitSheet: View {
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @State private var commitMessage = ""
    @State private var hasRemote = false
    @State private var isCommitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commit to \(session.branchName)")
                        .font(.headline)
                    Text("\(session.uncommittedFiles.count) file\(session.uncommittedFiles.count == 1 ? "" : "s") changed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // File list
            List(session.uncommittedFiles) { file in
                CommitFileRow(file: file, workingDirectory: session.workingDirectory)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .padding(.horizontal, 20)
            .frame(minHeight: 80, maxHeight: 140)

            // Commit message
            VStack(alignment: .leading, spacing: 6) {
                Text("Commit message")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Describe your changes...", text: $commitMessage, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isCommitting ? "Committing..." : (hasRemote ? "Commit & Push" : "Commit")) {
                    performCommit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 480, height: 380)
        .task {
            hasRemote = await session.hasRemote()
        }
    }

    private func performCommit() {
        isCommitting = true
        errorMessage = nil
        let push = hasRemote
        let message = commitMessage
        Task {
            do {
                let output = try await session.commitAndPush(message: message, pushToRemote: push)
                await MainActor.run {
                    sendNotification(title: "Commit Successful", body: output)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCommitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

// MARK: - Commit File Row

private struct CommitFileRow: View {
    let file: UncommittedFile
    let workingDirectory: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 12))
                    .lineLimit(1)

                if let dir = file.directory {
                    Text(dir)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Text(file.statusLetter)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(file.statusColor)
                .frame(width: 18, height: 18)
                .background(file.statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 1)
    }

    private var fileIcon: NSImage {
        let fullPath = (workingDirectory as NSString).appendingPathComponent(file.path)
        if FileManager.default.fileExists(atPath: fullPath) {
            return NSWorkspace.shared.icon(forFile: fullPath)
        }
        let ext = (file.path as NSString).pathExtension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

