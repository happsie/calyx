import SwiftUI
import AppKit

struct NotesView: View {
    let session: Session
    @State private var editor = EditorState()

    var body: some View {
        VStack(spacing: 0) {
            NotesToolbar(editor: editor)
            Divider()
            RichTextEditor(session: session, editor: editor)
        }
    }
}

// MARK: - Editor State

/// Shared state between the toolbar and the NSTextView coordinator.
@Observable
private class EditorState {
    weak var textView: NSTextView?

    // Saved selection — toolbar clicks steal focus, so we preserve the range
    // from the last selection change and use it for all formatting actions.
    var savedRange = NSRange(location: 0, length: 0)

    // Current selection attributes (updated on selection change)
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var currentFontSize: CGFloat = 14
    var hasBulletList = false
    var hasNumberedList = false
    var hasCheckboxList = false

    /// Run a formatting closure, restoring focus + selection around it.
    private func withTextView(_ body: (NSTextView) -> Void) {
        guard let textView else { return }
        let window = textView.window

        // Restore selection (may have been lost when SwiftUI button stole focus)
        textView.setSelectedRange(savedRange)

        body(textView)

        refreshAttributes()
        persistChanges()

        // Give focus back to the text view
        window?.makeFirstResponder(textView)
    }

    // MARK: - Formatting actions

    func toggleBold() {
        withTextView { tv in
            if savedRange.length == 0 {
                toggleTypingAttribute(trait: .boldFontMask)
            } else {
                toggleTrait(in: savedRange, trait: .boldFontMask)
            }
        }
    }

    func toggleItalic() {
        withTextView { tv in
            if savedRange.length == 0 {
                toggleTypingAttribute(trait: .italicFontMask)
            } else {
                toggleTrait(in: savedRange, trait: .italicFontMask)
            }
        }
    }

    func toggleUnderline() {
        withTextView { tv in
            if savedRange.length == 0 {
                let current = tv.typingAttributes[.underlineStyle] as? Int ?? 0
                tv.typingAttributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            } else {
                let storage = tv.textStorage!
                let current = storage.attribute(.underlineStyle, at: savedRange.location, effectiveRange: nil) as? Int ?? 0
                let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                storage.beginEditing()
                storage.addAttribute(.underlineStyle, value: newValue, range: savedRange)
                storage.endEditing()
            }
        }
    }

