import SwiftUI
import SwiftTerm

// MARK: - Coding Agent

enum CodingAgent: String, CaseIterable, Identifiable, Codable {
    case claude = "Claude"
    case gemini = "Gemini"
    case copilot = "Copilot"

    var id: String { rawValue }

    var command: String {
        switch self {
        case .claude: "claude"
        case .gemini: "gemini"
        case .copilot: "copilot"
        }
    }

    var icon: String {
        switch self {
        case .claude: "c.circle.fill"
        case .gemini: "g.circle.fill"
        case .copilot: "cp.circle.fill"
        }
    }

    var tint: SwiftUI.Color {
        switch self {
        case .claude: .orange
        case .gemini: .blue
        case .copilot: .purple
        }
    }

    var initials: String {
        switch self {
        case .claude: "CL"
        case .gemini: "GM"
        case .copilot: "CP"
        }
    }

    var dangerousFlag: String? {
        switch self {
        case .claude: "--dangerously-skip-permissions"
        case .copilot: "--yolo"
        case .gemini: "--yolo"
        }
    }
}

// MARK: - Terminal Pane

enum TerminalPaneKind: String, Codable {
    case agent
    case shell
}

struct TerminalPaneData: Codable, Identifiable {
    let id: UUID
    var kind: TerminalPaneKind
    var agentSessionId: String?
    var agent: CodingAgent?
}

@Observable
class TerminalPane: Identifiable {
    let id: UUID
    var kind: TerminalPaneKind
    var agent: CodingAgent?
    var agentSessionId: UUID?
    let terminalView: ThrottledTerminalView
    @ObservationIgnored private var fontObserver: Any?

    init(id: UUID = UUID(), kind: TerminalPaneKind, agent: CodingAgent? = nil, agentSessionId: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.agent = agent
        self.agentSessionId = agentSessionId

        let tv = ThrottledTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.font = AppSettings.resolvedTerminalFont()
        Session.applyTheme(to: tv)
        self.terminalView = tv

        fontObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.terminalFontDidChange,
            object: nil,
            queue: .main
        ) { [weak tv] _ in
            tv?.font = AppSettings.resolvedTerminalFont()
        }
    }

    deinit {
        if let observer = fontObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var persistedData: TerminalPaneData {
        TerminalPaneData(
            id: id,
            kind: kind,
            agentSessionId: agentSessionId?.uuidString,
            agent: agent
        )
    }

    var displayLabel: String {
        switch kind {
        case .shell: return "Terminal"
        case .agent: return agent?.rawValue ?? "Agent"
        }
    }
}

// MARK: - Session Tab

enum SessionTab: Hashable {
    case agent
    case diff
    case plan
    case notes
}

// MARK: - Persisted Session Data

struct SessionData: Codable, Identifiable {
    let id: UUID
    var name: String
    var branchName: String
    var baseBranch: String
    var agent: CodingAgent
    var projectPath: String
    var worktreePath: String
    var agentSessionId: String?
    var planText: String
    var notesRTFBase64: String?
    var submittedComments: [String: [SubmittedComment]]
    var sentCommentHistory: [SentCommentBatch]
    var terminalPanes: [TerminalPaneData]?

    init(id: UUID, name: String, branchName: String, baseBranch: String, agent: CodingAgent, projectPath: String, worktreePath: String, agentSessionId: String?, planText: String, notesRTFBase64: String? = nil, submittedComments: [String: [SubmittedComment]] = [:], sentCommentHistory: [SentCommentBatch] = [], terminalPanes: [TerminalPaneData]? = nil) {
        self.id = id
        self.name = name
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.agent = agent
        self.projectPath = projectPath
        self.worktreePath = worktreePath
        self.agentSessionId = agentSessionId
        self.planText = planText
        self.notesRTFBase64 = notesRTFBase64
        self.submittedComments = submittedComments
        self.sentCommentHistory = sentCommentHistory
        self.terminalPanes = terminalPanes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        branchName = try container.decode(String.self, forKey: .branchName)
        baseBranch = try container.decodeIfPresent(String.self, forKey: .baseBranch) ?? "main"
        agent = try container.decodeIfPresent(CodingAgent.self, forKey: .agent) ?? .claude
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath) ?? ""
        agentSessionId = try container.decodeIfPresent(String.self, forKey: .agentSessionId)
        planText = try container.decodeIfPresent(String.self, forKey: .planText) ?? ""
        notesRTFBase64 = try container.decodeIfPresent(String.self, forKey: .notesRTFBase64)
        submittedComments = try container.decodeIfPresent([String: [SubmittedComment]].self, forKey: .submittedComments) ?? [:]
        sentCommentHistory = try container.decodeIfPresent([SentCommentBatch].self, forKey: .sentCommentHistory) ?? []
        terminalPanes = try container.decodeIfPresent([TerminalPaneData].self, forKey: .terminalPanes)
    }
}

