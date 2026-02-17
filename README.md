# Calyx

A macOS app for managing multiple AI coding agent sessions (Claude, Gemini, Copilot) with integrated terminals, git worktrees, and diff viewing.

## Requirements

- macOS 14+
- Swift 5.9+

## Build & Run

```bash
swift build
swift run
```

No Xcode project needed — this is a Swift Package with an executable target.

## Build DMG

To create a distributable `.dmg`:

```bash
./scripts/build-dmg.sh
```

This builds a release binary, assembles a `.app` bundle, code-signs it, and packages it into `Calyx.dmg` in the project root.

Recipients should right-click the app and choose **Open** the first time to bypass Gatekeeper.

## Features

- **Multi-agent sessions** — run Claude, Gemini, or Copilot side by side
- **Integrated terminals** — each session has its own persistent terminal
- **Git worktrees** — sessions automatically create and work inside isolated worktrees
- **Diff viewer** — unified and side-by-side diff modes with syntax highlighting
- **Session persistence** — sessions save and restore across app launches