    func toggleStrikethrough() {
        withTextView { tv in
            if savedRange.length == 0 {
                let current = tv.typingAttributes[.strikethroughStyle] as? Int ?? 0
                tv.typingAttributes[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            } else {
                let storage = tv.textStorage!
                let current = storage.attribute(.strikethroughStyle, at: savedRange.location, effectiveRange: nil) as? Int ?? 0
                let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                storage.beginEditing()
                storage.addAttribute(.strikethroughStyle, value: newValue, range: savedRange)
                storage.endEditing()
            }
        }
    }

    func applyHeading(_ size: CGFloat, weight: NSFont.Weight) {
        withTextView { tv in
            let font = NSFont.systemFont(ofSize: size, weight: weight)

            // Always update typing attributes so new text uses this size
            tv.typingAttributes[.font] = font

            // Also restyle existing text on the current line(s)
            guard let storage = tv.textStorage else { return }
            let lineRange = (storage.string as NSString).lineRange(for: savedRange)
            if lineRange.length > 0 {
                storage.beginEditing()
                storage.addAttribute(.font, value: font, range: lineRange)
                storage.endEditing()
            }
        }
    }

    func toggleBulletList() {
        withTextView { _ in
            toggleListPrefix("\u{2022}\t", isBullet: true)
        }
    }

    func toggleNumberedList() {
        withTextView { _ in
            toggleListPrefix("1.\t", isBullet: false)
        }
    }

    func toggleCheckboxList() {
        withTextView { _ in
            toggleCheckboxPrefix()
        }
    }

    /// Apply large font styling to a checkbox character at the given location.
    private func styleCheckbox(in storage: NSTextStorage, at location: Int) {
        let checkboxRange = NSRange(location: location, length: 1)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: checkboxRange)
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: checkboxRange)
    }

    /// Toggle a checkbox at the given character index (called on click).
    func toggleCheckboxAt(_ charIndex: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineText = string.substring(with: lineRange)

        if lineText.hasPrefix("\u{2610}\t") {
            // Unchecked → checked
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 1), with: "\u{2611}")
            styleCheckbox(in: storage, at: lineRange.location)
            // Apply strikethrough to the line content after the checkbox
            let contentStart = lineRange.location + 2 // checkbox + tab
            let contentLength = lineRange.length - 2 - (lineText.hasSuffix("\n") ? 1 : 0)
            if contentLength > 0 {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                     range: NSRange(location: contentStart, length: contentLength))
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                     range: NSRange(location: contentStart, length: contentLength))
            }
            storage.endEditing()
            persistChanges()
        } else if lineText.hasPrefix("\u{2611}\t") {
            // Checked → unchecked
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 1), with: "\u{2610}")
            styleCheckbox(in: storage, at: lineRange.location)
            let contentStart = lineRange.location + 2
            let contentLength = lineRange.length - 2 - (lineText.hasSuffix("\n") ? 1 : 0)
            if contentLength > 0 {
                storage.removeAttribute(.strikethroughStyle, range: NSRange(location: contentStart, length: contentLength))
                storage.addAttribute(.foregroundColor, value: NSColor.textColor,
                                     range: NSRange(location: contentStart, length: contentLength))
            }
            storage.endEditing()
            persistChanges()
        }
    }

    // MARK: - Internal helpers

    private func toggleTypingAttribute(trait: NSFontTraitMask) {
        guard let textView else { return }
        let currentFont = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let fm = NSFontManager.shared
        let hasTrait = fm.traits(of: currentFont).contains(trait)
        let newFont = hasTrait
            ? fm.convert(currentFont, toNotHaveTrait: trait)
            : fm.convert(currentFont, toHaveTrait: trait)
        textView.typingAttributes[.font] = newFont
    }

    private func toggleTrait(in range: NSRange, trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        let fm = NSFontManager.shared
        let currentFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: 14)
        let hasTrait = fm.traits(of: currentFont).contains(trait)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
            let newFont = hasTrait
                ? fm.convert(font, toNotHaveTrait: trait)
                : fm.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
        storage.endEditing()
    }

    private func toggleListPrefix(_ prefix: String, isBullet: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: savedRange)

        let lines = string.substring(with: lineRange)
        let lineArray = lines.components(separatedBy: "\n")
        let allHavePrefix = lineArray.allSatisfy {
            $0.isEmpty
            || (isBullet && $0.hasPrefix("\u{2022}"))
            || (!isBullet && $0.first?.isNumber == true && $0.contains(".\t"))
        }
        let hasContent = lineArray.contains { !$0.isEmpty }

        storage.beginEditing()
        if allHavePrefix && hasContent {
            var offset = lineRange.location
            for line in lineArray {
                let lr = NSRange(location: offset, length: (line as NSString).length)
                if isBullet && line.hasPrefix("\u{2022}\t") {
                    storage.replaceCharacters(in: NSRange(location: lr.location, length: 2), with: "")
                    offset += lr.length - 2
                } else if !isBullet, let dotTab = line.range(of: ".\t"),
                          line.prefix(upTo: dotTab.lowerBound).allSatisfy(\.isNumber) {
                    let prefixLen = line.distance(from: line.startIndex, to: dotTab.upperBound)
                    storage.replaceCharacters(in: NSRange(location: lr.location, length: prefixLen), with: "")
                    offset += lr.length - prefixLen
                } else {
                    offset += lr.length
                }
                offset += 1
            }
        } else {
            var offset = lineRange.location
            var number = 1
            for line in lineArray {
                let lr = NSRange(location: offset, length: (line as NSString).length)
                // Insert prefix on non-empty lines, or on the cursor line if it's empty
                if !line.isEmpty || lr.location == savedRange.location {
                    let p = isBullet ? prefix : "\(number).\t"
                    let attrs: [NSAttributedString.Key: Any]
                    if storage.length > 0, lr.location < storage.length {
                        attrs = storage.attributes(at: lr.location, effectiveRange: nil)
                    } else {
                        attrs = textView.typingAttributes
                    }
                    storage.insert(NSAttributedString(string: p, attributes: attrs), at: lr.location)
                    offset += lr.length + p.count
                    number += 1
                } else {
                    offset += lr.length
                }
                offset += 1
            }
        }
        storage.endEditing()
    }

    private func toggleCheckboxPrefix() {
        guard let textView, let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: savedRange)
        let lines = string.substring(with: lineRange)
        let lineArray = lines.components(separatedBy: "\n")

        let allHaveCheckbox = lineArray.allSatisfy {
            $0.isEmpty || $0.hasPrefix("\u{2610}\t") || $0.hasPrefix("\u{2611}\t")
        }
        let hasContent = lineArray.contains { !$0.isEmpty }

        storage.beginEditing()
        if allHaveCheckbox && hasContent {
            // Remove checkbox prefixes
            var offset = lineRange.location
            for line in lineArray {
                let lr = NSRange(location: offset, length: (line as NSString).length)
                if line.hasPrefix("\u{2610}\t") || line.hasPrefix("\u{2611}\t") {
                    storage.replaceCharacters(in: NSRange(location: lr.location, length: 2), with: "")
                    // Remove strikethrough/color if it was checked
                    let contentLength = lr.length - 2
                    if contentLength > 0 {
                        storage.removeAttribute(.strikethroughStyle, range: NSRange(location: lr.location, length: contentLength))
                        storage.addAttribute(.foregroundColor, value: NSColor.textColor,
                                             range: NSRange(location: lr.location, length: contentLength))
                    }
                    offset += lr.length - 2
                } else {
                    offset += lr.length
                }
                offset += 1 // newline
            }
        } else {
            // Add checkbox prefixes
            var offset = lineRange.location
            for line in lineArray {
                let lr = NSRange(location: offset, length: (line as NSString).length)
                if !line.isEmpty || lr.location == savedRange.location {
                    let prefix = "\u{2610}\t"
                    let attrs: [NSAttributedString.Key: Any]
                    if storage.length > 0, lr.location < storage.length {
                        attrs = storage.attributes(at: lr.location, effectiveRange: nil)
                    } else {
                        attrs = textView.typingAttributes
                    }
                    storage.insert(NSAttributedString(string: prefix, attributes: attrs), at: lr.location)
                    styleCheckbox(in: storage, at: lr.location)
                    offset += lr.length + prefix.count
                } else {
                    offset += lr.length
                }
                offset += 1
            }
        }
        storage.endEditing()
    }

    func refreshAttributes() {
        guard let textView else { return }
        let range = savedRange
        let attrs: [NSAttributedString.Key: Any]
        if range.length > 0, let storage = textView.textStorage, range.location < storage.length {
            attrs = storage.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }

        let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let fm = NSFontManager.shared
        let traits = fm.traits(of: font)
        isBold = traits.contains(.boldFontMask)
        isItalic = traits.contains(.italicFontMask)
        isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        isStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
        currentFontSize = font.pointSize

        if let storage = textView.textStorage, storage.length > 0 {
            let loc = min(range.location, storage.length - 1)
            let cursorLine = (storage.string as NSString).lineRange(for: NSRange(location: loc, length: 0))
            let lineText = (storage.string as NSString).substring(with: cursorLine)
            hasBulletList = lineText.hasPrefix("\u{2022}\t")
            hasNumberedList = lineText.first?.isNumber == true && lineText.contains(".\t")
            hasCheckboxList = lineText.hasPrefix("\u{2610}\t") || lineText.hasPrefix("\u{2611}\t")
        } else {
            hasBulletList = false
            hasNumberedList = false
            hasCheckboxList = false
        }
    }

    func insertTemplate(_ template: NoteTemplate) {
        guard let textView, let storage = textView.textStorage else { return }
        let window = textView.window

        let attrString = template.attributedString
        let insertAt = storage.length > 0 ? storage.length : 0

        // Add a newline separator if there's already content
        storage.beginEditing()
        if insertAt > 0 {
            let newline = NSAttributedString(string: "\n\n", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor,
            ])
            storage.append(newline)
        }
        storage.append(attrString)
        storage.endEditing()

        persistChanges()

        // Place cursor at the end
        let endPos = storage.length
        textView.setSelectedRange(NSRange(location: endPos, length: 0))
        savedRange = textView.selectedRange()
        refreshAttributes()
        window?.makeFirstResponder(textView)
    }

    func persistChanges() {
        guard let textView else { return }
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
    }
}

