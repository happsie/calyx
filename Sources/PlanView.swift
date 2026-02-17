import SwiftUI
import WebKit

// MARK: - Plan File Model

struct PlanFile: Identifiable, Equatable {
    let id: String  // relative path
    let name: String
    let relativePath: String
    let content: String
    let lastModified: Date

    static func == (lhs: PlanFile, rhs: PlanFile) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.lastModified == rhs.lastModified
    }
}

// MARK: - Plan View

struct PlanView: View {
    let session: Session
    @State private var selectedFile: PlanFile?

    var body: some View {
        let files = session.planFiles

        if files.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                // Rendered markdown content
                if let file = selectedFile ?? files.first {
                    MarkdownWebView(markdown: file.content, fileName: file.name)
                } else {
                    emptyState
                }

                Divider()

                // File list sidebar
                planFileList(files: files)
                    .frame(width: 240)
            }
            .onChange(of: files) { _, newFiles in
                // Keep selection valid
                if let sel = selectedFile, !newFiles.contains(where: { $0.id == sel.id }) {
                    selectedFile = newFiles.first
                }
                // Auto-select if nothing selected
                if selectedFile == nil {
                    selectedFile = newFiles.first
                }
            }
            .onAppear {
                if selectedFile == nil {
                    selectedFile = files.first
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No plan files yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Markdown files will appear here as agents create them")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planFileList(files: [PlanFile]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files) { file in
                        planFileRow(file: file)
                            .onTapGesture { selectedFile = file }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func planFileRow(file: PlanFile) -> some View {
        let isActive = selectedFile?.id == file.id

        return HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if file.relativePath != file.name {
                    let dir = (file.relativePath as NSString).deletingLastPathComponent
                    if !dir.isEmpty {
                        Text(dir)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Markdown WebView

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fileName: String
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadHTML(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadHTML(into: webView)
    }

    private func loadHTML(into webView: WKWebView) {
        let html = markdownToHTML(markdown)
        let css = colorScheme == .dark ? darkThemeCSS : lightThemeCSS
        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }
}

// MARK: - Theme CSS

private let darkThemeCSS = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        background: rgb(33, 33, 38);
        color: rgb(217, 217, 222);
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
        font-size: 14px;
        line-height: 1.6;
        padding: 24px 32px;
        -webkit-font-smoothing: antialiased;
    }
    h1, h2, h3, h4, h5, h6 {
        color: rgb(235, 235, 240);
        margin-top: 1.4em;
        margin-bottom: 0.6em;
        font-weight: 600;
    }
    h1 { font-size: 1.8em; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 0.3em; }
    h2 { font-size: 1.4em; border-bottom: 1px solid rgba(255,255,255,0.07); padding-bottom: 0.2em; }
    h3 { font-size: 1.15em; }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
    p { margin-bottom: 0.8em; }
    a { color: rgb(106, 159, 212); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
        font-family: 'SF Mono', Menlo, monospace;
        font-size: 0.9em;
        background: rgba(255, 255, 255, 0.08);
        padding: 0.15em 0.4em;
        border-radius: 4px;
    }
    pre {
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 8px;
        padding: 14px 18px;
        margin: 0.8em 0;
        overflow-x: auto;
    }
    pre code {
        background: none;
        padding: 0;
        font-size: 13px;
        line-height: 1.5;
    }
    ul, ol { margin: 0.5em 0 0.8em 1.6em; }
    li { margin-bottom: 0.3em; }
    li > ul, li > ol { margin-top: 0.2em; margin-bottom: 0.2em; }
    blockquote {
        border-left: 3px solid rgba(106, 159, 212, 0.5);
        padding: 0.4em 1em;
        margin: 0.8em 0;
        color: rgb(180, 180, 185);
        background: rgba(255, 255, 255, 0.03);
        border-radius: 0 4px 4px 0;
    }
    hr {
        border: none;
        border-top: 1px solid rgba(255, 255, 255, 0.1);
        margin: 1.5em 0;
    }
    table {
        border-collapse: collapse;
        margin: 0.8em 0;
        width: 100%;
    }
    th, td {
        border: 1px solid rgba(255, 255, 255, 0.1);
        padding: 8px 12px;
        text-align: left;
    }
    th {
        background: rgba(255, 255, 255, 0.05);
        font-weight: 600;
    }
    strong { color: rgb(235, 235, 240); }
    em { font-style: italic; }
    img { max-width: 100%; border-radius: 4px; }
    ::-webkit-scrollbar { width: 8px; height: 8px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 4px; }
"""

private let lightThemeCSS = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        background: rgb(255, 255, 255);
        color: rgb(36, 36, 40);
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
        font-size: 14px;
        line-height: 1.6;
        padding: 24px 32px;
        -webkit-font-smoothing: antialiased;
    }
    h1, h2, h3, h4, h5, h6 {
        color: rgb(20, 20, 24);
        margin-top: 1.4em;
        margin-bottom: 0.6em;
        font-weight: 600;
    }
    h1 { font-size: 1.8em; border-bottom: 1px solid rgba(0,0,0,0.1); padding-bottom: 0.3em; }
    h2 { font-size: 1.4em; border-bottom: 1px solid rgba(0,0,0,0.07); padding-bottom: 0.2em; }
    h3 { font-size: 1.15em; }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
    p { margin-bottom: 0.8em; }
    a { color: rgb(41, 98, 155); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
        font-family: 'SF Mono', Menlo, monospace;
        font-size: 0.9em;
        background: rgba(0, 0, 0, 0.06);
        padding: 0.15em 0.4em;
        border-radius: 4px;
    }
    pre {
        background: rgba(0, 0, 0, 0.04);
        border: 1px solid rgba(0, 0, 0, 0.08);
        border-radius: 8px;
        padding: 14px 18px;
        margin: 0.8em 0;
        overflow-x: auto;
    }
    pre code {
        background: none;
        padding: 0;
        font-size: 13px;
        line-height: 1.5;
    }
    ul, ol { margin: 0.5em 0 0.8em 1.6em; }
    li { margin-bottom: 0.3em; }
    li > ul, li > ol { margin-top: 0.2em; margin-bottom: 0.2em; }
    blockquote {
        border-left: 3px solid rgba(41, 98, 155, 0.5);
        padding: 0.4em 1em;
        margin: 0.8em 0;
        color: rgb(80, 80, 85);
        background: rgba(0, 0, 0, 0.03);
        border-radius: 0 4px 4px 0;
    }
    hr {
        border: none;
        border-top: 1px solid rgba(0, 0, 0, 0.1);
        margin: 1.5em 0;
    }
    table {
        border-collapse: collapse;
        margin: 0.8em 0;
        width: 100%;
    }
    th, td {
        border: 1px solid rgba(0, 0, 0, 0.1);
        padding: 8px 12px;
        text-align: left;
    }
    th {
        background: rgba(0, 0, 0, 0.04);
        font-weight: 600;
    }
    strong { color: rgb(20, 20, 24); }
    em { font-style: italic; }
    img { max-width: 100%; border-radius: 4px; }
    ::-webkit-scrollbar { width: 8px; height: 8px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: rgba(0,0,0,0.15); border-radius: 4px; }
"""

// MARK: - Markdown to HTML Converter

func markdownToHTML(_ markdown: String) -> String {
    let lines = markdown.components(separatedBy: "\n")
    var html = ""
    var inCodeBlock = false
    var inList = false
    var listType = ""  // "ul" or "ol"
    var inBlockquote = false

    func closeList() {
        if inList {
            html += "</\(listType)>\n"
            inList = false
        }
    }

    func closeBlockquote() {
        if inBlockquote {
            html += "</blockquote>\n"
            inBlockquote = false
        }
    }

    for line in lines {
        // Fenced code blocks
        if line.hasPrefix("```") {
            if inCodeBlock {
                html += "</code></pre>\n"
                inCodeBlock = false
            } else {
                closeList()
                closeBlockquote()
                inCodeBlock = true
                html += "<pre><code>"
            }
            continue
        }

        if inCodeBlock {
            html += escapeHTML(line) + "\n"
            continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Empty line
        if trimmed.isEmpty {
            closeList()
            closeBlockquote()
            continue
        }

        // Horizontal rule
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            closeList()
            closeBlockquote()
            html += "<hr>\n"
            continue
        }

        // Headings
        if let heading = parseHeading(trimmed) {
            closeList()
            closeBlockquote()
            html += heading
            continue
        }

        // Blockquote
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            closeList()
            if !inBlockquote {
                inBlockquote = true
                html += "<blockquote>\n"
            }
            let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
            html += "<p>\(inlineMarkdown(content))</p>\n"
            continue
        }

        // Unordered list
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            closeBlockquote()
            if !inList || listType != "ul" {
                closeList()
                inList = true
                listType = "ul"
                html += "<ul>\n"
            }
            let content = String(trimmed.dropFirst(2))
            html += "<li>\(inlineMarkdown(content))</li>\n"
            continue
        }

        // Ordered list
        if let range = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            closeBlockquote()
            if !inList || listType != "ol" {
                closeList()
                inList = true
                listType = "ol"
                html += "<ol>\n"
            }
            let content = String(trimmed[range.upperBound...])
            html += "<li>\(inlineMarkdown(content))</li>\n"
            continue
        }

        // Regular paragraph
        closeList()
        closeBlockquote()
        html += "<p>\(inlineMarkdown(trimmed))</p>\n"
    }

    // Close any open blocks
    if inCodeBlock { html += "</code></pre>\n" }
    closeList()
    closeBlockquote()

    return html
}

private func parseHeading(_ line: String) -> String? {
    let levels = [(prefix: "######", tag: "h6"), ("##### ", "h5"), ("#### ", "h4"),
                  ("### ", "h3"), ("## ", "h2"), ("# ", "h1")]
    for (prefix, tag) in levels {
        if line.hasPrefix(prefix) {
            let content = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return "<\(tag)>\(inlineMarkdown(content))</\(tag)>\n"
        }
    }
    return nil
}

private func inlineMarkdown(_ text: String) -> String {
    var result = escapeHTML(text)

    // Inline code (must be first to prevent inner processing)
    result = result.replacingOccurrences(
        of: "`([^`]+)`",
        with: "<code>$1</code>",
        options: .regularExpression
    )

    // Bold+italic
    result = result.replacingOccurrences(
        of: #"\*\*\*(.+?)\*\*\*"#,
        with: "<strong><em>$1</em></strong>",
        options: .regularExpression
    )

    // Bold
    result = result.replacingOccurrences(
        of: #"\*\*(.+?)\*\*"#,
        with: "<strong>$1</strong>",
        options: .regularExpression
    )

    // Italic
    result = result.replacingOccurrences(
        of: #"\*(.+?)\*"#,
        with: "<em>$1</em>",
        options: .regularExpression
    )

    // Links [text](url)
    result = result.replacingOccurrences(
        of: #"\[([^\]]+)\]\(([^)]+)\)"#,
        with: "<a href=\"$2\">$1</a>",
        options: .regularExpression
    )

    return result
}

private func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}
