import Foundation

enum DiffLineType {
    case unchanged
    case added
    case removed
}

struct InlineChange {
    let range: NSRange
    let isAddition: Bool
}

struct DiffLine {
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let inlineChanges: [InlineChange]
}

enum DiffViewMode: String, CaseIterable {
    case unified = "Unified"
    case sideBySide = "Side by Side"
}

enum FileChangeType: String {
    case modified = "Modified"
    case added = "Added"
    case deleted = "Deleted"
    case renamed = "Renamed"
}

struct FileDiff: Identifiable {
    let id = UUID()
    let fileName: String
    let language: String
    let changeType: FileChangeType
    let oldText: String
    let newText: String

    /// Create a FileDiff with auto-detected language from the file extension.
    init(fileName: String, changeType: FileChangeType, oldText: String, newText: String) {
        self.fileName = fileName
        self.language = Self.detectLanguage(from: fileName)
        self.changeType = changeType
        self.oldText = oldText
        self.newText = newText
    }

    /// Create a FileDiff with an explicit language override.
    init(fileName: String, language: String, changeType: FileChangeType, oldText: String, newText: String) {
        self.fileName = fileName
        self.language = language
        self.changeType = changeType
        self.oldText = oldText
        self.newText = newText
    }

    private static func detectLanguage(from fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "mts", "cts": return "typescript"
        case "tsx": return "tsx"
        case "jsx": return "jsx"
        case "py": return "python"
        case "rb": return "ruby"
        case "rs": return "rust"
        case "go": return "go"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "cs": return "csharp"
        case "m", "mm": return "objectivec"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "xml", "plist": return "xml"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "md", "markdown": return "markdown"
        case "dockerfile": return "dockerfile"
        default:
            // Check full filename for special cases
            let name = (fileName as NSString).lastPathComponent.lowercased()
            switch name {
            case "dockerfile": return "dockerfile"
            case "makefile", "gnumakefile": return "makefile"
            case "cmakelists.txt": return "cmake"
            default: return "plaintext"
            }
        }
    }
}