// MARK: - Toolbar

private struct NotesToolbar: View {
    let editor: EditorState

    var body: some View {
        HStack(spacing: 2) {
            // Heading picker — fixed width to prevent layout jumps
            Menu {
                Button("Title") { editor.applyHeading(28, weight: .bold) }
                Button("Heading") { editor.applyHeading(22, weight: .bold) }
                Button("Subheading") { editor.applyHeading(18, weight: .semibold) }
                Divider()
                Button("Body") { editor.applyHeading(14, weight: .regular) }
            } label: {
                Text(headingLabel)
                    .font(.system(size: 11))
                    .frame(width: 72, alignment: .leading)
            }
            .menuStyle(.button)
            .frame(width: 90)

            toolbarDivider

            // Bold / Italic / Underline / Strikethrough
            formatButton("bold", active: editor.isBold) { editor.toggleBold() }
            formatButton("italic", active: editor.isItalic) { editor.toggleItalic() }
            formatButton("underline", active: editor.isUnderline) { editor.toggleUnderline() }
            formatButton("strikethrough", active: editor.isStrikethrough) { editor.toggleStrikethrough() }

            toolbarDivider

            // Lists
            formatButton("list.bullet", active: editor.hasBulletList) { editor.toggleBulletList() }
            formatButton("list.number", active: editor.hasNumberedList) { editor.toggleNumberedList() }
            formatButton("checklist", active: editor.hasCheckboxList) { editor.toggleCheckboxList() }

            Spacer()

            // Template menu
            Menu {
                ForEach(NoteTemplate.allCases, id: \.self) { template in
                    Button {
                        editor.insertTemplate(template)
                    } label: {
                        Label(template.rawValue, systemImage: template.icon)
                    }
                }
            } label: {
                Label("Templates", systemImage: "doc.text")
                    .font(.system(size: 11))
            }
            .menuStyle(.button)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private var headingLabel: String {
        let size = editor.currentFontSize
        if size >= 26 { return "Title" }
        if size >= 20 { return "Heading" }
        if size >= 16 { return "Subheading" }
        return "Body"
    }

    private func formatButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: active ? .bold : .regular))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .background(active ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }
}

