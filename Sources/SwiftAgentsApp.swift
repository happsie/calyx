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

class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionManager: SessionManager?
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

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager?.save()
    }

    func applicationDidResignActive(_ notification: Notification) {
        sessionManager?.save()
    }
}
