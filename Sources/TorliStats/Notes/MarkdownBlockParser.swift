import Foundation

// MARK: - Markdown block model

enum MarkdownBlockKind: Equatable {
    case heading(level: Int)
    case unorderedList(marker: Character)
    case orderedList(number: Int, delimiter: Character)
    case todo(completed: Bool)
    case quote(depth: Int)
    case frontMatter
    case codeFence(marker: Character, length: Int, closing: Bool)
    case code
    case divider
    case paragraph

    var isCode: Bool {
        switch self {
        case .code, .codeFence: true
        default: false
        }
    }
}

/// One physical Markdown line and the ranges that make up its syntax.
/// Ranges are UTF-16 offsets and are relative to the complete source passed to
/// the parser, so they can be used directly with NSTextStorage.
struct MarkdownBlock: Equatable {
    let kind: MarkdownBlockKind
    let lineRange: NSRange
    let markerRange: NSRange
    let contentRange: NSRange
    let indentationRange: NSRange

    func marker(in source: String) -> String {
        substring(in: source, range: markerRange)
    }

    func content(in source: String) -> String {
        substring(in: source, range: contentRange)
    }

    func indentation(in source: String) -> String {
        substring(in: source, range: indentationRange)
    }

    private func substring(in source: String, range: NSRange) -> String {
        let text = source as NSString
        guard range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= text.length else { return "" }
        return text.substring(with: range)
    }
}