// MARK: - Note Templates

private enum NoteTemplate: String, CaseIterable {
    case majorMediumMinor = "Major / Medium / Minor"
    case todoList = "TODO List"

    var icon: String {
        switch self {
        case .majorMediumMinor: return "chart.bar.fill"
        case .todoList: return "checklist"
        }
    }

    var attributedString: NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 14)
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: NSColor.textColor]
        let checkboxAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.textColor]

        func appendCheckboxLine(trailing: String = "\n") {
            result.append(NSAttributedString(string: "\u{2610}", attributes: checkboxAttrs))
            result.append(NSAttributedString(string: "\t\(trailing)", attributes: bodyAttrs))
        }

        switch self {
        case .majorMediumMinor:
            let headingFont = NSFont.systemFont(ofSize: 22, weight: .bold)
            let subheadingFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
            let headingAttrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: NSColor.textColor]
            let subheadingAttrs: [NSAttributedString.Key: Any] = [.font: subheadingFont, .foregroundColor: NSColor.textColor]

            result.append(NSAttributedString(string: "Change Notes\n", attributes: headingAttrs))
            result.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            result.append(NSAttributedString(string: "Major\n", attributes: subheadingAttrs))
            result.append(NSAttributedString(string: "\u{2022}\t\n", attributes: bodyAttrs))
            result.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            result.append(NSAttributedString(string: "Medium\n", attributes: subheadingAttrs))
            result.append(NSAttributedString(string: "\u{2022}\t\n", attributes: bodyAttrs))
            result.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            result.append(NSAttributedString(string: "Minor\n", attributes: subheadingAttrs))
            result.append(NSAttributedString(string: "\u{2022}\t", attributes: bodyAttrs))

        case .todoList:
            let headingFont = NSFont.systemFont(ofSize: 22, weight: .bold)
            let headingAttrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: NSColor.textColor]

            result.append(NSAttributedString(string: "TODO\n", attributes: headingAttrs))
            result.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            appendCheckboxLine()
            appendCheckboxLine()
            appendCheckboxLine(trailing: "")
        }

        return result
    }
}

// MARK: - Checkbox-aware Text View

private class CheckboxTextView: NSTextView {
    weak var editorState: EditorState?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        guard let storage = textStorage, charIndex < storage.length else {
            super.mouseDown(with: event)
            return
        }

        let string = storage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineText = string.substring(with: lineRange)

        // Check if the line starts with a checkbox and the click is on the checkbox character
        if (lineText.hasPrefix("\u{2610}\t") || lineText.hasPrefix("\u{2611}\t")),
           charIndex >= lineRange.location && charIndex < lineRange.location + 2 {
            editorState?.toggleCheckboxAt(lineRange.location)
            return
        }

        super.mouseDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else {
            super.insertNewline(sender)
            return
        }

        let string = storage.string as NSString
        let cursorLoc = selectedRange().location
        let lineRange = string.lineRange(for: NSRange(location: cursorLoc, length: 0))
        let lineText = string.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")

