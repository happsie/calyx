import SwiftUI
import SwiftTerm

struct TerminalContentView: NSViewRepresentable {
    var command: String?
    var fontSize: CGFloat = 13
    var onTerminalCreated: ((LocalProcessTerminalView) -> Void)? = nil

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        applyTheme(to: terminalView)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let resolved = command.flatMap { resolveExecutable($0) }

        let executable = shell
        let args: [String] = if let path = resolved {
            ["-l", "-c", path]
        } else {
            ["-l"]
        }

        terminalView.startProcess(
            executable: executable,
            args: args,
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
            execName: (executable as NSString).lastPathComponent
        )

        onTerminalCreated?(terminalView)
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    private func applyTheme(to view: LocalProcessTerminalView) {
        // Soft dark background that sits well alongside macOS chrome
        view.nativeBackgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        view.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)

        // Muted ANSI palette — 8 normal + 8 bright
        view.installColors([
            color(0x3B, 0x3B, 0x42),  // black
            color(0xD4, 0x6A, 0x6A),  // red
            color(0x8C, 0xBE, 0x8C),  // green
            color(0xD4, 0xB8, 0x6A),  // yellow
            color(0x6A, 0x9F, 0xD4),  // blue
            color(0xB8, 0x7E, 0xC6),  // magenta
            color(0x6A, 0xC4, 0xBF),  // cyan
            color(0xC5, 0xC5, 0xCA),  // white

            color(0x5A, 0x5A, 0x64),  // bright black
            color(0xE8, 0x8C, 0x8C),  // bright red
            color(0xA8, 0xD4, 0xA8),  // bright green
            color(0xE8, 0xD0, 0x8C),  // bright yellow
            color(0x8C, 0xBB, 0xE8),  // bright blue
            color(0xCE, 0x9E, 0xDA),  // bright magenta
            color(0x8C, 0xDA, 0xD4),  // bright cyan
            color(0xE0, 0xE0, 0xE5),  // bright white
        ])
    }
}

// MARK: - Helpers

/// SwiftTerm Color uses UInt16 components in 0...65535 range.
private func color(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
    SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
}

private func resolveExecutable(_ name: String) -> String? {
    let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
        .split(separator: ":")

    for dir in searchPaths {
        let candidate = "\(dir)/\(name)"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}
