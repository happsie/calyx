import SwiftUI

// MARK: - Wizard Steps

private enum WizardStep {
    case project
    case details
}

// MARK: - Git Helpers

private func fetchGitBranches(at path: String) -> [String] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["branch", "--list", "--format=%(refname:short)"]
    process.currentDirectoryURL = URL(fileURLWithPath: path)
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

private func detectMainBranch(from branches: [String]) -> String {
    for candidate in ["main", "master", "develop", "dev"] {
        if branches.contains(candidate) { return candidate }
    }
    return branches.first ?? "main"
}

// MARK: - Main Sheet

struct NewSessionSheet: View {
    @Environment(SessionManager.self) private var manager
    @Environment(ProjectStore.self) private var projectStore
    @Environment(\.dismiss) private var dismiss

    var onCreate: ((UUID) -> Void)? = nil

    @State private var step: WizardStep = .project
    @State private var selectedProjectPath: String = ""
    @State private var name = ""
    @State private var branchName = ""
    @State private var baseBranch = "main"
    @State private var agent: CodingAgent = .claude
    @State private var branches: [String] = []
    @State private var branchSearch = ""
    @State private var showBranchDropdown = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, branch, baseBranch
    }

    private var filteredBranches: [String] {
        if branchSearch.isEmpty { return branches }
        return branches.filter { $0.localizedCaseInsensitiveContains(branchSearch) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(step == .project ? "Select Project" : "Session Details")
                    .font(.title2.weight(.semibold))

                Spacer()

                // Step indicator
                HStack(spacing: 6) {
                    stepDot(active: step == .project)
                    stepDot(active: step == .details)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Content
            Group {
                switch step {
                case .project:
                    projectStep
                case .details:
                    detailsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // Buttons
            HStack {
                if step == .details {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) { step = .project }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                switch step {
                case .project:
                    Button("Next") {
                        loadBranches()
                        withAnimation(.easeInOut(duration: 0.2)) { step = .details }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedProjectPath.isEmpty)

                case .details:
                    Button("Create Session") { create() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Step Dot

    private func stepDot(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
    }

    // MARK: - Step 1: Project

    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            if projectStore.recentPaths.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No projects added yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Add a project folder to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Button(action: browseFolder) {
                        Label("Add Project Folder…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Project list (scrollable within fixed bounds)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(projectStore.recentPaths, id: \.self) { path in
                            projectRow(path: path)
                            if path != projectStore.recentPaths.last {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                // Add button pinned at bottom
                Button(action: browseFolder) {
                    Label("Add Project Folder…", systemImage: "folder.badge.plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
        }
    }

    private func projectRow(path: String) -> some View {
        let isSelected = selectedProjectPath == path

        return HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(projectStore.displayName(for: path))
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(abbreviatePath(path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16))
            }

            Button(action: {
                if selectedProjectPath == path { selectedProjectPath = "" }
                projectStore.removePath(path)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedProjectPath = path }
    }

    // MARK: - Step 2: Details

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Show selected project as context
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                Text(projectStore.displayName(for: selectedProjectPath))
                    .font(.system(size: 13, weight: .medium))
                Text(abbreviatePath(selectedProjectPath))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Session Name
            fieldSection("Session Name") {
                TextField("e.g. Add login flow", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focusedField, equals: .name)
            }

            // Branch fields side by side
            HStack(alignment: .top, spacing: 16) {
                fieldSection("Branch Name") {
                    TextField("auto-derived from name if empty", text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focusedField, equals: .branch)
                }
                fieldSection("Base Branch") {
                    branchPicker
                }
            }

            // Coding Agent
            fieldSection("Coding Agent") {
                HStack(spacing: 12) {
                    ForEach(CodingAgent.allCases) { a in
                        agentRadioButton(a)
                    }
                }
            }
        }
        .padding(24)
        .onAppear { focusedField = .name }
    }

    // MARK: - Branch Picker

    private var branchPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Trigger button
            Button(action: { showBranchDropdown.toggle() }) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(baseBranch)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($focusedField, equals: .baseBranch)
            .onKeyPress(.return) {
                showBranchDropdown = true
                return .handled
            }
            .onKeyPress(.space) {
                showBranchDropdown = true
                return .handled
            }
            .popover(isPresented: $showBranchDropdown, arrowEdge: .bottom) {
                branchDropdownContent
            }
        }
    }

    private var branchDropdownContent: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search branches…", text: $branchSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if let first = filteredBranches.first {
                            baseBranch = first
                            branchSearch = ""
                            showBranchDropdown = false
                        }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if filteredBranches.isEmpty {
                Text(branches.isEmpty ? "No branches found" : "No matching branches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredBranches, id: \.self) { branch in
                            branchRow(branch)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 240)
    }

    private func branchRow(_ branch: String) -> some View {
        let isSelected = baseBranch == branch

        return Button(action: {
            baseBranch = branch
            branchSearch = ""
            showBranchDropdown = false
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(branch)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
    }

    // MARK: - Agent Radio Buttons

    private func agentRadioButton(_ a: CodingAgent) -> some View {
        let isSelected = agent == a

        return Button(action: { agent = a }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.system(size: 14))

                Image(systemName: a.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(a.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            projectStore.addPath(path)
            selectedProjectPath = path
        }
    }

    private func loadBranches() {
        branches = fetchGitBranches(at: selectedProjectPath)
        baseBranch = detectMainBranch(from: branches)
        branchSearch = ""
    }

    private func create() {
        let session = manager.createSession(
            name: name.trimmingCharacters(in: .whitespaces),
            branchName: branchName.isEmpty ? deriveBranch(from: name) : branchName,
            baseBranch: baseBranch,
            agent: agent,
            projectPath: selectedProjectPath
        )
        onCreate?(session.id)
        dismiss()
    }

    private func deriveBranch(from name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
