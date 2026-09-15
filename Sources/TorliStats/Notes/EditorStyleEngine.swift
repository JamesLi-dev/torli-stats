import AppKit

extension NSAttributedString.Key {
    /// Marks Markdown punctuation that should occupy no glyph space while the
    /// plain-text source remains untouched.
    static let notesHidden = NSAttributedString.Key("notesHidden")

    /// Stores the visual state for an inline Todo marker while preserving the
    /// Unicode checkbox in the note's plain-text source.
    static let taskCheckbox = NSAttributedString.Key("taskCheckbox")

    /// Marks a block quote line for the layout manager's callout decoration.
    static let quoteDecoration = NSAttributedString.Key("quoteDecoration")

    /// Marks YAML front matter, code blocks, and horizontal divider lines for custom drawing.
    static let frontMatterDecoration = NSAttributedString.Key("frontMatterDecoration")
    static let codeBlockDecoration = NSAttributedString.Key("codeBlockDecoration")
    static let dividerDecoration = NSAttributedString.Key("dividerDecoration")
}

struct QuoteDecoration {
    let fill: NSColor
    let bar: NSColor
    let barGap: CGFloat
    let barWidth: CGFloat
    let barRadius: CGFloat
}

struct FrontMatterDecoration {
    let fill: NSColor
    let text: NSColor
    let font: NSFont
    let placeholder: Bool
}

struct CodeBlockDecoration {
    let fill: NSColor
}

struct DividerDecoration {
    let color: NSColor
    let thickness: CGFloat
}

/// Accumulates TextKit character edits until it is safe to style them.
/// Marked-text composition deliberately leaves the pending ranges untouched.
struct EditorEditAccumulator {
    private(set) var pending: [NSRange] = []

    var hasPendingEdits: Bool { !pending.isEmpty }

    mutating func record(_ range: NSRange) {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else { return }
        pending.append(range)
    }

    mutating func consume(in text: NSString, hasMarkedText: Bool) -> [NSRange] {
        guard !hasMarkedText, !pending.isEmpty else { return [] }
        let edits = pending
        pending.removeAll(keepingCapacity: true)
        return EditorStyleEngine.affectedLineRanges(for: edits, in: text)
    }

    mutating func clear() {
        pending.removeAll(keepingCapacity: true)
    }
}

/// Applies note attributes without owning editor state. Every normal edit is
/// planned as one or more complete-line ranges; full-document work is reserved
/// for initial content and explicit configuration changes.
enum EditorStyleEngine {
    typealias FontProvider = (CGFloat) -> NSFont

