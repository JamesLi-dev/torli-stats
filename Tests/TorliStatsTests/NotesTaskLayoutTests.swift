import AppKit
import XCTest
@testable import TorliStats

final class NotesTaskLayoutTests: XCTestCase {
    private func editor(_ text: String, markdown: Bool = true, active: NSRange? = nil) -> TaskTextView {
        _ = NSApplication.shared
        let storage = NSTextStorage(string: text)
        let layout = HidingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 340, height: 1000))
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        let view = TaskTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 400), textContainer: container)
        view.backgroundColor = NSColor(calibratedRed: 1, green: 0.96, blue: 0.78, alpha: 1)
        view.allowsUndo = true
        style(view, markdown: markdown, active: active)
        return view
    }

    private func style(_ view: NSTextView, markdown: Bool = true, active: NSRange? = nil) {
        EditorStyleEngine.apply(to: view, ranges: [NSRange(location: 0, length: (view.string as NSString).length)],
            revealing: active, ink: .black, size: 15, markdownEnabled: markdown,
            bodyFont: { NSFont.systemFont(ofSize: $0) }, isCompletedTask: { Tasks.marker(of: $0) == Tasks.done })
    }

    func testTaskRecognitionAcrossConsumersAndEmptyMarkdownTasks() throws {
        let source = "\t+ [X] 中文 👩‍💻\r\n  - [ ]\r\n☐\ntext ☐ remains"
        let note = Note(body: source)
        XCTAssertEqual(note.taskProgress?.done, 1)
        XCTAssertEqual(note.taskProgress?.total, 3)
        XCTAssertEqual(Note.derivedTitle(from: source), "中文 👩‍💻")
        let task = try XCTUnwrap(TaskLine.parse("\t+ [X] 中文 👩‍💻"))
        XCTAssertEqual(task.indentationColumns, 4)
        XCTAssertEqual(task.body, "中文 👩‍💻")
        XCTAssertNil(TaskLine.parse("- [x]word"))
        let imported = Tasks.fromMarkdown(source)
        XCTAssertEqual(imported, "\t☑ 中文 👩‍💻\r\n  ☐ \r\n☐ \ntext ☐ remains")
        XCTAssertEqual(Tasks.fromMarkdown(Tasks.toMarkdown(imported)), imported)
    }

    func testToggleAndReturnUseSameMarkdownTaskRules() {
        let view = editor("  * [ ] 中文😀")
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        let bridge = EditorBridge(); bridge.textView = view
        bridge.toggleTaskLine()
        XCTAssertEqual(view.string, "  - [x] 中文😀")
        XCTAssertEqual(view.selectedRange().location, (view.string as NSString).length)
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "  - [x] 中文😀\n  - [ ] ")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "  - [x] 中文😀\n  ")
        view.setSelectedRange(NSRange(location: 9, length: 0))
        bridge.toggleTaskLine()
        XCTAssertEqual(view.string, "  中文😀\n  ")
    }

    func testCompletedBodyOnlyAndWrappedIndentWithMarkdownDisabled() throws {
        let text = "\t☑ 中文 task with enough words to wrap onto another line without shifting back under the checkbox"
        let view = editor(text, markdown: false)
        let storage = try XCTUnwrap(view.textStorage)
        let task = try XCTUnwrap(TaskLine.parse(text))
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: task.markerRange.location, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.strikethroughStyle, at: task.bodyRange.location, effectiveRange: nil))
        XCTAssertEqual(storage.attribute(.notesCheckbox, at: task.markerRange.location, effectiveRange: nil) as? Bool, true)
        let paragraph = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertGreaterThan(paragraph.headIndent, 20)
        XCTAssertEqual(paragraph.headIndent, paragraph.firstLineHeadIndent)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let lastGlyph = view.layoutManager!.glyphIndexForCharacter(at: storage.length - 1)
        let lastRect = view.layoutManager!.lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
        XCTAssertGreaterThan(lastRect.minY, 0)
        XCTAssertGreaterThanOrEqual(lastRect.minX, paragraph.headIndent)
    }

    func testCheckboxMouseClickAndUndo() throws {
        let view = editor("  + [ ] 点击中文")
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let layout = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layout.ensureLayout(for: container)
        let marker = try XCTUnwrap(TaskLine.parse(view.string)).markerRange
        let box = try XCTUnwrap((layout as? HidingLayoutManager)?.checkboxRect(at: marker.location))
        let point = view.convert(NSPoint(x: box.midX + view.textContainerOrigin.x, y: box.midY + view.textContainerOrigin.y), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: event)
        XCTAssertEqual(view.string, "  - [x] 点击中文")
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "  + [ ] 点击中文")
    }

    func testRulesRecognizeRevealDisableAndClearAfterEditing() throws {
        for line in ["---", " *** ", "___", "- - -", "\t_ _ _"] { XCTAssertTrue(MarkdownRule.isRule(line)) }
        for line in ["--", "-*-", "text ---", "- item", "*** bold ***"] { XCTAssertFalse(MarkdownRule.isRule(line)) }
        let view = editor("---\nbody")
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertNotNil(storage.attribute(.notesRule, at: 0, effectiveRange: nil))
        style(view, active: NSRange(location: 0, length: 4))
        XCTAssertNil(storage.attribute(.notesRule, at: 0, effectiveRange: nil))
        style(view, markdown: false)
        XCTAssertNil(storage.attribute(.notesRule, at: 0, effectiveRange: nil))
        XCTAssertEqual(view.string, "---\nbody")
        storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "ordinary")
        style(view)
        XCTAssertNil(storage.attribute(.notesRule, at: 0, effectiveRange: nil))
        let spaced = editor("* * *")
        spaced.setSelectedRange(NSRange(location: 5, length: 0))
        spaced.insertNewline(nil)
        XCTAssertEqual(spaced.string, "* * *\n")
    }

    func testCheckboxUsesItsOwnLineAfterHiddenPrefix() throws {
        let view = editor("☐ First\n  ☑ Second\n\t- [ ] Third")
        let layout = try XCTUnwrap(view.layoutManager as? HidingLayoutManager)
        layout.ensureLayout(for: view.textContainer!)
        let source = view.string as NSString
        var previousY: CGFloat = -1
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byLines) { text, range, _, _ in
            guard let text, let task = TaskLine.parse(text), let box = layout.checkboxRect(at: range.location + task.markerRange.location) else {
                XCTFail("Missing checkbox"); return
            }
            let bodyGlyph = layout.glyphIndexForCharacter(at: range.location + task.bodyRange.location)
            let line = layout.lineFragmentRect(forGlyphAt: bodyGlyph, effectiveRange: nil)
            XCTAssertEqual(box.midY, line.midY, accuracy: 0.1)
            XCTAssertGreaterThan(box.midY, previousY)
            previousY = box.midY
        }
    }

    func testEmptyTaskAtEndKeepsOwnCheckboxLine() throws {
        for suffix in ["☐", "☐ ", "- [ ]", "- [ ] "] {
            let view = editor("☐ Previous\n" + suffix)
            let layout = try XCTUnwrap(view.layoutManager as? HidingLayoutManager)
            layout.ensureLayout(for: view.textContainer!)
            let first = try XCTUnwrap(layout.checkboxRect(at: 0))
            let last = try XCTUnwrap(layout.checkboxRect(at: ("☐ Previous\n" as NSString).length))
            XCTAssertGreaterThan(last.minY, first.maxY, suffix)
        }
    }

    func testRenderDecorations() throws {
        let view = editor("☐ 整理今天的任务\n  ☑ 已完成的任务，只有正文显示删除线\n\t- [ ] 多级任务：这是一条较长的内容，用于检查换行后文字能否保持对齐。\n\n---\n分割线下面的正文\n***\n___\n")
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["TORLI_NOTES_PREVIEW"] {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        XCTAssertEqual(view.string.components(separatedBy: "\n").count, 9)
    }
}