// MARK: - Session

@Observable
class Session: Identifiable {
    let id: UUID
    var name: String
    var branchName: String
    var baseBranch: String
    var agent: CodingAgent
    var projectPath: String
    var worktreePath: String = ""
    var agentSessionId: UUID?
    var setupError: String?
    var terminalPanes: [TerminalPane]
    var focusedPaneId: UUID?
    var fileDiffs: [FileDiff] = []
    var diffRevision: Int = 0
    var hasUncommittedChanges: Bool = false
    var uncommittedFiles: [UncommittedFile] = []
    var submittedComments: [String: [SubmittedComment]] = [:]
    var sentCommentHistory: [SentCommentBatch] = []
    var planText: String = ""
    var planFiles: [PlanFile] = []
    var planRevision: Int = 0
    var notesRTFData: Data?
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var diffPollTask: Task<Void, Never>?
    @ObservationIgnored private var planPollTask: Task<Void, Never>?

    /// The primary agent pane's terminal view — keeps `sendToTerminal`, `sendAllComments` etc. working.
    var terminalView: LocalProcessTerminalView {
        let primaryPane = terminalPanes.first { $0.kind == .agent } ?? terminalPanes[0]
        return primaryPane.terminalView
    }

    /// Create a brand new session — sets up worktree from scratch.
    init(name: String, branchName: String, baseBranch: String = "main", agent: CodingAgent = .claude, projectPath: String) {
        self.id = UUID()
        self.name = name
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.agent = agent
        self.projectPath = projectPath
        let sessionId = UUID()
        self.agentSessionId = sessionId

        let primaryPane = TerminalPane(kind: .agent, agent: agent, agentSessionId: sessionId)
        self.terminalPanes = [primaryPane]
        self.focusedPaneId = primaryPane.id

        setupWorktree()
        startProcess(for: primaryPane, isRestoring: false)
    }

    /// Restore a session from persisted data — reuses existing worktree, resumes agent if possible.
    init(restoring data: SessionData) {
        self.isRestoring = true
        self.id = data.id
        self.name = data.name
        self.branchName = data.branchName
        self.baseBranch = data.baseBranch
        self.agent = data.agent
        self.projectPath = data.projectPath
        self.worktreePath = data.worktreePath
        self.agentSessionId = data.agentSessionId.flatMap { UUID(uuidString: $0) }
        self.planText = data.planText
        self.notesRTFData = data.notesRTFBase64.flatMap { Data(base64Encoded: $0) }
        self.submittedComments = data.submittedComments
        self.sentCommentHistory = data.sentCommentHistory

        // Restore terminal panes from persisted data, or synthesize single agent pane
        if let paneDataArray = data.terminalPanes, !paneDataArray.isEmpty {
            self.terminalPanes = paneDataArray.map { pd in
                TerminalPane(
                    id: pd.id,
                    kind: pd.kind,
                    agent: pd.agent,
                    agentSessionId: pd.agentSessionId.flatMap { UUID(uuidString: $0) }
                )
            }
        } else {
            // Old format — synthesize single agent pane
            let restoredSessionId = data.agentSessionId.flatMap { UUID(uuidString: $0) }
            let primaryPane = TerminalPane(kind: .agent, agent: data.agent, agentSessionId: restoredSessionId)
            self.terminalPanes = [primaryPane]
        }
        self.focusedPaneId = terminalPanes.first?.id

        // Verify worktree still exists, otherwise try to recreate
        if !worktreePath.isEmpty && !FileManager.default.fileExists(atPath: worktreePath) {
            worktreePath = ""
            setupWorktree()
        }

        for pane in terminalPanes {
            startProcess(for: pane, isRestoring: true)
        }
    }

    /// Snapshot for persistence.
    var persistedData: SessionData {
        // Keep agentSessionId from primary agent pane for backward compat
        let primaryAgentSessionId = terminalPanes.first(where: { $0.kind == .agent })?.agentSessionId ?? agentSessionId
        return SessionData(
            id: id,
            name: name,
            branchName: branchName,
            baseBranch: baseBranch,
            agent: agent,
            projectPath: projectPath,
            worktreePath: worktreePath,
            agentSessionId: primaryAgentSessionId?.uuidString,
            planText: planText,
            notesRTFBase64: notesRTFData?.base64EncodedString(),
            submittedComments: submittedComments,
            sentCommentHistory: sentCommentHistory,
            terminalPanes: terminalPanes.map { $0.persistedData }
        )
    }

    func sendToTerminal(_ text: String) {
        terminalView.send(txt: text)
    }

