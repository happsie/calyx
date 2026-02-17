import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@main
struct SwiftAgentsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var sessionManager = SessionManager()
    @State private var projectStore = ProjectStore()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(projectStore)
                .environment(appSettings)
                .environment(appDelegate)
                .preferredColorScheme(appSettings.appearanceMode.colorScheme)
                .onAppear {
                    appDelegate.sessionManager = sessionManager
                }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(after: .appInfo) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@Observable
class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionManager: SessionManager?
    var isQuitting = false
    private var saveTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.processName = "Calyx"
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconRenderer.setAsDockIcon()
        NSApp.activate(ignoringOtherApps: true)
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.sessionManager?.save()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sessionManager else { return .terminateNow }

        // If all processes are already dead, no need to wait
        if sessionManager.allProcessesTerminated {
            return .terminateNow
        }

        isQuitting = true
        sessionManager.terminateAllProcesses()

        // Use DispatchQueue for polling — Timer may not fire during termination
        // because the run loop can be in a non-default mode.
        let startTime = Date()
        pollForTermination(sessionManager: sessionManager, startTime: startTime)

        return .terminateLater
    }

    private func pollForTermination(sessionManager: SessionManager, startTime: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let allDead = sessionManager.allProcessesTerminated
            let elapsed = Date().timeIntervalSince(startTime)

            if allDead || elapsed >= 3.0 {
                if !allDead {
                    sessionManager.forceKillAllProcesses()
                }
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                self?.pollForTermination(sessionManager: sessionManager, startTime: startTime)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager?.save()
    }

    func applicationDidResignActive(_ notification: Notification) {
        sessionManager?.save()
    }
}