    private static let bold = try! NSRegularExpression(
        pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(
        pattern: "(?<![\\*_])([\\*_])(?=[^\\*_\\s])(.+?)(?<=[^\\*_\\s])\\1(?![\\*_])")
    private static let code = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private static let struck = try! NSRegularExpression(
        pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let link = try! NSRegularExpression(
        pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")

    /// A note is ordinary text, and text can carry any scheme somebody typed or
    /// imported. Only these three are ever made clickable — the rest are styled
    /// and inert, so a note can never become a launcher for something else.
    private static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    /// The destination of a Markdown link, or nil if it is not one of ours.
    static func openableURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              openableSchemes.contains(scheme) else { return nil }
        return url
    }

    /// The complete line containing a UTF-16 location. At EOF after a trailing
    /// newline this correctly returns the zero-length final line.
    static func lineRange(containing location: Int, in text: NSString) -> NSRange {
        let safeLocation = min(max(0, location), text.length)
        return text.lineRange(for: NSRange(location: safeLocation, length: 0))
    }

    /// Expand character edits to complete lines. One character on either side
    /// is included before expansion so inserting/deleting a newline restyles
    /// both paragraphs that changed identity.
    static func affectedLineRanges(for edits: [NSRange], in text: NSString) -> [NSRange] {
        guard !edits.isEmpty else { return [] }
        guard text.length > 0 else { return [NSRange(location: 0, length: 0)] }

        let expanded = edits.compactMap { edit -> NSRange? in
            guard let safe = clamped(edit, to: text.length) else { return nil }
            let lower = max(0, safe.location - 1)
            let upper = min(text.length, safe.location + safe.length + 1)
            return text.lineRange(for: NSRange(location: lower, length: upper - lower))
        }
        let lines = merged(expanded, length: text.length, keepingEmpty: false)
        let rescanned = MarkdownBlockParser.expandedRanges(for: lines, in: text as String)
        return merged(rescanned, length: text.length, keepingEmpty: false)
    }

    /// Clamp, sort, and merge only overlapping or adjacent ranges. Distant
    /// caret lines stay disjoint so styling never scans the gap between them.
    static func normalizedStyleRanges(_ ranges: [NSRange], length: Int) -> [NSRange] {
        merged(ranges, length: length, keepingEmpty: false)
    }

    /// Apply base, Markdown, and completed-task attributes to scoped ranges.
    /// The string and selection are never mutated.
    @discardableResult
    static func apply(to textView: NSTextView,
                      ranges: [NSRange],
                      revealing activeLine: NSRange?,
                      ink: NSColor,
                      size: CGFloat,
                      markdownEnabled: Bool,
                      textDirection: NoteTextDirection = .automatic,
                      bodyFont: @escaping FontProvider) -> [NSRange] {
        let font = bodyFont(size)
        let paragraphStyle = textDirection.paragraphStyle
        textView.typingAttributes = [.font: font, .foregroundColor: ink,
                                     .paragraphStyle: paragraphStyle]

        guard let storage = textView.textStorage else { return [] }
        let planned = normalizedStyleRanges(ranges, length: storage.length)
        guard !planned.isEmpty else { return [] }

        for range in planned {
            // Process disjoint ranges separately. NSTextStorage coalesces edits
            // inside one begin/end pair, which would otherwise invalidate the
            // untouched gap between two distant caret lines.
            storage.beginEditing()
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.obliqueness, range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.taskCheckbox, range: range)
            storage.removeAttribute(.quoteDecoration, range: range)
            storage.removeAttribute(.frontMatterDecoration, range: range)
            storage.removeAttribute(.codeBlockDecoration, range: range)
            storage.removeAttribute(.dividerDecoration, range: range)
            storage.removeAttribute(.notesHidden, range: range)
            // Both belong to links. Styling is line-scoped, so an attribute left
            // behind when the syntax around it is deleted never gets cleaned up
            // by a later pass — the line would stay underlined and clickable.
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.link, range: range)
            storage.addAttribute(.foregroundColor, value: ink, range: range)
            storage.addAttribute(.font, value: font, range: range)
            applyParagraphStyles(to: storage, range: range, direction: textDirection)

            let fragment = storage.mutableString.substring(with: range)
            styleTasks(storage, fragment, offset: range.location, ink: ink, font: font)
            if markdownEnabled {
                markdown(storage, fragment, offset: range.location, ink: ink,
                         size: size, revealing: activeLine,
                         frontMatterAllowed: range.location == 0,
                         bodyFont: bodyFont)
            }
            styleCompletedTasks(storage, fragment, offset: range.location, ink: ink)
            storage.endEditing()

            // Hidden markers require glyph regeneration, but only for the lines
            // whose attributes were actually touched.
            textView.layoutManager?.invalidateGlyphs(forCharacterRange: range,
                                                      changeInLength: 0,
                                                      actualCharacterRange: nil)
            textView.layoutManager?.invalidateLayout(forCharacterRange: range,
                                                      actualCharacterRange: nil)
            textView.layoutManager?.invalidateDisplay(forCharacterRange: range)
        }
        return planned
    }

    /// Apply Automatic independently to every paragraph so mixed-language
    /// notes can contain both English and Arabic/Hebrew paragraphs naturally.
    private static func applyParagraphStyles(to storage: NSTextStorage,
                                             range: NSRange,
                                             direction: NoteTextDirection) {
        guard direction == .automatic else {
            storage.addAttribute(.paragraphStyle, value: direction.paragraphStyle, range: range)
            return
        }

        let text = storage.mutableString
        let upperBound = NSMaxRange(range)
        var location = range.location
        while location < upperBound {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            let target = NSIntersectionRange(paragraph, range)
            guard target.length > 0 else { break }
            let contents = text.substring(with: paragraph)
            storage.addAttribute(.paragraphStyle,
                                 value: direction.paragraphStyle(for: contents),
                                 range: target)
            location = NSMaxRange(target)
        }
    }

    /// The only characters any of the expressions below can match on. A link
    /// needs its opening bracket, and nothing else in a URL is Markdown at all —
    /// leaving `[` out here silently switched links off.
    private static let markdownChars = CharacterSet(charactersIn: "*_`~#>-+[")

    private static func markdown(_ storage: NSTextStorage, _ fragment: String,
                                 offset: Int, ink: NSColor, size: CGFloat,
                                 revealing activeLine: NSRange?,
                                 frontMatterAllowed: Bool,
                                 bodyFont: @escaping FontProvider) {
        for block in MarkdownBlockParser.parse(fragment,
                                               frontMatterAllowed: frontMatterAllowed) {
            styleBlock(storage, fragment, block, offset: offset, ink: ink, size: size,
                       activeLine: activeLine, bodyFont: bodyFont)
        }
    }