        // Detect which list type the current line uses
        let isCheckbox = lineText.hasPrefix("\u{2610}\t") || lineText.hasPrefix("\u{2611}\t")
        let isBullet = lineText.hasPrefix("\u{2022}\t")
        let isNumbered = lineText.first?.isNumber == true && lineText.contains(".\t")

        // If the line is just a prefix with no content, remove it (end the list)
        if isCheckbox && (lineText == "\u{2610}\t" || lineText == "\u{2611}\t") {
            let replaceRange = NSRange(location: lineRange.location, length: (lineText as NSString).length)
            storage.beginEditing()
            storage.replaceCharacters(in: replaceRange, with: "")
            storage.endEditing()
            return
        }
        if isBullet && lineText == "\u{2022}\t" {
            let replaceRange = NSRange(location: lineRange.location, length: (lineText as NSString).length)
            storage.beginEditing()
            storage.replaceCharacters(in: replaceRange, with: "")
            storage.endEditing()
            return
        }
        if isNumbered, let dotTab = lineText.range(of: ".\t"),
           lineText.prefix(upTo: dotTab.lowerBound).allSatisfy(\.isNumber) {
            let afterPrefix = lineText[dotTab.upperBound...]
            if afterPrefix.isEmpty {
                let replaceRange = NSRange(location: lineRange.location, length: (lineText as NSString).length)
                storage.beginEditing()
                storage.replaceCharacters(in: replaceRange, with: "")
                storage.endEditing()
                return
            }
        }

        // Continue list on new line
        if isCheckbox {
            super.insertNewline(sender)
            let checkboxAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20),
                .foregroundColor: NSColor.textColor,
            ]
            let bodyAttrs = typingAttributes
            let line = NSMutableAttributedString(string: "\u{2610}", attributes: checkboxAttrs)
            line.append(NSAttributedString(string: "\t", attributes: bodyAttrs))
            insertText(line, replacementRange: selectedRange())
            return
        }

        if isBullet {
            super.insertNewline(sender)
            let attrs = typingAttributes
            insertText(NSAttributedString(string: "\u{2022}\t", attributes: attrs), replacementRange: selectedRange())
            return
        }

        if isNumbered, let dotTab = lineText.range(of: ".\t"),
           let num = Int(lineText.prefix(upTo: dotTab.lowerBound)) {
            super.insertNewline(sender)
            let attrs = typingAttributes
            insertText(NSAttributedString(string: "\(num + 1).\t", attributes: attrs), replacementRange: selectedRange())
            return
        }

        super.insertNewline(sender)
    }
}

// MARK: - Rich Text Editor

private struct RichTextEditor: NSViewRepresentable {
    let session: Session
    let editor: EditorState

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = CheckboxTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false

        let defaultFont = NSFont.systemFont(ofSize: 14)
        textView.typingAttributes = [
            .font: defaultFont,
            .foregroundColor: NSColor.textColor,
        ]

        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        // Load existing RTF data, or insert session name as default title
        if let rtfData = session.notesRTFData,
           let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           attrString.length > 0 {
            textView.textStorage?.setAttributedString(attrString)
            // Restyle any existing checkboxes to use larger font
            if let storage = textView.textStorage {
                let fullString = storage.string as NSString
                storage.beginEditing()
                fullString.enumerateSubstrings(in: NSRange(location: 0, length: fullString.length), options: .byLines) { _, lineRange, _, _ in
                    let line = fullString.substring(with: lineRange)
                    if line.hasPrefix("\u{2610}") || line.hasPrefix("\u{2611}") {
                        let cbRange = NSRange(location: lineRange.location, length: 1)
                        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: cbRange)
                        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: cbRange)
                    }
                }
                storage.endEditing()
            }
        } else {
            let titleFont = NSFont.systemFont(ofSize: 28, weight: .bold)
            let title = NSAttributedString(string: "\(session.name)\n", attributes: [
                .font: titleFont,
                .foregroundColor: NSColor.textColor,
            ])
            textView.textStorage?.setAttributedString(title)
            // Place cursor on the line after the title
            let endPos = title.length
            textView.setSelectedRange(NSRange(location: endPos, length: 0))
        }

        textView.editorState = editor
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        editor.textView = textView
        editor.refreshAttributes()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, editor: editor)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let session: Session
        let editor: EditorState
        weak var textView: NSTextView?

        init(session: Session, editor: EditorState) {
            self.session = session
            self.editor = editor
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let range = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            session.notesRTFData = textView.textStorage?.rtf(from: range, documentAttributes: [:])
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            editor.savedRange = textView.selectedRange()
            editor.refreshAttributes()
        }
    }
}