    var totalCommentCount: Int {
        submittedComments.values.reduce(0) { $0 + $1.count }
    }

    func sendAllComments() {
        let flat: [SubmittedComment] = submittedComments.values.flatMap { $0 }
        let allComments = flat.sorted { a, b in
            if a.fileName != b.fileName { return a.fileName < b.fileName }
            return a.lineNumber < b.lineNumber
        }

        guard !allComments.isEmpty else { return }

        var message = "# Code Review Comments\n\n"
        var currentFile = ""

        for comment in allComments {
            if comment.fileName != currentFile {
                currentFile = comment.fileName
                message += "## \(currentFile)\n\n"
            }
            message += "Line \(comment.lineNumber):\n"
            message += "> \(comment.lineContent)\n\n"
            message += "\(comment.commentText)\n\n"
        }

        sendToTerminal(message)
        terminalView.send(EscapeSequences.cmdRet)

        let batch = SentCommentBatch(comments: allComments)
        sentCommentHistory.append(batch)
        submittedComments.removeAll()
    }

    // MARK: - Pane Management

    func addTerminalPane(kind: TerminalPaneKind, agent: CodingAgent? = nil) {
        guard terminalPanes.count < 3 else { return }
        let sessionId: UUID? = (kind == .agent) ? UUID() : nil
        let pane = TerminalPane(kind: kind, agent: agent, agentSessionId: sessionId)
        terminalPanes.append(pane)
        focusedPaneId = pane.id
        startProcess(for: pane, isRestoring: false)
    }

    func removeTerminalPane(id: UUID) {
        guard terminalPanes.count > 1 else { return }
        terminalPanes.removeAll { $0.id == id }
        if focusedPaneId == id {
            focusedPaneId = terminalPanes.first?.id
        }
    }

    /// The directory the terminal runs in — worktree if created, otherwise project root.
    var workingDirectory: String {
        worktreePath.isEmpty ? projectPath : worktreePath
    }

    // MARK: - Git Operations

    func hasRemote() async -> Bool {
        let dir = workingDirectory
        guard !dir.isEmpty else { return false }
        return await Task.detached {
            let result = runGit(["remote"], in: dir)
            return result.success && !result.output.isEmpty
        }.value
    }

    func commitAndPush(message: String, pushToRemote: Bool) async throws -> String {
        let dir = workingDirectory
        guard !dir.isEmpty else { throw GitError.noWorkingDirectory }

        return try await Task.detached {
            // Stage all changes
            let addResult = runGit(["add", "-A"], in: dir)
            guard addResult.success else {
                throw GitError.commandFailed("git add: \(addResult.output)")
            }

            // Commit
            let commitResult = runGit(["commit", "-m", message], in: dir)
            guard commitResult.success else {
                throw GitError.commandFailed("git commit: \(commitResult.output)")
            }

            // Push if requested
            if pushToRemote {
                let pushResult = runGit(["push"], in: dir)
                guard pushResult.success else {
                    // Commit succeeded but push failed — try push with --set-upstream
                    let branch = runGit(["branch", "--show-current"], in: dir)
                    let branchName = branch.success ? branch.output : "HEAD"
                    let retryResult = runGit(["push", "--set-upstream", "origin", branchName], in: dir)
                    guard retryResult.success else {
                        throw GitError.commandFailed("git push: \(retryResult.output)")
                    }
                    return "Committed and pushed (set upstream)"
                }
                return "Committed and pushed"
            }

            return "Committed: \(commitResult.output)"
        }.value
    }

    // MARK: - Diff Polling