    private static func styleBlock(_ storage: NSTextStorage, _ fragment: String,
                                   _ block: MarkdownBlock, offset: Int, ink: NSColor,
                                   size: CGFloat, activeLine: NSRange?,
                                   bodyFont: @escaping FontProvider) {
        func global(_ range: NSRange) -> NSRange {
            NSRange(location: offset + range.location, length: range.length)
        }

        func dim(_ localRange: NSRange) {
            guard localRange.length > 0 else { return }
            let range = global(localRange)
            let faint = ink.withAlphaComponent(0.32)
            if let activeLine,
               NSIntersectionRange(range, activeLine).length > 0 || activeLine.location == range.location {
                storage.addAttribute(.foregroundColor, value: faint, range: range)
            } else {
                storage.addAttribute(.notesHidden, value: true, range: range)
                storage.addAttribute(.foregroundColor, value: faint, range: range)
            }
        }

        func hide(_ localRange: NSRange) {
            guard localRange.length > 0 else { return }
            storage.addAttribute(.notesHidden, value: true, range: global(localRange))
        }

        func inline(_ localRange: NSRange) {
            guard localRange.length > 0 else { return }
            let local = fragment as NSString
            let content = local.substring(with: localRange)
            inlineMarkdown(storage, content, offset: offset + localRange.location,
                           ink: ink, size: size, activeLine: activeLine,
                           bodyFont: bodyFont)
        }

        switch block.kind {
        case .heading(let level):
            let bump = max(1.5, 7 - CGFloat(level) * 1.1)
            storage.addAttribute(.font, value: heavier(size + bump, bodyFont: bodyFont),
                                 range: global(block.lineRange))
            dim(block.markerRange)
            inline(block.contentRange)

        case .unorderedList:
            styleListParagraph(storage, fragment, block, offset: offset,
                               font: bodyFont(size))
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.58),
                                 range: global(block.markerRange))
            inline(block.contentRange)

