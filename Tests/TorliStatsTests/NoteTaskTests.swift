import XCTest
import AppKit
@testable import TorliStats

final class NoteTaskTests: XCTestCase {
    func testTaskLineParsesIndentationCheckboxAndBodyRanges() {
        let line = "\t  ☑   中文 task"
        let task = TaskLine.parse(line)

        XCTAssertNotNil(task)
        XCTAssertEqual(task?.state, .completed)
        XCTAssertEqual(task?.indentationRange, NSRange(location: 0, length: 3))
        XCTAssertEqual(task?.checkboxRange, NSRange(location: 3, length: 1))
        XCTAssertEqual(task?.separatorRange, NSRange(location: 4, length: 3))
        XCTAssertEqual(task?.bodyRange, NSRange(location: 7, length: 7))
        XCTAssertEqual(task?.indentation(in: line), "\t  ")
        XCTAssertEqual(task?.body(in: line), "中文 task")
        XCTAssertEqual(task?.taskPrefixRange, NSRange(location: 3, length: 4))
    }

    func testTaskLineAcceptsLineEndingsAndRejectsNonTasks() {
        let task = TaskLine.parse("  ☐ task\r\n")
        XCTAssertEqual(task?.body(in: "  ☐ task\r\n"), "task")
        XCTAssertTrue(task?.isEmpty == false)

        XCTAssertNil(TaskLine.parse("  text ☐ task"))
        XCTAssertNil(TaskLine.parse("- [ ] markdown task"))
    }

    func testMarkdownTasksImportWithMultipleAndNestedLines() {
        let markdown = "- [ ] one\n  * [x]\t中文\nplain - [ ] text\n- [ ]\n- [X] done\r\n"
        let expected = "☐ one\n  ☑ 中文\nplain - [ ] text\n☐ \n☑ done\r\n"

        XCTAssertEqual(Tasks.fromMarkdown(markdown), expected)
    }

    func testMarkdownExportOnlyConvertsTaskPrefixes() {
        let source = "ordinary ☐ text\n  ☐ task\n☑ done\n"
        let expected = "ordinary ☐ text\n  - [ ] task\n- [x] done\n"

        XCTAssertEqual(Tasks.toMarkdown(source), expected)
    }

    func testMarkdownTaskConversionIsStableForInternalPlainText() {
        let source = "☐ one\n  ☑ two\nparagraph\n\t☐ 中文\n"
        XCTAssertEqual(Tasks.fromMarkdown(Tasks.toMarkdown(source)), source)
    }

    func testTaskConsumersUseIndentedTasks() {
        var note = Note()
        note.body = "  ☐ open\n\t☑ done\nnormal line"

        XCTAssertEqual(note.taskProgress?.done, 1)
        XCTAssertEqual(note.taskProgress?.total, 2)
        XCTAssertEqual(Note.derivedTitle(from: "\t☑ first task"), "first task")

        note.title = "Custom title"
        XCTAssertEqual(note.preview, "open done normal line")

        note.body = "```\n☑ not a task\n```\n  ☑ real task"
        XCTAssertEqual(note.taskProgress?.done, 1)
        XCTAssertEqual(note.taskProgress?.total, 1)
    }

    func testCompletedTaskStylingTargetsBodyNotCheckbox() {
        let source = "  ☑ done"
        let storage = NSTextStorage(string: source)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 100))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 100),
                                  textContainer: container)

        EditorStyleEngine.apply(to: textView,
                                ranges: [NSRange(location: 0, length: storage.length)],
                                revealing: nil,
                                ink: .black,
                                size: 13,
                                markdownEnabled: false,
                                bodyFont: { NSFont.systemFont(ofSize: $0) })

        let checkbox = storage.attribute(.taskCheckbox, at: 2, effectiveRange: nil) as? TaskCheckboxStyle
        XCTAssertEqual(checkbox?.isCompleted, true)
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil))
        XCTAssertEqual(
            (storage.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? NSNumber)?.intValue,
            NSUnderlineStyle.single.rawValue
        )
        let paragraph = storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(paragraph)
        XCTAssertGreaterThan(paragraph?.headIndent ?? 0, TaskCheckboxRenderer.visualSize)
    }
}
