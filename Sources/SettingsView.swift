import SwiftUI
import AppKit

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var description: String {
        switch self {
        case .system: "Match macOS"
        case .light: "Always light"
        case .dark: "Always dark"
        }
    }
}

// MARK: - Code Editor

enum CodeEditor: String, CaseIterable, Codable, Identifiable {
    case vscode = "VS Code"
    case intellij = "IntelliJ"
    case zed = "Zed"

    var id: String { rawValue }

    var bundleId: String {
        switch self {
        case .vscode: "com.microsoft.VSCode"
        case .intellij: "com.jetbrains.intellij"
        case .zed: "dev.zed.Zed"
        }
    }

    var cliCommand: String {
        switch self {
        case .vscode: "code"
        case .intellij: "idea"
        case .zed: "zed"
        }
    }

    /// Returns the app icon from the installed application, or nil if not installed.
    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func open(directory: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cliCommand, directory]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func open(file: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        switch self {
        case .vscode:
            process.arguments = [cliCommand, "--goto", file]
        case .intellij, .zed:
            process.arguments = [cliCommand, file]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

// MARK: - App Settings

@Observable
final class AppSettings {
    var appearanceMode: AppearanceMode {
        didSet {
            save()
            applyAppearance()
        }
    }

    var dangerousMode: Bool {
        didSet { save() }
    }

    var defaultDiffMode: DiffViewMode {
        didSet { save() }
    }

    var defaultEditor: CodeEditor {
        didSet { save() }
    }

    var terminalFontName: String {
        didSet {
            save()
            postTerminalFontChange()
        }
    }

    var terminalFontSize: Double {
        didSet {
            save()
            postTerminalFontChange()
        }
    }

    var customPlanPaths: [String] = [] {
        didSet { save() }
    }

    static let terminalFontDidChange = Notification.Name("AppSettingsTerminalFontDidChange")
    private static let appearanceKey = "appearanceMode"
    private static let dangerousModeKey = "dangerousMode"
    private static let diffModeKey = "defaultDiffMode"
    private static let editorKey = "defaultEditor"
    private static let fontNameKey = "terminalFontName"
    private static let fontSizeKey = "terminalFontSize"
    private static let customPlanPathsKey = "customPlanPaths"

    static let defaultFontCandidates = [
        "JetBrainsMono Nerd Font",
        "JetBrainsMonoNL Nerd Font",
        "JetBrains Mono",
    ]

    static func resolvedTerminalFont() -> NSFont {
        let name = UserDefaults.standard.string(forKey: fontNameKey) ?? ""
        let size = UserDefaults.standard.double(forKey: fontSizeKey)
        let resolvedSize = size > 0 ? size : 13
        let cgSize = CGFloat(resolvedSize)

        if !name.isEmpty, let font = NSFont(name: name, size: cgSize) {
            return font
        }
        for candidate in defaultFontCandidates {
            if let font = NSFont(name: candidate, size: cgSize) {
                return font
            }
        }
        return .monospacedSystemFont(ofSize: cgSize, weight: .regular)
    }

    /// The family name of the font that `resolvedTerminalFont()` actually returns.
    static func resolvedTerminalFontName() -> String {
        resolvedTerminalFont().familyName ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).familyName!
    }

    private func postTerminalFontChange() {
        NotificationCenter.default.post(name: Self.terminalFontDidChange, object: nil)
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.appearanceKey),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
        self.dangerousMode = UserDefaults.standard.bool(forKey: Self.dangerousModeKey)
        if let raw = UserDefaults.standard.string(forKey: Self.diffModeKey),
           let mode = DiffViewMode(rawValue: raw) {
            self.defaultDiffMode = mode
        } else {
            self.defaultDiffMode = .unified
        }
        if let raw = UserDefaults.standard.string(forKey: Self.editorKey),
           let editor = CodeEditor(rawValue: raw) {
            self.defaultEditor = editor
        } else {
            self.defaultEditor = .vscode
        }
        self.terminalFontName = UserDefaults.standard.string(forKey: Self.fontNameKey) ?? Self.resolvedTerminalFontName()
        let storedSize = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        self.terminalFontSize = storedSize > 0 ? storedSize : 13
        self.customPlanPaths = UserDefaults.standard.stringArray(forKey: Self.customPlanPathsKey) ?? []
        applyAppearance()
    }

    private func save() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceKey)
        UserDefaults.standard.set(dangerousMode, forKey: Self.dangerousModeKey)
        UserDefaults.standard.set(defaultDiffMode.rawValue, forKey: Self.diffModeKey)
        UserDefaults.standard.set(defaultEditor.rawValue, forKey: Self.editorKey)
        UserDefaults.standard.set(terminalFontName, forKey: Self.fontNameKey)
        UserDefaults.standard.set(terminalFontSize, forKey: Self.fontSizeKey)
        UserDefaults.standard.set(customPlanPaths, forKey: Self.customPlanPathsKey)
    }

    private func applyAppearance() {
        guard let app = NSApp else { return }
        app.appearance = appearanceMode.nsAppearance
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        AppearanceCard(
                            mode: mode,
                            isSelected: settings.appearanceMode == mode
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.appearanceMode = mode
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Default Editor", selection: $settings.defaultEditor) {
                    ForEach(CodeEditor.allCases) { editor in
                        EditorLabel(editor: editor)
                            .tag(editor)
                    }
                }

                Picker("Default Diff View", selection: $settings.defaultDiffMode) {
                    ForEach(DiffViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } header: {
                Text("General")
            }

            Section {
                TerminalFontSettings(settings: settings)
            } header: {
                Text("Terminal")
            }

            Section {
                CustomPlanPathsSettings(settings: settings)
            } header: {
                Text("Plan Paths")
            }

            Section {
                Toggle(isOn: $settings.dangerousMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip permission prompts")
                        Text("Passes --dangerously-skip-permissions to Claude")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Agent")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Terminal Font Settings

private struct TerminalFontSettings: View {
    @Bindable var settings: AppSettings

    private var monospacedFamilies: [String] {
        let fm = NSFontManager.shared
        return fm.availableFontFamilies.filter { family in
            if let font = NSFont(name: family, size: 13) {
                return font.isFixedPitch
            }
            return false
        }.sorted()
    }

    var body: some View {
        Picker("Font", selection: $settings.terminalFontName) {
            ForEach(monospacedFamilies, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .onAppear {
            let families = monospacedFamilies
            if !families.contains(settings.terminalFontName) {
                settings.terminalFontName = AppSettings.resolvedTerminalFontName()
            }
        }

        HStack {
            Text("Size")
            Spacer()
            TextField("", value: $settings.terminalFontSize, format: .number)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
            Stepper("", value: $settings.terminalFontSize, in: 10...24, step: 1)
                .labelsHidden()
        }

        Text("The quick brown fox jumps over the lazy dog\n0123456789 !@#$%^&*()")
            .font(.init(AppSettings.resolvedTerminalFont()))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Custom Plan Paths Settings

private struct CustomPlanPathsSettings: View {
    @Bindable var settings: AppSettings
    @State private var newPath = ""

    private var isAddEnabled: Bool {
        !newPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(settings.customPlanPaths.enumerated()), id: \.offset) { index, path in
                HStack {
                    Text(path)
                        .font(.body)
                    Spacer()
                    Button("Remove") {
                        settings.customPlanPaths.remove(at: index)
                    }
                }
            }

            HStack {
                TextField("", text: $newPath, prompt: Text("e.g. .claude/plans"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit { addPath() }

                Button("Add", action: addPath)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isAddEnabled)
            }

            Text("Directories relative to the project root scanned for plan markdown files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .labelsHidden()
    }

    private func addPath() {
        let trimmed = newPath.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, !settings.customPlanPaths.contains(trimmed) else { return }
        settings.customPlanPaths.append(trimmed)
        newPath = ""
    }
}

// MARK: - Appearance Card

private struct AppearanceCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(previewFill)
                    .frame(width: 72, height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    }
                    .overlay {
                        previewContent
                    }

                Text(mode.rawValue)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var previewFill: Color {
        switch mode {
        case .light: .white
        case .dark: Color(white: 0.15)
        case .system: .clear
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch mode {
        case .light:
            previewLines(background: .white, lines: Color(white: 0.85))
        case .dark:
            previewLines(background: Color(white: 0.15), lines: Color(white: 0.28))
        case .system:
            HStack(spacing: 0) {
                previewLines(background: .white, lines: Color(white: 0.85))
                    .clipShape(.rect(topLeadingRadius: 6, bottomLeadingRadius: 6))
                previewLines(background: Color(white: 0.15), lines: Color(white: 0.28))
                    .clipShape(.rect(bottomTrailingRadius: 6, topTrailingRadius: 6))
            }
        }
    }

    private func previewLines(background: Color, lines: Color) -> some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lines)
                    .frame(width: 26, height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lines)
                    .frame(width: 18, height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lines)
                    .frame(width: 22, height: 3)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Editor Label

private struct EditorLabel: View {
    let editor: CodeEditor

    var body: some View {
        if let icon = editor.appIcon {
            Label {
                Text(editor.rawValue)
            } icon: {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
        } else {
            Label(editor.rawValue, systemImage: "app.dashed")
        }
    }
}