        case .orderedList:
            styleListParagraph(storage, fragment, block, offset: offset,
                               font: bodyFont(size))
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.58),
                                 range: global(block.markerRange))
            inline(block.contentRange)

        case .todo:
            // TaskTextView's custom glyph is independent of Markdown styling;
            // only the body receives inline Markdown attributes here.
            inline(block.contentRange)

        case .frontMatter:
            let font = NSFont.monospacedSystemFont(ofSize: max(10, size - 0.5),
                                                    weight: .regular)
            let isDelimiter = block.markerRange.length > 0
            let isOpening = isDelimiter && offset + block.lineRange.location == 0
            storage.addAttribute(.font, value: font, range: global(block.lineRange))
            storage.addAttribute(.foregroundColor,
                                 value: ink.withAlphaComponent(0.58),
                                 range: global(block.lineRange))
            storage.addAttribute(.frontMatterDecoration,
                                 value: FrontMatterDecoration(
                                     fill: ink.withAlphaComponent(0.045),
                                     text: ink.withAlphaComponent(0.55),
                                     font: font,
                                     placeholder: isOpening),
                                 range: global(block.lineRange))
            if isDelimiter { hide(block.markerRange) }

        case .quote(let depth):
            let quoteInk = ink.withAlphaComponent(0.62)
            storage.addAttribute(.foregroundColor, value: quoteInk,
                                 range: global(block.lineRange))
            hide(block.markerRange)
            storage.addAttribute(.quoteDecoration,
                                 value: QuoteDecoration(
                                     fill: ink.withAlphaComponent(0.055),
                                     bar: ink.withAlphaComponent(0.48),
                                     barGap: 8,
                                     barWidth: 4,
                                     barRadius: 2),
                                 range: global(block.lineRange))
            storage.addAttribute(.obliqueness, value: 0.15,
                                 range: global(block.contentRange))
            styleQuoteParagraph(storage, block, offset: offset, depth: depth)
            inline(block.contentRange)

        case .codeFence:
            storage.addAttribute(.font,
                                 value: NSFont.monospacedSystemFont(ofSize: size - 0.5,
                                                                    weight: .regular),
                                 range: global(block.lineRange))
            storage.addAttribute(.codeBlockDecoration,
                                 value: CodeBlockDecoration(fill: ink.withAlphaComponent(0.045)),
                                 range: global(block.lineRange))
            styleCodeParagraph(storage, block, offset: offset)
            dim(block.markerRange)

        case .code:
            storage.addAttribute(.font,
                                 value: NSFont.monospacedSystemFont(ofSize: size - 0.5,
                                                                    weight: .regular),
                                 range: global(block.lineRange))
            storage.addAttribute(.codeBlockDecoration,
                                 value: CodeBlockDecoration(fill: ink.withAlphaComponent(0.045)),
                                 range: global(block.lineRange))
            styleCodeParagraph(storage, block, offset: offset)

        case .divider:
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.45),
                                 range: global(block.lineRange))
            storage.addAttribute(.dividerDecoration,
                                 value: DividerDecoration(color: ink.withAlphaComponent(0.3),
                                                          thickness: 1),
                                 range: global(block.lineRange))
            hide(block.markerRange)

        case .paragraph:
            inline(block.contentRange)
        }
    }

    private static func styleCodeParagraph(_ storage: NSTextStorage,
                                           _ block: MarkdownBlock, offset: Int) {
        let paragraph = (storage.attribute(.paragraphStyle,
                                           at: offset + block.lineRange.location,
                                           effectiveRange: nil) as? NSParagraphStyle)?
            .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        paragraph.paragraphSpacingBefore = 2
        paragraph.paragraphSpacing = 2
        storage.addAttribute(.paragraphStyle,
                             value: paragraph,
                             range: NSRange(location: offset + block.lineRange.location,
                                            length: block.lineRange.length))
    }

    private static func styleQuoteParagraph(_ storage: NSTextStorage,
                                            _ block: MarkdownBlock, offset: Int,
                                            depth: Int) {
        let paragraph = (storage.attribute(.paragraphStyle,
                                           at: offset + block.lineRange.location,
                                           effectiveRange: nil) as? NSParagraphStyle)?
            .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        // The source marker is hidden, so only a compact content inset remains.
        // Wrapped lines use the same inset and stay aligned with the callout.
        let contentInset: CGFloat = 18 + CGFloat(max(0, depth - 1)) * 12
        paragraph.firstLineHeadIndent = contentInset
        paragraph.headIndent = contentInset
        storage.addAttribute(.paragraphStyle,
                             value: paragraph,
                             range: NSRange(location: offset + block.lineRange.location,
                                            length: block.lineRange.length))
    }

    private static func styleListParagraph(_ storage: NSTextStorage, _ fragment: String,
                                           _ block: MarkdownBlock, offset: Int,
                                           font: NSFont) {
        let globalLine = NSRange(location: offset + block.lineRange.location,
                                 length: block.lineRange.length)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let indentation = displayWhitespace(block.indentation(in: fragment))
        let marker = displayWhitespace(block.marker(in: fragment))
        let indentationWidth = (indentation as NSString).size(withAttributes: attributes).width
        let markerWidth = (marker as NSString).size(withAttributes: attributes).width
        let paragraph = (storage.attribute(.paragraphStyle,
                                           at: globalLine.location,
                                           effectiveRange: nil) as? NSParagraphStyle)?
            .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = indentationWidth + markerWidth
        storage.addAttribute(.paragraphStyle, value: paragraph, range: globalLine)
    }

    private static func displayWhitespace(_ value: String) -> String {
        value.map { $0 == "\t" ? "    " : " " }.reduce(into: "") { result, value in
            result.append(value)
        }
    }

    private static func inlineMarkdown(_ storage: NSTextStorage, _ fragment: String,
                                       offset: Int, ink: NSColor, size: CGFloat,
                                       activeLine: NSRange?,
                                       bodyFont: @escaping FontProvider) {
        let local = fragment as NSString
        let full = NSRange(location: 0, length: local.length)
        guard local.rangeOfCharacter(from: markdownChars).location != NSNotFound else { return }

        func global(_ range: NSRange) -> NSRange {
            NSRange(location: offset + range.location, length: range.length)
        }

        func dim(_ localRange: NSRange) {
            guard localRange.length > 0 else { return }
            let range = global(localRange)
            let faint = ink.withAlphaComponent(0.32)
            if let activeLine,
               NSIntersectionRange(range, activeLine).length > 0 || activeLine.location == range.location {
                storage.addAttribute(.foregroundColor, value: faint, range: range)
            } else {
                storage.addAttribute(.notesHidden, value: true, range: range)
                storage.addAttribute(.foregroundColor, value: faint, range: range)
            }
        }

        func each(_ expression: NSRegularExpression,
                  _ body: @escaping (NSTextCheckingResult) -> Void) {
            expression.enumerateMatches(in: fragment, range: full) { match, _, _ in
                if let match { body(match) }
            }
        }

        each(link) { match in
            let label = match.range(at: 1)
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: global(label))
            if let url = openableURL(local.substring(with: match.range(at: 2))) {
                storage.addAttribute(.link, value: url, range: global(label))
            }
            dim(NSRange(location: match.range.location, length: 1))
            dim(NSRange(location: label.upperBound,
                        length: match.range.upperBound - label.upperBound))
        }
        each(bold) { match in
            storage.addAttribute(.font, value: heavier(size, bodyFont: bodyFont),
                                 range: global(match.range(at: 2)))
            dim(NSRange(location: match.range.location, length: 2))
            dim(NSRange(location: match.range.upperBound - 2, length: 2))
        }
        each(italic) { match in
            storage.addAttribute(.obliqueness, value: 0.2,
                                 range: global(match.range(at: 2)))
            dim(NSRange(location: match.range.location, length: 1))
            dim(NSRange(location: match.range.upperBound - 1, length: 1))
        }
        each(code) { match in
            storage.addAttribute(.font,
                                 value: NSFont.monospacedSystemFont(ofSize: size - 0.5,
                                                                    weight: .regular),
                                 range: global(match.range(at: 1)))
            storage.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.07),
                                 range: global(match.range(at: 1)))
            dim(NSRange(location: match.range.location, length: 1))
            dim(NSRange(location: match.range.upperBound - 1, length: 1))
        }
        each(struck) { match in
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: global(match.range(at: 1)))
            dim(NSRange(location: match.range.location, length: 2))
            dim(NSRange(location: match.range.upperBound - 2, length: 2))
        }
    }

    private static func styleTasks(_ storage: NSTextStorage, _ fragment: String,
                                   offset: Int, ink: NSColor, font: NSFont) {
        let local = fragment as NSString
        for block in MarkdownBlockParser.parse(fragment) {
            guard case .todo = block.kind else { continue }
            let line = local.substring(with: NSRange(location: block.lineRange.location,
                                                      length: block.lineRange.length))
            guard let task = TaskLine.parse(line) else { continue }

            let globalLine = NSRange(location: offset + block.lineRange.location,
                                     length: block.lineRange.length)
            let checkbox = NSRange(location: offset + block.lineRange.location + task.checkboxRange.location,
                                   length: task.checkboxRange.length)
            storage.addAttribute(.taskCheckbox,
                                 value: TaskCheckboxStyle(isCompleted: task.isCompleted, ink: ink),
                                 range: checkbox)
            // Hide only the source marker's glyph. Hiding the glyph retains its
            // normal advance width so the layout and caret still use the source
            // character while drawGlyphs paints the custom checkbox.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: checkbox)

            let paragraph = (storage.attribute(.paragraphStyle,
                                               at: globalLine.location,
                                               effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = TaskCheckboxRenderer.bodyHeadIndent(for: task,
                                                                       line: line,
                                                                       font: font)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: globalLine)
        }
    }

    private static func styleCompletedTasks(_ storage: NSTextStorage, _ fragment: String,
                                            offset: Int, ink: NSColor) {
        for block in MarkdownBlockParser.parse(fragment) {
            guard case .todo(let completed) = block.kind, completed,
                  block.contentRange.length > 0 else { continue }
            let body = NSRange(location: offset + block.contentRange.location,
                               length: block.contentRange.length)
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: body)
            storage.addAttribute(.foregroundColor,
                                 value: ink.withAlphaComponent(0.45), range: body)
        }
    }

    private static func heavier(_ size: CGFloat, bodyFont: FontProvider) -> NSFont {
        let base = bodyFont(size)
        let boldFont = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        return boldFont != base ? boldFont : NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else { return nil }
        let location = min(range.location, length)
        let available = length - location
        return NSRange(location: location, length: min(range.length, available))
    }

    private static func merged(_ ranges: [NSRange], length: Int,
                               keepingEmpty: Bool) -> [NSRange] {
        let safe = ranges.compactMap { clamped($0, to: length) }
            .filter { keepingEmpty || $0.length > 0 }
            .sorted {
                $0.location == $1.location ? $0.length < $1.length : $0.location < $1.location
            }
        guard var current = safe.first else { return [] }

        var result: [NSRange] = []
        for next in safe.dropFirst() {
            if next.location <= current.location + current.length {
                let upper = max(current.location + current.length,
                                next.location + next.length)
                current.length = upper - current.location
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }
}
