import XCTest
import AppKit
@testable import TorliStats

final class MarkdownBlockTests: XCTestCase {
    func testAppleMarkdownASTIndexRecognizesStandardBlocks() {
        let source = "# Title\n- item\n> quote\n```swift\ncode\n```"
        let index = MarkdownASTIndex(source: source)
        let text = source as NSString
        let lines = ["# Title", "- item", "> quote", "```swift", "code"].map {
            let start = text.range(of: $0).location
            return text.lineRange(for: NSRange(location: start, length: 0))
        }

        XCTAssertEqual(index.kind(for: lines[0]), .heading(level: 1))
        XCTAssertEqual(index.kind(for: lines[1]), .unorderedList)
        XCTAssertEqual(index.kind(for: lines[2]), .quote(depth: 1))
        XCTAssertEqual(index.kind(for: lines[3]), .code)
        XCTAssertEqual(index.kind(for: lines[4]), .code)
    }

    func testParsesBlockKindsAndRanges() {
        let source = "# Title\n  - item\n1) next\n>> quote\n---\n☑ done\n"
        let blocks = MarkdownBlockParser.parse(source)

        XCTAssertEqual(blocks.map(\.kind), [
            .heading(level: 1),
            .unorderedList(marker: "-"),
            .orderedList(number: 1, delimiter: ")"),
            .quote(depth: 2),
            .divider,
            .todo(completed: true)
        ])
        XCTAssertEqual(blocks[0].content(in: source), "Title")
        XCTAssertEqual(blocks[1].indentation(in: source), "  ")
        XCTAssertEqual(blocks[1].marker(in: source), "- ")
        XCTAssertEqual(blocks[2].content(in: source), "next")
        XCTAssertEqual(blocks[3].marker(in: source), ">> ")
        XCTAssertEqual(blocks[5].content(in: source), "done")
    }

    func testParsesFrontMatterAndFourDashDivider() {
        let source = "---\ntitle: Demo\n---\n----\nbody"
        let blocks = MarkdownBlockParser.parse(source)

        XCTAssertEqual(blocks.map(\.kind), [
            .frontMatter,
            .frontMatter,
            .frontMatter,
            .divider,
            .paragraph
        ])
        XCTAssertEqual(blocks[0].marker(in: source), "---")
        XCTAssertEqual(blocks[1].content(in: source), "title: Demo")
        XCTAssertEqual(blocks[2].marker(in: source), "---")
        XCTAssertEqual(blocks[3].marker(in: source), "----")
    }

    func testParsesDividerVariants() {
        let source = "* * *\n- - -\n——\n----\n--"
        let blocks = MarkdownBlockParser.parse(source)

        XCTAssertEqual(blocks.map(\.kind), [
            .divider,
            .divider,
            .divider,
            .divider,
            .paragraph
        ])
    }

    func testCodeFenceMakesAllInteriorLinesCodeAndSkipsNestedMarkdown() {
        let source = "```swift\n**not bold**\n- not a list\n```\nparagraph\n"
        let blocks = MarkdownBlockParser.parse(source)

        XCTAssertEqual(blocks.map(\.kind), [
            .codeFence(marker: "`", length: 3, closing: false),
            .code,
            .code,
            .codeFence(marker: "`", length: 3, closing: true),
            .paragraph
        ])
        XCTAssertEqual(blocks[0].content(in: source), "swift")
        XCTAssertEqual(blocks[1].content(in: source), "**not bold**")
        XCTAssertEqual(blocks[3].marker(in: source), "```")
    }

    func testUnclosedFenceContinuesToEndOfDocument() {
        let source = "before\n~~~\n# still code\n"
        let blocks = MarkdownBlockParser.parse(source)

        XCTAssertEqual(blocks.map(\.kind), [
            .paragraph,
            .codeFence(marker: "~", length: 3, closing: false),
            .code
        ])
        XCTAssertTrue(blocks.last?.kind.isCode == true)
    }

    func testFenceEditsExpandRescanToTheCodeBlock() {
        let source = "before\n```\ncode\n```\nafter\n"
        let line = (source as NSString).lineRange(for: NSRange(location: 7, length: 0))
        let expanded = MarkdownBlockParser.expandedRanges(for: [line], in: source)

        XCTAssertEqual(expanded.count, 2)
        XCTAssertEqual(expanded[1], NSRange(location: 7, length: 13))
    }

