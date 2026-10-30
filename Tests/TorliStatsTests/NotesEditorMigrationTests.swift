import AppKit
import XCTest
@testable import TorliStats

final class NotesEditorMigrationTests: XCTestCase {
    private var windows: [NSWindow] = []
    private func editor(_ text: String, caret: Int? = nil) -> TaskTextView {
        _ = NSApplication.shared
        let storage = NSTextStorage()
        let layout = HidingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let view = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        windows.append(window)
        view.isRichText = false
        view.allowsUndo = true
        view.string = text
        view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        return view
    }

    func testBulletAndNumberedContinuation() {
        for (input, expected) in [("- 中文", "- 中文\n- "), ("  * item", "  * item\n  * "),
                                  ("1. item", "1. item\n2. "), ("2.3. item", "2.3. item\n2.4. ")] {
            let view = editor(input)
            view.insertNewline(nil)
            XCTAssertEqual(view.string, expected)
        }
    }

    func testTaskContinuationKeepsIndentationAndResetsCompletion() {
        let view = editor("  ☑ 完成😀")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "  ☑ 完成😀\n  ☐ ")
    }

    func testEmptyListExitPreservesFollowingLine() {
        for marker in ["- ", "☐ ", "1. "] {
            let view = editor(marker + "\r\n下一行", caret: (marker as NSString).length)
            view.insertNewline(nil)
            XCTAssertEqual(view.string, "\r\n下一行")
        }
    }

    func testIndentAndOutdentPreserveNewlineAndUnicode() {
        let view = editor("- 😀中文\nnext", caret: 4)
        view.insertTab(nil)
        XCTAssertEqual(view.string, "  - 😀中文\nnext")
        view.insertBacktab(nil)
        XCTAssertEqual(view.string, "- 😀中文\nnext")
        let tabbed = editor("\t☐ task\nnext", caret: 4)
        tabbed.insertBacktab(nil)
        XCTAssertEqual(tabbed.string, "☐ task\nnext")
    }

    func testNumberedIndentationAndOverflow() {
        let view = editor("1. 中文\nnext", caret: 5)
        view.insertTab(nil)
        XCTAssertEqual(view.string, "1.1. 中文\nnext")
        view.insertBacktab(nil)
        XCTAssertEqual(view.string, "1. 中文\nnext")
        let large = editor("\(Int.max). item")
        large.insertNewline(nil)
        XCTAssertEqual(large.string, "\(Int.max). item\n\(Int.max). ")
    }

    func testTaskTogglePreservesIndentAndCyclesStates() {
        let view = editor("  文本\nnext", caret: 3)
        let bridge = EditorBridge()
        bridge.textView = view
        bridge.toggleTaskLine()
        XCTAssertEqual(view.string, "  ☐ 文本\nnext")
        bridge.toggleTaskLine()
        XCTAssertEqual(view.string, "  ☑ 文本\nnext")
        bridge.toggleTaskLine()
        XCTAssertEqual(view.string, "  文本\nnext")
    }

    func testListEditCanBeUndone() {
        let view = editor("- item")
        XCTAssertNotNil(view.undoManager)
        view.undoManager?.beginUndoGrouping()
        view.insertNewline(nil)
        view.undoManager?.endUndoGrouping()
        XCTAssertEqual(view.string, "- item\n- ")
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "- item")
    }

    func testUprightAndMixedLabelRuns() {
        let runs = VerticalLabelLayout.runs(for: "项目API😀")
        XCTAssertEqual(runs.map(\.text), ["项", "目", "API", "😀"])
        XCTAssertEqual(runs.map(\.orientation), [.upright, .upright, .rotated, .upright])
        XCTAssertEqual(VerticalLabelLayout.runs(for: "TODO 123").count, 1)
        let family = VerticalLabelLayout.runs(for: "👨‍👩‍👧‍👦")
        XCTAssertEqual(family.count, 1)
        XCTAssertEqual(family.first?.orientation, .upright)
    }

    func testLabelTruncationRespectsAvailableHeight() {
        let limit = DeckGeom.tabGlyphAdvance * 3
        let runs = VerticalLabelLayout.fittingRuns(for: "中文长标题测试", maxAdvance: limit)
        XCTAssertEqual(runs.last?.text, "…")
        XCTAssertLessThanOrEqual(runs.reduce(0) { $0 + $1.advance }, limit)
        XCTAssertEqual(runs.dropLast().map(\.text).joined(), "中文")
    }

    func testSpacePreferenceChangesDeckBehavior() {
        let old = NotesSettings.confineToSpace
        defer { NotesSettings.confineToSpace = old }
        let panel = DeckPanel()
        NotesSettings.confineToSpace = true
        panel.applyLevel()
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        NotesSettings.confineToSpace = false
        panel.applyLevel()
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }
}
