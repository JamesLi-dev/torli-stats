import AppKit
import XCTest
@testable import TorliStats

final class StatusBarTextLayoutTests: XCTestCase {
    func testColumnOriginsMatchWithLocalizedTypingAndAllFontSizes() {
        for size: CGFloat in [8, 9, 10] {
            for label in ["输入", "Typing"] {
                for count in ["99", "6.2K", "100.0K"] {
                    assertAligned(top: [label, "TOR  BAB", "CPU  12%", "↑ 147.5 KB/s"],
                                  bottom: [count, "88%  89%", "MEM  69%", "↓  17.8 MB/s"], size: size)
                }
            }
        }
    }

    func testHiddenTypingAndOneSidedMetricsKeepTheirColumns() {
        assertAligned(top: ["TOR", "CPU  12%", ""], bottom: ["100%", "", "↓  17.8 KB/s"], size: 9)
    }

    private func assertAligned(top: [String], bottom: [String], size: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = size + 1
        style.maximumLineHeight = size + 1
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
            .paragraphStyle: style,
            .baselineOffset: -max(0, size - 5)
        ]
        let title = StatusBarTextLayout.title(
            top: top.map { NSAttributedString(string: $0, attributes: attributes) },
            bottom: bottom.map { NSAttributedString(string: $0, attributes: attributes) },
            attributes: attributes, gap: 8, leadingInset: 8
        )
        let storage = NSTextStorage(attributedString: title)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 2000, height: 100))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        XCTAssertFalse(title.string.contains("\t"), file: file, line: line)
        let rows = title.string.components(separatedBy: "\n")
        XCTAssertEqual(rows.count, 2, file: file, line: line)
        XCTAssertLessThan(title.size().width, 500, "Status item must not expand or wrap due to tab stops", file: file, line: line)
        XCTAssertLessThan(title.size().height, 40, file: file, line: line)
        var upperSearch = 0
        var lowerSearch = 0
        for index in top.indices {
            if !top[index].isEmpty, !bottom[index].isEmpty {
                let upperRow = rows[0] as NSString
                let lowerRow = rows[1] as NSString
                let upperRange = upperRow.range(of: top[index], range: NSRange(location: upperSearch, length: upperRow.length - upperSearch))
                let lowerRange = lowerRow.range(of: bottom[index], range: NSRange(location: lowerSearch, length: lowerRow.length - lowerSearch))
                let upper = layout.glyphIndexForCharacter(at: upperRange.location)
                let lower = layout.glyphIndexForCharacter(at: lowerRange.location + upperRow.length + 1)
                let upperX = layout.lineFragmentRect(forGlyphAt: upper, effectiveRange: nil).minX + layout.location(forGlyphAt: upper).x
                let lowerX = layout.lineFragmentRect(forGlyphAt: lower, effectiveRange: nil).minX + layout.location(forGlyphAt: lower).x
                XCTAssertEqual(upperX, lowerX, accuracy: 0.01, "Column \(index), \(top), \(bottom), font \(size)", file: file, line: line)
                upperSearch = NSMaxRange(upperRange)
                lowerSearch = NSMaxRange(lowerRange)
            }
        }
    }
}
