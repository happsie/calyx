import SwiftUI

enum SidebarSelection: Hashable {
    case session(UUID)
    case settings
}

struct SidebarView: View {
    @Environment(SessionManager.self) private var manager
    @Binding var selection: SidebarSelection?
    @State private var showNewSession = false
    @State private var sessionToDelete: Session?
    @State private var alsoRemoveWorktree = false

    var body: some View {
        List(selection: $selection) {
            Section("Sessions") {
                ForEach(manager.sessions) { session in
                    SessionSidebarRow(session: session)
                        .tag(SidebarSelection.session(session.id))
                        .contextMenu {
                            Button {
                                sessionToDelete = session
                            } label: {
                                Label("Delete Session…", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                sessionToDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSession = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("New Session")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                selection = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(selection == .settings ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selection == .settings ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .navigationTitle("Calyx")
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet { sessionId in
                selection = .session(sessionId)
            }
        }
        .sheet(item: $sessionToDelete) { session in
            DeleteSessionSheet(
                session: session,
                alsoRemoveWorktree: $alsoRemoveWorktree,
                onDelete: { deleteSession(session, removeWorktree: alsoRemoveWorktree) },
                onCancel: {
                    sessionToDelete = nil
                    alsoRemoveWorktree = false
                }
            )
        }
    }

    private func deleteSession(_ session: Session, removeWorktree: Bool) {
        if removeWorktree, !session.worktreePath.isEmpty {
            // Remove the git worktree properly, then delete the directory
            if !session.projectPath.isEmpty {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["worktree", "remove", session.worktreePath, "--force"]
                process.currentDirectoryURL = URL(fileURLWithPath: session.projectPath)
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            if case .session(session.id) = selection {
                selection = nil
            }
            manager.removeSession(id: session.id)
        }
        alsoRemoveWorktree = false
    }
}

// MARK: - Sidebar Row

private struct SessionSidebarRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            SessionBadge(name: session.name, id: session.id)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(session.branchName)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Session Badge

private struct SessionBadge: View {
    let name: String
    let id: UUID

    private static let colors: [Color] = [
        .blue, .purple, .pink, .orange, .teal,
        .indigo, .mint, .cyan, .brown, .red,
    ]

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var color: Color {
        let hash = id.hashValue
        return Self.colors[abs(hash) % Self.colors.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color, in: .rect(cornerRadius: 7))
    }
}

// MARK: - Delete Confirmation Sheet

private struct DeleteSessionSheet: View {
    let session: Session
    @Binding var alsoRemoveWorktree: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)

                Text("Delete \"\(session.name)\"?")
                    .font(.headline)

                Text("This will remove the session from Calyx.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            if !session.worktreePath.isEmpty {
                Toggle(isOn: $alsoRemoveWorktree) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also remove git worktree")
                            .font(.system(size: 13))
                        Text(abbreviatePath(session.worktreePath))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Delete") {
                    dismiss()
                    onDelete()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 380, height: session.worktreePath.isEmpty ? 220 : 280)
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