/// A line-oriented block parser. It deliberately does not mutate the source;
/// syntax is hidden by attributes in EditorStyleEngine while the note remains
/// plain text.
enum MarkdownBlockParser {
    static func parse(_ source: String, frontMatterAllowed: Bool = true) -> [MarkdownBlock] {
        let text = source as NSString
        guard text.length > 0 else { return [] }

        var blocks: [MarkdownBlock] = []
        blocks.reserveCapacity(source.count / 24)
        var location = 0
        var fence: (marker: Character, length: Int)?
        var inFrontMatter = false
        let ast = MarkdownASTIndex(source: source)

        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = lineContentRange(lineRange, in: text)
            let line = text.substring(with: contentRange)
            let astKind = ast.kind(for: lineRange)

            if inFrontMatter {
                let delimiter = line == "---"
                blocks.append(MarkdownBlock(
                    kind: .frontMatter,
                    lineRange: lineRange,
                    markerRange: delimiter ? contentRange : NSRange(location: contentRange.location, length: 0),
                    contentRange: delimiter
                        ? NSRange(location: contentRange.location + contentRange.length, length: 0)
                        : contentRange,
                    indentationRange: NSRange(location: contentRange.location,
                                              length: leadingIndentationLength(in: line))))
                if delimiter { inFrontMatter = false }
                location = NSMaxRange(lineRange)
                continue
            }

            if frontMatterAllowed && blocks.isEmpty && line == "---" {
                blocks.append(MarkdownBlock(
                    kind: .frontMatter,
                    lineRange: lineRange,
                    markerRange: contentRange,
                    contentRange: NSRange(location: contentRange.location + contentRange.length,
                                          length: 0),
                    indentationRange: NSRange(location: contentRange.location, length: 0)))
                inFrontMatter = true
                location = NSMaxRange(lineRange)
                continue
            }

            if let currentFence = fence {
                if let closing = fenceMarker(in: line),
                   closing.marker == currentFence.marker,
                   closing.length >= currentFence.length {
                    blocks.append(MarkdownBlock(
                        kind: .codeFence(marker: closing.marker,
                                         length: closing.length,
                                         closing: true),
                        lineRange: lineRange,
                        markerRange: NSRange(location: contentRange.location + closing.range.location,
                                             length: closing.range.length),
                        contentRange: NSRange(location: contentRange.location + closing.range.location,
                                              length: closing.range.length),
                        indentationRange: NSRange(location: contentRange.location,
                                                  length: leadingIndentationLength(in: line))
                    ))
                    fence = nil
                } else {
                    blocks.append(MarkdownBlock(
                        kind: .code,
                        lineRange: lineRange,
                        markerRange: NSRange(location: contentRange.location, length: 0),
                        contentRange: contentRange,
                        indentationRange: NSRange(location: contentRange.location,
                                                  length: leadingIndentationLength(in: line))
                    ))
                }
                location = NSMaxRange(lineRange)
                continue
            }

            if let opening = fenceMarker(in: line) {
                let markerLocation = contentRange.location + opening.range.location
                let contentLocation = markerLocation + opening.range.length
                blocks.append(MarkdownBlock(
                    kind: .codeFence(marker: opening.marker,
                                     length: opening.length,
                                     closing: false),
                    lineRange: lineRange,
                    markerRange: NSRange(location: markerLocation, length: opening.range.length),
                    contentRange: NSRange(location: contentLocation,
                                          length: max(0, NSMaxRange(contentRange) - contentLocation)),
                    indentationRange: NSRange(location: contentRange.location,
                                              length: leadingIndentationLength(in: line))
                ))
                fence = (opening.marker, opening.length)
                location = NSMaxRange(lineRange)
                continue
            }

            // swift-markdown also recognizes indented code blocks. Keep the
            // custom fence state above for editable fence markers, then let the
            // AST cover this standard block form.
            if case .code? = astKind {
                blocks.append(MarkdownBlock(
                    kind: .code,
                    lineRange: lineRange,
                    markerRange: NSRange(location: contentRange.location, length: 0),
                    contentRange: contentRange,
                    indentationRange: NSRange(location: contentRange.location,
                                              length: leadingIndentationLength(in: line))))
                location = NSMaxRange(lineRange)
                continue
            }

            blocks.append(parseNormalLine(line,
                                          lineRange: lineRange,
                                          contentRange: contentRange,
                                          astKind: astKind))
            location = NSMaxRange(lineRange)
        }
        return blocks
    }

    static func block(containing location: Int, in source: String) -> MarkdownBlock? {
        let blocks = parse(source)
        if let containing = blocks.first(where: { NSLocationInRange(location, $0.lineRange) }) {
            return containing
        }

        // A caret immediately after the final character is still on the last
        // physical line. NSLocationInRange uses an exclusive upper bound, so
        // handle this EOF position explicitly without stealing the boundary
        // from the following line when the source ends with a newline.
        guard location == source.utf16.count else { return nil }
        return blocks.last(where: { NSMaxRange($0.lineRange) == location })
    }

    /// Return ranges that may need a wider Markdown rescan after a fence edit.
    /// Ordinary edits stay line-scoped; changing a fence rescans the affected
    /// code block (or to EOF when the current fence is unclosed).
    static func expandedRanges(for ranges: [NSRange], in source: String) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        let blocks = parse(source)
        guard !blocks.isEmpty else { return ranges }
        let text = source as NSString
        var result = ranges

        for range in ranges {
            guard let index = blocks.firstIndex(where: {
                NSIntersectionRange($0.lineRange, range).length > 0 ||
                NSLocationInRange(range.location, $0.lineRange)
            }) else { continue }

            let current = blocks[index]
            if case .frontMatter = current.kind {
                var start = index
                while start > 0, blocks[start - 1].kind == .frontMatter {
                    start -= 1
                }
                var end = index
                while end + 1 < blocks.count, blocks[end + 1].kind == .frontMatter {
                    end += 1
                }
                let first = blocks[start].lineRange.location
                let last = blocks[end].lineRange
                result.append(NSRange(location: first, length: NSMaxRange(last) - first))
                continue
            }

            let fenceSensitive = current.kind.isCode ||
                text.substring(with: current.lineRange).contains("```") ||
                text.substring(with: current.lineRange).contains("~~~")
            guard fenceSensitive else { continue }

            var start = index
            while start > 0, blocks[start - 1].kind.isCode {
                start -= 1
            }
            var end = index
            while end + 1 < blocks.count, blocks[end + 1].kind.isCode {
                end += 1
            }

            let first = blocks[start].lineRange.location
            let last = blocks[end].lineRange
            result.append(NSRange(location: first, length: NSMaxRange(last) - first))
        }
        return result
    }

    private static func parseNormalLine(_ line: String,
                                        lineRange: NSRange,
                                        contentRange: NSRange,
                                        astKind: MarkdownASTKind?) -> MarkdownBlock {
        let text = line as NSString
        let lineOffset = contentRange.location
        let indentationLength = leadingIndentationLength(in: line)
        let indentation = NSRange(location: lineOffset, length: indentationLength)
        // Accessing the AST kind here keeps standard CommonMark recognition in
        // the library; the local checks below only recover source sub-ranges
        // and Torli-specific marker behavior.
        let standardBlock = astKind
        var cursor = indentationLength

        if let divider = dividerRange(in: line) {
            return MarkdownBlock(kind: .divider,
                                  lineRange: lineRange,
                                  markerRange: shifted(divider, by: lineOffset),
                                  contentRange: shifted(divider, by: lineOffset),
                                  indentationRange: indentation)
        }

        var quoteDepth = 0
        let quoteStart = cursor
        while cursor < text.length, text.character(at: cursor) == 0x3E { // >
            quoteDepth += 1
            cursor += 1
            while cursor < text.length, horizontalWhitespace(text.character(at: cursor)) {
                cursor += 1
            }
        }
        if quoteDepth > 0,
           standardBlock.map({
               if case .quote = $0 { return true }
               return false
           }) ?? true {
            let marker = NSRange(location: lineOffset + quoteStart,
                                  length: cursor - quoteStart)
            let content = NSRange(location: lineOffset + cursor,
                                  length: max(0, text.length - cursor))
            return MarkdownBlock(kind: .quote(depth: quoteDepth),
                                  lineRange: lineRange,
                                  markerRange: marker,
                                  contentRange: content,
                                  indentationRange: indentation)
        }

        if cursor < text.length, text.character(at: cursor) == 0x23 { // #
            let headingStart = cursor
            var level = 0
            while cursor < text.length, text.character(at: cursor) == 0x23, level < 6 {
                level += 1
                cursor += 1
            }
            if level > 0, cursor < text.length,
               horizontalWhitespace(text.character(at: cursor)),
               standardBlock.map({
                   if case .heading = $0 { return true }
                   return false
               }) ?? true {
                while cursor < text.length, horizontalWhitespace(text.character(at: cursor)) {
                    cursor += 1
                }
                return MarkdownBlock(kind: .heading(level: level),
                                      lineRange: lineRange,
                                      markerRange: NSRange(location: lineOffset + headingStart,
                                                           length: cursor - headingStart),
                                      contentRange: NSRange(location: lineOffset + cursor,
                                                            length: max(0, text.length - cursor)),
                                      indentationRange: indentation)
            }
            cursor = indentationLength
        }

        if let unordered = unorderedList(in: line, from: cursor),
           standardBlock == .unorderedList || unordered.prefixLength == 1 {
            let marker = NSRange(location: lineOffset + cursor, length: unordered.prefixLength)
            return MarkdownBlock(kind: .unorderedList(marker: unordered.marker),
                                  lineRange: lineRange,
                                  markerRange: marker,
                                  contentRange: NSRange(location: lineOffset + cursor + unordered.prefixLength,
                                                        length: max(0, text.length - cursor - unordered.prefixLength)),
                                  indentationRange: indentation)
        }

        if let ordered = orderedList(in: line, from: cursor),
           standardBlock == .orderedList || ordered.prefixLength == 2 || ordered.prefixLength == 1 {
            let marker = NSRange(location: lineOffset + cursor, length: ordered.prefixLength)
            return MarkdownBlock(kind: .orderedList(number: ordered.number,
                                                    delimiter: ordered.delimiter),
                                  lineRange: lineRange,
                                  markerRange: marker,
                                  contentRange: NSRange(location: lineOffset + cursor + ordered.prefixLength,
                                                        length: max(0, text.length - cursor - ordered.prefixLength)),
                                  indentationRange: indentation)
        }

        if cursor == indentationLength,
           let task = TaskLine.parse(line),
           task.checkboxRange.location == indentationLength {
            return MarkdownBlock(kind: .todo(completed: task.isCompleted),
                                  lineRange: lineRange,
                                  markerRange: NSRange(location: lineOffset + task.checkboxRange.location,
                                                       length: task.checkboxRange.length),
                                  contentRange: NSRange(location: lineOffset + task.bodyRange.location,
                                                        length: task.bodyRange.length),
                                  indentationRange: indentation)
        }

        return MarkdownBlock(kind: .paragraph,
                              lineRange: lineRange,
                              markerRange: NSRange(location: lineOffset, length: 0),
                              contentRange: contentRange,
                              indentationRange: indentation)
    }

    private static func fenceMarker(in line: String) -> (marker: Character, length: Int, range: NSRange)? {
        let text = line as NSString
        let indentation = leadingIndentationLength(in: line)
        guard indentation <= 3, indentation < text.length else { return nil }
        let first = text.character(at: indentation)
        guard first == 0x60 || first == 0x7E else { return nil } // ` or ~

        var cursor = indentation
        while cursor < text.length, text.character(at: cursor) == first {
            cursor += 1
        }
        let length = cursor - indentation
        guard length >= 3 else { return nil }
        if first == 0x60, line.contains("`") && cursor < text.length {
            // Backtick fences cannot contain another backtick in the info string.
            let remainder = text.substring(from: cursor)
            if remainder.contains("`") { return nil }
        }
        return (first == 0x60 ? "`" : "~",
                length,
                NSRange(location: indentation, length: length))
    }

    private static func unorderedList(in line: String, from cursor: Int) -> (marker: Character, prefixLength: Int)? {
        let text = line as NSString
        guard cursor < text.length else { return nil }
        let value = text.character(at: cursor)
        guard value == 0x2D || value == 0x2A || value == 0x2B else { return nil }
        var end = cursor + 1
        if end == text.length {
            // Keep a marker-only line editable as a list while the user is
            // still typing the conventional separating space.
            return (value == 0x2D ? "-" : value == 0x2A ? "*" : "+", end - cursor)
        }
        guard horizontalWhitespace(text.character(at: end)) else { return nil }
        while end < text.length, horizontalWhitespace(text.character(at: end)) { end += 1 }
        return (value == 0x2D ? "-" : value == 0x2A ? "*" : "+", end - cursor)
    }

    private static func orderedList(in line: String, from cursor: Int) -> (number: Int, delimiter: Character, prefixLength: Int)? {
        let text = line as NSString
        guard cursor < text.length, text.character(at: cursor) >= 0x30,
              text.character(at: cursor) <= 0x39 else { return nil }
        var end = cursor
        while end < text.length,
              text.character(at: end) >= 0x30,
              text.character(at: end) <= 0x39 {
            end += 1
        }
        guard end < text.length,
              text.character(at: end) == 0x2E || text.character(at: end) == 0x29 else { return nil }
        let delimiterLocation = end
        let delimiter: Character = text.character(at: delimiterLocation) == 0x2E ? "." : ")"
        end += 1
        let number = Int(text.substring(with: NSRange(location: cursor,
                                                       length: delimiterLocation - cursor))) ?? 1
        if end == text.length {
            // As with unordered markers, accept `1.` at the end of a line so
            // Return can create `2. ` without requiring a preliminary space.
            return (number, delimiter, end - cursor)
        }
        guard horizontalWhitespace(text.character(at: end)) else { return nil }
        while end < text.length, horizontalWhitespace(text.character(at: end)) { end += 1 }
        return (number, delimiter, end - cursor)
    }

    private static func dividerRange(in line: String) -> NSRange? {
        let text = line as NSString
        var indices: [Int] = []
        var cursor = 0
        while cursor < text.length {
            let value = text.character(at: cursor)
            if !horizontalWhitespace(value) { indices.append(cursor) }
            cursor += 1
        }
        guard indices.count >= 2 else { return nil }
        let first = text.character(at: indices[0])
        let isLongDash = first == 0x2014 || first == 0x2013 // — or –
        let isMarkdownRule = first == 0x2D || first == 0x2A || first == 0x5F
        guard isLongDash || isMarkdownRule else { return nil }
        guard isLongDash || indices.count >= 3 else { return nil }
        guard indices.allSatisfy({ text.character(at: $0) == first }) else { return nil }
        return NSRange(location: indices[0], length: indices.last! - indices[0] + 1)
    }

    private static func lineContentRange(_ lineRange: NSRange, in text: NSString) -> NSRange {
        var length = lineRange.length
        let end = lineRange.location + length
        if length > 0, text.character(at: end - 1) == 0x0A {
            length -= 1
            if length > 0, text.character(at: lineRange.location + length - 1) == 0x0D {
                length -= 1
            }
        } else if length > 0, text.character(at: end - 1) == 0x0D {
            length -= 1
        }
        return NSRange(location: lineRange.location, length: length)
    }

    private static func leadingIndentationLength(in line: String) -> Int {
        let text = line as NSString
        var length = 0
        while length < text.length, horizontalWhitespace(text.character(at: length)) {
            length += 1
        }
        return length
    }

    private static func horizontalWhitespace(_ value: unichar) -> Bool {
        value == 0x20 || value == 0x09
    }

    private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}