    func startDiffPolling() {
        let dir = workingDirectory
        let base = baseBranch
        guard !dir.isEmpty else { return }

        diffPollTask?.cancel()
        diffPollTask = Task.detached { [weak self] in
            let diffBase = resolveDiffBase(base, in: dir)
            var lastSignature = ""

            while !Task.isCancelled {
                guard let self else { return }

                // Build a change signature from tracked diffs + untracked files.
                // git diff alone misses untracked (new) files the AI creates.
                let fullDiff = runGit(["diff", diffBase], in: dir)
                let untracked = runGit(
                    ["ls-files", "--others", "--exclude-standard"],
                    in: dir
                )
                let signature = (fullDiff.output) + "\n--untracked--\n" + (untracked.output)

                // Check for uncommitted changes (staged + unstaged + untracked)
                let statusResult = runGit(["status", "--porcelain"], in: dir)
                let uncommitted = statusResult.success && !statusResult.output.isEmpty
                let parsedFiles = statusResult.success ? parseGitStatus(statusResult.output) : []

                if signature != lastSignature {
                    lastSignature = signature
                    let nameStatus = runGit(["diff", "--name-status", diffBase], in: dir)
                    var allDiffs = nameStatus.success
                        ? parseDiffNameStatus(nameStatus.output, dir: dir, baseBranch: diffBase)
                        : []

                    // Include untracked (new) files as Added diffs
                    if untracked.success {
                        let untrackedDiffs = parseUntrackedFiles(untracked.output, dir: dir)
                        allDiffs.append(contentsOf: untrackedDiffs)
                    }

                    let finalDiffs = allDiffs
                    await MainActor.run {
                        self.fileDiffs = finalDiffs
                        self.diffRevision += 1
                        self.hasUncommittedChanges = uncommitted
                        self.uncommittedFiles = parsedFiles
                    }
                } else if self.hasUncommittedChanges != uncommitted {
                    await MainActor.run {
                        self.hasUncommittedChanges = uncommitted
                        self.uncommittedFiles = parsedFiles
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopDiffPolling() {
        diffPollTask?.cancel()
        diffPollTask = nil
    }

    // MARK: - Plan File Polling

    func startPlanPolling() {
        let dir = workingDirectory
        let agentType = agent
        let sessionId = agentSessionId
        let customPaths = UserDefaults.standard.stringArray(forKey: "customPlanPaths") ?? []
        let projectRoot = projectPath
        guard !dir.isEmpty else { return }

        planPollTask?.cancel()
        planPollTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                var discovered = discoverPlanFiles(agent: agentType, worktreeDir: dir, sessionId: sessionId)

                // Common fallback: scan <worktree>/.planning/ for all agents
                let planningDir = (dir as NSString).appendingPathComponent(".planning")
                discovered.append(contentsOf: scanDirectory(planningDir, baseDir: dir))

                // Scan user-configured custom plan paths (relative to project root)
                for customPath in customPaths {
                    let fullPath = (projectRoot as NSString).appendingPathComponent(customPath)
                    discovered.append(contentsOf: scanDirectory(fullPath, baseDir: projectRoot))
                }

                // Deduplicate by id
                var seen = Set<String>()
                var unique: [PlanFile] = []
                for file in discovered {
                    if seen.insert(file.id).inserted {
                        unique.append(file)
                    }
                }

                // Sort by modification date, newest first
                unique.sort { $0.lastModified > $1.lastModified }

                let currentFiles = await MainActor.run { self.planFiles }
                if unique != currentFiles {
                    let finalFiles = unique
                    await MainActor.run {
                        self.planFiles = finalFiles
                        self.planRevision += 1
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPlanPolling() {
        planPollTask?.cancel()
        planPollTask = nil
    }

    // MARK: - Git Worktree Setup

    private func setupWorktree() {
        guard !projectPath.isEmpty, !branchName.isEmpty else { return }

        // Clean up stale worktree references from previously deleted sessions
        _ = runGit(["worktree", "prune"], in: projectPath)

        // Fetch latest for the base branch
        _ = runGit(["fetch", "origin", baseBranch], in: projectPath)

        // Compute worktree path: <project>/.worktrees/<branchName>
        let worktreesRoot = (projectPath as NSString).appendingPathComponent(".worktrees")
        let worktreeDir = (worktreesRoot as NSString).appendingPathComponent(branchName)

        // Reuse if it already exists and is a valid worktree
        if FileManager.default.fileExists(atPath: worktreeDir) {
            let gitFile = (worktreeDir as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitFile) {
                worktreePath = worktreeDir
                return
            }
            // Directory exists but isn't a valid worktree — remove it
            try? FileManager.default.removeItem(atPath: worktreeDir)
        }

        // Ensure the worktrees container directory exists
        try? FileManager.default.createDirectory(
            atPath: worktreesRoot,
            withIntermediateDirectories: true
        )

        // Create worktree with new branch based on the base branch
        let result = runGit(
            ["worktree", "add", "-b", branchName, worktreeDir, baseBranch],
            in: projectPath
        )

        if result.success {
            worktreePath = worktreeDir
        } else {
            // Branch might already exist — try without -b, using --force in case
            // the branch is already checked out in the main working tree
            let retryResult = runGit(
                ["worktree", "add", "--force", worktreeDir, branchName],
                in: projectPath
            )
            if retryResult.success {
                worktreePath = worktreeDir
            } else {
                setupError = retryResult.output
            }
        }
    }

    // MARK: - Terminal Process

    private func startProcess(for pane: TerminalPane, isRestoring: Bool) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let args: [String]

        switch pane.kind {
        case .agent:
            let paneAgent = pane.agent ?? agent
            var agentCommand: String = paneAgent.command

            if UserDefaults.standard.bool(forKey: "dangerousMode"),
               let flag = paneAgent.dangerousFlag {
                agentCommand += " \(flag)"
            }

            switch paneAgent {
            case .claude:
                if let sessionId = pane.agentSessionId {
                    // Always use --session-id: resumes if the session exists,
                    // creates with the same ID if not (avoids ID mismatch when
                    // --resume fails to find an expired/cleaned-up session).
                    agentCommand += " --session-id \(sessionId.uuidString)"
                }
            case .copilot:
                if let sessionId = pane.agentSessionId {
                    agentCommand += " --resume \(sessionId.uuidString)"
                }
            case .gemini:
                break
            }

            args = ["-l", "-c", agentCommand]

        case .shell:
            args = ["-l"]
        }

        var env = ProcessInfo.processInfo.environment
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"

        // When launched from an .app bundle, macOS provides a minimal PATH
        // that lacks common tool directories. Ensure they're included so
        // commands like `claude`, `git`, etc. are found by the login shell.
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingComponents = Set(currentPath.components(separatedBy: ":"))
        let missing = extraPaths.filter { !existingComponents.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [currentPath]).joined(separator: ":")
        }

        let envArray = env.map { "\($0.key)=\($0.value)" }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory

        pane.terminalView.startProcess(
            executable: shell,
            args: args,
            environment: envArray,
            execName: (shell as NSString).lastPathComponent,
            currentDirectory: cwd
        )
    }

    static func applyTheme(to view: LocalProcessTerminalView, isDark: Bool) {
        if isDark {
            view.nativeBackgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            view.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
            view.installColors([
                termColor(0x3B, 0x3B, 0x42),  // black
                termColor(0xD4, 0x6A, 0x6A),  // red
                termColor(0x8C, 0xBE, 0x8C),  // green
                termColor(0xD4, 0xB8, 0x6A),  // yellow
                termColor(0x6A, 0x9F, 0xD4),  // blue
                termColor(0xB8, 0x7E, 0xC6),  // magenta
                termColor(0x6A, 0xC4, 0xBF),  // cyan
                termColor(0xC5, 0xC5, 0xCA),  // white
                termColor(0x5A, 0x5A, 0x64),  // bright black
                termColor(0xE8, 0x8C, 0x8C),  // bright red
                termColor(0xA8, 0xD4, 0xA8),  // bright green
                termColor(0xE8, 0xD0, 0x8C),  // bright yellow
                termColor(0x8C, 0xBB, 0xE8),  // bright blue
                termColor(0xCE, 0x9E, 0xDA),  // bright magenta
                termColor(0x8C, 0xDA, 0xD4),  // bright cyan
                termColor(0xE0, 0xE0, 0xE5),  // bright white
            ])
        } else {
            view.nativeBackgroundColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
            view.nativeForegroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1)
            view.installColors([
                termColor(0xE8, 0xE8, 0xED),  // black (light bg)
                termColor(0xC4, 0x2B, 0x2B),  // red
                termColor(0x2E, 0x8B, 0x41),  // green
                termColor(0x9E, 0x7C, 0x12),  // yellow
                termColor(0x2A, 0x62, 0xA8),  // blue
                termColor(0x8B, 0x46, 0x9B),  // magenta
                termColor(0x1A, 0x8A, 0x82),  // cyan
                termColor(0x3A, 0x3A, 0x40),  // white (dark text)
                termColor(0xB0, 0xB0, 0xB8),  // bright black
                termColor(0xE8, 0x4D, 0x4D),  // bright red
                termColor(0x3A, 0xA8, 0x52),  // bright green
                termColor(0xB8, 0x94, 0x1E),  // bright yellow
                termColor(0x3A, 0x7E, 0xD0),  // bright blue
                termColor(0xA8, 0x5C, 0xBB),  // bright magenta
                termColor(0x22, 0xA8, 0x9E),  // bright cyan
                termColor(0x1A, 0x1A, 0x1E),  // bright white (darkest text)
            ])
        }
    }

    static func applyTheme(to view: LocalProcessTerminalView) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        applyTheme(to: view, isDark: isDark)
    }
}

struct UncommittedFile: Identifiable {
    let id: String // the file path
    let status: String // e.g. "M", "A", "D", "??"
    let path: String

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directory: String? {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    var statusLabel: String {
        switch status {
        case "M": "Modified"
        case "A": "Added"
        case "D": "Deleted"
        case "R": "Renamed"
        case "??": "Untracked"
        default: status
        }
    }

    var statusLetter: String {
        switch status {
        case "??": "U"
        default: String(status.prefix(1))
        }
    }

    var statusColor: SwiftUI.Color {
        switch status {
        case "M": Color(nsColor: .init(red: 0.85, green: 0.75, blue: 0.45, alpha: 1))
        case "A": Color(nsColor: .init(red: 0.45, green: 0.80, blue: 0.50, alpha: 1))
        case "D": Color(nsColor: .init(red: 0.90, green: 0.45, blue: 0.42, alpha: 1))
        case "??": Color(nsColor: .init(red: 0.45, green: 0.80, blue: 0.50, alpha: 1))
        default: .secondary
        }
    }
}

private func parseGitStatus(_ output: String) -> [UncommittedFile] {
    guard !output.isEmpty else { return [] }
    var files: [UncommittedFile] = []
    for line in output.split(separator: "\n") {
        guard line.count >= 4 else { continue }
        let statusPart = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
        let filePath = String(line.dropFirst(3))
        let status = statusPart.isEmpty ? "?" : statusPart
        files.append(UncommittedFile(id: filePath, status: status, path: filePath))
    }
    return files
}

private struct GitResult {
    let success: Bool
    let output: String
}

enum GitError: LocalizedError {
    case noWorkingDirectory
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWorkingDirectory: "No working directory"
        case .commandFailed(let msg): msg
        }
    }
}

/// Find the best ref to diff against. Tries: the branch name as-is, origin/<branch>, then HEAD.
private func resolveDiffBase(_ base: String, in dir: String) -> String {
    // Try the base branch directly (works if local branch exists)
    let direct = runGit(["rev-parse", "--verify", base], in: dir)
    if direct.success { return base }

    // Try origin/<base> (common when worktree doesn't have a local tracking branch)
    let remote = "origin/\(base)"
    let remoteCheck = runGit(["rev-parse", "--verify", remote], in: dir)
    if remoteCheck.success { return remote }

    // Last resort: diff against HEAD (shows only uncommitted changes)
    return "HEAD"
}

private func parseDiffNameStatus(_ output: String, dir: String, baseBranch: String) -> [FileDiff] {
    guard !output.isEmpty else { return [] }

    var diffs: [FileDiff] = []
    for line in output.split(separator: "\n") {
        let parts = line.split(separator: "\t")
        guard parts.count >= 2 else { continue }

        let status = String(parts[0])
        let changeType: FileChangeType
        let fileName: String
        var oldFileName: String? = nil

        if status.hasPrefix("R") {
            changeType = .renamed
            oldFileName = String(parts[1])
            fileName = parts.count >= 3 ? String(parts[2]) : String(parts[1])
        } else {
            fileName = String(parts[1])
            switch status {
            case "A": changeType = .added
            case "D": changeType = .deleted
            default: changeType = .modified
            }
        }

        // Old content from base branch
        var oldText = ""
        if changeType != .added {
            let sourceFile = oldFileName ?? fileName
            let result = runGit(["show", "\(baseBranch):\(sourceFile)"], in: dir)
            if result.success { oldText = result.output }
        }

        // New content from working tree
        var newText = ""
        if changeType != .deleted {
            let filePath = (dir as NSString).appendingPathComponent(fileName)
            newText = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        }

        diffs.append(FileDiff(fileName: fileName, changeType: changeType, oldText: oldText, newText: newText))
    }

    return diffs
}

private func parseUntrackedFiles(_ output: String, dir: String) -> [FileDiff] {
    guard !output.isEmpty else { return [] }

    var diffs: [FileDiff] = []
    for line in output.split(separator: "\n") {
        let fileName = String(line)
        guard !fileName.isEmpty else { continue }

        let filePath = (dir as NSString).appendingPathComponent(fileName)
        let newText = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        // Skip binary files (failed to read as UTF-8)
        guard !newText.isEmpty else { continue }

        diffs.append(FileDiff(fileName: fileName, changeType: .added, oldText: "", newText: newText))
    }
    return diffs
}

private func runGit(_ arguments: [String], in directory: String) -> GitResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: directory)
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return GitResult(success: false, output: error.localizedDescription)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return GitResult(success: process.terminationStatus == 0, output: output)
}

private func readPlanFile(at fullPath: String, relativePath: String) -> PlanFile? {
    let fm = FileManager.default
    guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8),
          let attrs = try? fm.attributesOfItem(atPath: fullPath),
          let modified = attrs[.modificationDate] as? Date else {
        return nil
    }
    let name = (relativePath as NSString).lastPathComponent
    return PlanFile(id: relativePath, name: name, relativePath: relativePath, content: content, lastModified: modified)
}