    func testCodeFenceReturnExpansionDoesNotReenterReturnDelegate() {
        let parent = NoteTextView(text: .constant("```js"),
                                  ink: .black,
                                  bridge: EditorBridge(),
                                  autofocus: false,
                                  markdownEnabled: true)
        let coordinator = parent.makeCoordinator()
        let storage = NSTextStorage(string: "```js")
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 200))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200),
                                  textContainer: container)
        textView.delegate = coordinator
        coordinator.attach(to: textView)
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))

        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "```js\n")
    }

    func testListReturnExpansionAddsTheNextMarker() {
        for (source, expected) in [("- item", "- item\n- "),
                                   ("1. item", "1. item\n2. "),
                                   ("-", "-\n- "),
                                   ("1.", "1.\n2. ")] {
            let parent = NoteTextView(text: .constant(source),
                                      ink: .black,
                                      bridge: EditorBridge(),
                                      autofocus: false,
                                      markdownEnabled: true)
            let coordinator = parent.makeCoordinator()
            let storage = NSTextStorage(string: source)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 500, height: 200))
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200),
                                      textContainer: container)
            textView.delegate = coordinator
            coordinator.attach(to: textView)
            textView.setSelectedRange(NSRange(location: storage.length, length: 0))

            textView.insertNewline(nil)
            XCTAssertEqual(textView.string, expected)
        }
    }

    func testEditorStylesKeepListMarkersAndDecorateQuotes() {
        let source = "- bullet\n1. ordered\n>> quote"
        let storage = NSTextStorage(string: source)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 200))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200),
                                  textContainer: container)

        EditorStyleEngine.apply(to: textView,
                                ranges: [NSRange(location: 0, length: storage.length)],
                                revealing: nil,
                                ink: .black,
                                size: 13,
                                markdownEnabled: true,
                                bodyFont: { NSFont.systemFont(ofSize: $0) })

        let orderedStart = (source as NSString).range(of: "1.").location
        let quoteStart = (source as NSString).range(of: ">>").location
        XCTAssertNil(storage.attribute(.notesHidden, at: 0, effectiveRange: nil))
        XCTAssertNil(storage.attribute(.notesHidden, at: orderedStart, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.notesHidden, at: quoteStart, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.quoteDecoration, at: quoteStart, effectiveRange: nil))
    }

    func testEditorStylesDrawFrontMatterAndDividerDecorations() {
        let source = "---\ntitle: Demo\n---\n----"
        let storage = NSTextStorage(string: source)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 200))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200),
                                  textContainer: container)

        EditorStyleEngine.apply(to: textView,
                                ranges: [NSRange(location: 0, length: storage.length)],
                                revealing: nil,
                                ink: .black,
                                size: 13,
                                markdownEnabled: true,
                                bodyFont: { NSFont.systemFont(ofSize: $0) })

        let dividerStart = (source as NSString).range(of: "----").location
        let titleStart = (source as NSString).range(of: "title").location
        XCTAssertNotNil(storage.attribute(.frontMatterDecoration, at: 0, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.frontMatterDecoration, at: titleStart, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.dividerDecoration, at: dividerStart, effectiveRange: nil))
        let divider = storage.attribute(.dividerDecoration,
                                        at: dividerStart,
                                        effectiveRange: nil) as? DividerDecoration
        XCTAssertEqual(divider?.thickness, 1)
        XCTAssertNotNil(storage.attribute(.notesHidden, at: 0, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.notesHidden, at: dividerStart, effectiveRange: nil))
    }

    func testEditorStylesDoNotParseMarkdownInsideCode() {
        let source = "```swift\n**not bold**\n```\n**real bold**"
        let storage = NSTextStorage(string: source)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 200))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200),
                                  textContainer: container)

        EditorStyleEngine.apply(to: textView,
                                ranges: [NSRange(location: 0, length: storage.length)],
                                revealing: nil,
                                ink: .black,
                                size: 13,
                                markdownEnabled: true,
                                bodyFont: { NSFont.systemFont(ofSize: $0) })

        let codeStart = (source as NSString).range(of: "**not bold**").location
        let realStart = (source as NSString).range(of: "**real bold**").location
        XCTAssertNotEqual(codeStart, NSNotFound)
        XCTAssertNotEqual(realStart, NSNotFound)
        XCTAssertNil(storage.attribute(.notesHidden, at: codeStart, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.codeBlockDecoration, at: codeStart, effectiveRange: nil))
        let codeParagraph = storage.attribute(.paragraphStyle,
                                               at: codeStart,
                                               effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(codeParagraph?.headIndent, 12)
        XCTAssertNotNil(storage.attribute(.notesHidden, at: realStart, effectiveRange: nil))
    }
}
