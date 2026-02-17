import SwiftUI

struct DetailView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(AppSettings.self) private var appSettings
    let selection: SidebarSelection?

    var body: some View {
        Group {
            switch selection {
            case .session(let id):
                if let session = manager.sessions.first(where: { $0.id == id }) {
                    SessionDetailView(session: session)
                } else {
                    ContentUnavailableView(
                        "Session Not Found",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This session no longer exists.")
                    )
                }
            case .settings:
                SettingsView()
            case .none:
                ContentUnavailableView(
                    "Welcome to Calyx",
                    systemImage: "leaf.fill",
                    description: Text("Create a session or select an item from the sidebar to get started.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(navigationTitle)
        .toolbar {
            if let session = selectedSession {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(session.name)
                            .font(.system(size: 15, weight: .semibold))

                        Divider().frame(height: 14)

                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(session.branchName)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if !session.worktreePath.isEmpty {
                            Text(abbreviatePath(session.worktreePath))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    editorMenuButton(for: session)
                }
            }
        }
    }

    private func editorMenuButton(for session: Session) -> some View {
        let dir = session.workingDirectory
        let defaultEditor = appSettings.defaultEditor

        return Menu {
            ForEach(CodeEditor.allCases) { editor in
                Button {
                    editor.open(directory: dir)
                } label: {
                    if let icon = editor.appIcon {
                        Label {
                            Text(editor.rawValue)
                        } icon: {
                            Image(nsImage: icon)
                        }
                    } else {
                        Text(editor.rawValue)
                    }
                }
            }
        } label: {
            if let icon = defaultEditor.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 14))
            }
        } primaryAction: {
            defaultEditor.open(directory: dir)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .disabled(dir.isEmpty)
        .help("Open in \(defaultEditor.rawValue)")
    }

    private var selectedSession: Session? {
        guard case .session(let id) = selection else { return nil }
        return manager.sessions.first { $0.id == id }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var navigationTitle: String {
        switch selection {
        case .session: ""
        case .settings: "Settings"
        case .none: "Calyx"
        }
    }
}