private func scanDirectory(_ dirPath: String, baseDir: String) -> [PlanFile] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dirPath) else { return [] }

    var results: [PlanFile] = []
    guard let enumerator = fm.enumerator(atPath: dirPath) else { return [] }

    while let relative = enumerator.nextObject() as? String {
        guard relative.hasSuffix(".md") else { continue }
        let fullPath = (dirPath as NSString).appendingPathComponent(relative)
        let dirName = (dirPath as NSString).lastPathComponent
        let relativePath = (dirName as NSString).appendingPathComponent(relative)
        if let file = readPlanFile(at: fullPath, relativePath: relativePath) {
            results.append(file)
        }
    }
    return results
}

// MARK: - Agent-Specific Plan Discovery

private func discoverPlanFiles(agent: CodingAgent, worktreeDir: String, sessionId: UUID?) -> [PlanFile] {
    switch agent {
    case .claude:
        return discoverClaudePlans(worktreeDir: worktreeDir, sessionId: sessionId)
    case .copilot:
        return discoverCopilotPlans(sessionId: sessionId)
    case .gemini:
        return []  // Gemini keeps todos in-memory only
    }
}

private func discoverClaudePlans(worktreeDir: String, sessionId: UUID?) -> [PlanFile] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    // Resolve plansDirectory from settings
    var plansDir: String?

    // 1. Check <worktree>/.claude/settings.json
    let localSettings = (worktreeDir as NSString).appendingPathComponent(".claude/settings.json")
    if let dir = readJSONSetting(key: "plansDirectory", from: localSettings) {
        plansDir = dir
    }

    // 2. Check ~/.claude/settings.json
    if plansDir == nil {
        let globalSettings = (home as NSString).appendingPathComponent(".claude/settings.json")
        if let dir = readJSONSetting(key: "plansDirectory", from: globalSettings) {
            plansDir = dir
        }
    }

    // Resolve the path
    let resolvedDir: String
    if let plansDir {
        if (plansDir as NSString).isAbsolutePath {
            resolvedDir = plansDir
        } else {
            // Relative path resolves from worktree root
            resolvedDir = (worktreeDir as NSString).appendingPathComponent(plansDir)
        }
    } else {
        // Default: ~/.claude/plans/
        resolvedDir = (home as NSString).appendingPathComponent(".claude/plans")
    }

    let allPlans = scanDirectory(resolvedDir, baseDir: resolvedDir)

    // Filter to only plans referenced by this session's JSONL transcript.
    // Claude stores session transcripts at ~/.claude/projects/<encoded-path>/<sessionId>.jsonl
    let referencedNames = findClaudeSessionPlanNames(worktreeDir: worktreeDir, sessionId: sessionId)
    if referencedNames.isEmpty {
        return []
    }
    return allPlans.filter { referencedNames.contains($0.name) }
}

