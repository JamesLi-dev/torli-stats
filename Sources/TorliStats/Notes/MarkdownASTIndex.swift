import Foundation
import Markdown

/// Standard Markdown block information supplied by Apple's parser. The
/// editor still keeps its own UTF-16 ranges because NSTextStorage and
/// NSTextView use them, while swift-markdown source locations use UTF-8 bytes.
enum MarkdownASTKind: Equatable {
    case heading(level: Int)
    case unorderedList
    case orderedList
    case quote(depth: Int)
    case code
    case divider
}

struct MarkdownASTIndex {
    private struct Span {
        let kind: MarkdownASTKind
        let range: NSRange
    }

    private enum ListKind {
        case unordered
        case ordered
    }

    private let spans: [Span]

    init(source: String) {
        let offsets = SourceOffsetMap(source: source)
        var collector = Collector(offsets: offsets)
        collector.collect(Document(parsing: source))
        spans = collector.spans
    }

    func kind(for lineRange: NSRange) -> MarkdownASTKind? {
        let matches = spans.filter {
            NSIntersectionRange($0.range, lineRange).length > 0 ||
                NSLocationInRange(lineRange.location, $0.range) ||
                NSLocationInRange($0.range.location, lineRange)
        }
        guard !matches.isEmpty else { return nil }

        // A code span wins over all nested nodes. A quote wins over a list or
        // paragraph inside it, matching Markdown's block ownership.
        if let code = matches.first(where: {
            if case .code = $0.kind { return true }
            return false
        }) {
            return code.kind
        }
        if let quote = matches.first(where: {
            if case .quote = $0.kind { return true }
            return false
        }) {
            return quote.kind
        }
        if let heading = matches.first(where: {
            if case .heading = $0.kind { return true }
            return false
        }) {
            return heading.kind
        }
        if let divider = matches.first(where: {
            if case .divider = $0.kind { return true }
            return false
        }) {
            return divider.kind
        }
        return matches.first(where: {
            switch $0.kind {
            case .unorderedList, .orderedList: true
            default: false
            }
        })?.kind
    }

    private struct Collector {
        let offsets: SourceOffsetMap
        var spans: [Span] = []

        mutating func collect(_ markup: Markup,
                              list: ListKind? = nil,
                              quoteDepth: Int = 0) {
            if let range = markup.range.flatMap(offsets.nsRange(for:)) {
                if let heading = markup as? Heading {
                    spans.append(Span(kind: .heading(level: heading.level), range: range))
                } else if markup is CodeBlock {
                    spans.append(Span(kind: .code, range: range))
                } else if markup is ThematicBreak {
                    spans.append(Span(kind: .divider, range: range))
                } else if markup is BlockQuote {
                    spans.append(Span(kind: .quote(depth: max(1, quoteDepth + 1)), range: range))
                } else if markup is ListItem, let list {
                    spans.append(Span(kind: list == .ordered ? .orderedList : .unorderedList,
                                      range: range))
                }
            }

            let childList: ListKind?
            if markup is OrderedList {
                childList = .ordered
            } else if markup is UnorderedList {
                childList = .unordered
            } else {
                childList = list
            }
            let childQuoteDepth = markup is BlockQuote ? quoteDepth + 1 : quoteDepth
            for child in markup.children {
                collect(child, list: childList, quoteDepth: childQuoteDepth)
            }
        }
    }

    private struct SourceOffsetMap {
        let bytes: [UInt8]
        let lineStarts: [Int]
        let source: String

        init(source: String) {
            self.source = source
            bytes = Array(source.utf8)
            var starts = [0]
            for (index, byte) in bytes.enumerated() where byte == 0x0A {
                starts.append(index + 1)
            }
            lineStarts = starts
        }

        func nsRange(for range: SourceRange) -> NSRange? {
            guard let lower = utf16Offset(for: range.lowerBound),
                  let upper = utf16Offset(for: range.upperBound),
                  upper >= lower else { return nil }
            return NSRange(location: lower, length: upper - lower)
        }

        private func utf16Offset(for location: SourceLocation) -> Int? {
            let line = location.line - 1
            guard line >= 0, line < lineStarts.count else { return nil }
            let start = lineStarts[line]
            let end = line + 1 < lineStarts.count ? lineStarts[line + 1] : bytes.count
            let column = max(0, location.column - 1)
            let byteOffset = min(end, start + column)
            let prefix = bytes[0..<byteOffset]
            return String(decoding: prefix, as: UTF8.self).utf16.count
        }
    }
}