private func discoverCopilotPlans(sessionId: UUID?) -> [PlanFile] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let sessionStateDir = (home as NSString).appendingPathComponent(".copilot/session-state")
    let fm = FileManager.default
    var results: [PlanFile] = []

    // 1. Check specific session's plan.md
    if let sessionId {
        let planPath = (sessionStateDir as NSString)
            .appendingPathComponent(sessionId.uuidString)
            .appending("/plan.md")
        if let file = readPlanFile(at: planPath, relativePath: "session-state/\(sessionId.uuidString)/plan.md") {
            results.append(file)
        }
    }

    // 2. Scan for other recent plan.md files (last 24h)
    let cutoff = Date().addingTimeInterval(-86400)
    guard fm.fileExists(atPath: sessionStateDir),
          let entries = try? fm.contentsOfDirectory(atPath: sessionStateDir) else {
        return results
    }

    for entry in entries {
        // Skip the session we already checked
        if let sessionId, entry == sessionId.uuidString { continue }

        let planPath = (sessionStateDir as NSString)
            .appendingPathComponent(entry)
            .appending("/plan.md")
        guard fm.fileExists(atPath: planPath),
              let attrs = try? fm.attributesOfItem(atPath: planPath),
              let modified = attrs[.modificationDate] as? Date,
              modified > cutoff else { continue }

        if let file = readPlanFile(at: planPath, relativePath: "session-state/\(entry)/plan.md") {
            results.append(file)
        }
    }

    return results
}

/// Grep the session's JSONL transcript for plan file references.
/// Returns the set of plan file names (e.g. "cosmic-plotting-bunny.md") referenced by this session.
private func findClaudeSessionPlanNames(worktreeDir: String, sessionId: UUID?) -> Set<String> {
    guard let sessionId else { return [] }
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    // Claude encodes project paths by replacing "/" and "." with "-"
    // e.g. /Users/foo.bar/.worktrees/branch → -Users-foo-bar--worktrees-branch
    let encoded = worktreeDir
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ".", with: "-")
    let projectDir = (home as NSString).appendingPathComponent(".claude/projects/\(encoded)")
    let jsonlPath = (projectDir as NSString).appendingPathComponent("\(sessionId.uuidString).jsonl")

    guard FileManager.default.fileExists(atPath: jsonlPath) else { return [] }

    // Use grep to efficiently find plan file references without loading the entire file
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
    process.arguments = ["-o", "plans/[a-zA-Z0-9_-]*\\.md", jsonlPath]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    var names = Set<String>()
    for line in output.split(separator: "\n") {
        // "plans/cosmic-plotting-bunny.md" → "cosmic-plotting-bunny.md"
        let name = String(line.dropFirst("plans/".count))
        if !name.isEmpty {
            names.insert(name)
        }
    }
    return names
}

private func readJSONSetting(key: String, from path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let value = json[key] as? String else {
        return nil
    }
    return value
}

private func termColor(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
    SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
}

// MARK: - Session Manager

@Observable
class SessionManager {
    var sessions: [Session] = []

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    init() {
        loadSessions()
    }

    @discardableResult
    func createSession(name: String, branchName: String, baseBranch: String = "main", agent: CodingAgent = .claude, projectPath: String = "") -> Session {
        let session = Session(name: name, branchName: branchName, baseBranch: baseBranch, agent: agent, projectPath: projectPath)
        sessions.append(session)
        save()
        return session
    }

    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    private static var backupURL: URL {
        storageURL.deletingLastPathComponent().appendingPathComponent("sessions.backup.json")
    }

    /// Terminate all running terminal processes across all sessions.
    /// Sends SIGTERM to each process group so child processes (agents) also die.
    func terminateAllProcesses() {
        for session in sessions {
            for pane in session.terminalPanes {
                let pid = pane.terminalView.process.shellPid
                if pid > 0 {
                    // Negative PID sends signal to entire process group
                    kill(-pid, SIGTERM)
                }
                pane.terminalView.terminate()
            }
        }
    }

    /// Whether all terminal processes across all sessions have exited.
    var allProcessesTerminated: Bool {
        for session in sessions {
            for pane in session.terminalPanes {
                if pane.terminalView.process.running {
                    return false
                }
            }
        }
        return true
    }

    /// Send SIGKILL to any remaining processes (timeout fallback).
    func forceKillAllProcesses() {
        for session in sessions {
            for pane in session.terminalPanes {
                let pid = pane.terminalView.process.shellPid
                if pid > 0 && pane.terminalView.process.running {
                    kill(-pid, SIGKILL)
                }
            }
        }
    }

    func save() {
        let data = sessions.map { $0.persistedData }
        do {
            let encoded = try JSONEncoder().encode(data)
            // Backup existing file before overwriting
            let fm = FileManager.default
            if fm.fileExists(atPath: Self.storageURL.path) {
                try? fm.removeItem(at: Self.backupURL)
                try? fm.copyItem(at: Self.storageURL, to: Self.backupURL)
            }
            try encoded.write(to: Self.storageURL, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    private func loadSessions() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.storageURL.path) else { return }

        if let loaded = loadSessionsFrom(url: Self.storageURL), !loaded.isEmpty {
            sessions = loaded
        } else if fm.fileExists(atPath: Self.backupURL.path) {
            // Main file failed completely — try backup
            print("Main sessions file failed, trying backup...")
            if let loaded = loadSessionsFrom(url: Self.backupURL) {
                sessions = loaded
            }
        }
    }

    /// Decode sessions individually so one corrupt entry doesn't wipe all sessions.
    private func loadSessionsFrom(url: URL) -> [Session]? {
        do {
            let data = try Data(contentsOf: url)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("Sessions file is not a JSON array: \(url.lastPathComponent)")
                return nil
            }
            var loaded: [Session] = []
            for (index, element) in jsonArray.enumerated() {
                do {
                    let elementData = try JSONSerialization.data(withJSONObject: element)
                    let sessionData = try JSONDecoder().decode(SessionData.self, from: elementData)
                    loaded.append(Session(restoring: sessionData))
                } catch {
                    print("Skipping corrupt session at index \(index): \(error)")
                }
            }
            return loaded
        } catch {
            print("Failed to read sessions file \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}

// MARK: - Project Store

@Observable
class ProjectStore {
    private static let key = "recentProjectPaths"

    var recentPaths: [String] {
        didSet { save() }
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: ProjectStore.key) ?? []
        self.recentPaths = stored.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func addPath(_ path: String) {
        recentPaths.removeAll { $0 == path }
        recentPaths.insert(path, at: 0)
        if recentPaths.count > 20 {
            recentPaths = Array(recentPaths.prefix(20))
        }
    }

    func removePath(_ path: String) {
        recentPaths.removeAll { $0 == path }
    }

    /// Display name: last path component
    func displayName(for path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func save() {
        UserDefaults.standard.set(recentPaths, forKey: ProjectStore.key)
    }
}
