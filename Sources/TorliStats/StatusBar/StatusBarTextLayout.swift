import AppKit
import CoreText

/// Native status buttons must receive bounded, tab-free lines. Their compact
/// cell layout does not honor the tab sizing used by a full text container.
enum StatusBarTextLayout {
    static func title(
        top: [NSAttributedString],
        bottom: [NSAttributedString],
        attributes: [NSAttributedString.Key: Any],
        gap: CGFloat,
        leadingInset: CGFloat
    ) -> NSAttributedString {
        guard !top.isEmpty, top.count == bottom.count else { return NSAttributedString() }
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        style.alignment = .left
        style.baseWritingDirection = .leftToRight
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        let rowAttributes = attributes.merging([.paragraphStyle: style, .kern: 0.0]) { _, new in new }
        let widths = top.indices.map { max(width(top[$0]), width(bottom[$0])) }
        let result = NSMutableAttributedString()
        for (rowIndex, row) in [top, bottom].enumerated() {
            if rowIndex > 0 { result.append(NSAttributedString(string: "\n", attributes: rowAttributes)) }
            result.append(spacer(leadingInset, attributes: rowAttributes))
            for (index, cell) in row.enumerated() {
                let normalized = NSMutableAttributedString(attributedString: cell)
                cell.enumerateAttribute(.kern, in: NSRange(location: 0, length: cell.length)) { value, range, _ in
                    if value == nil { normalized.addAttribute(.kern, value: 0.0, range: range) }
                }
                result.append(normalized)
                let padding = max(0, widths[index] - width(cell))
                result.append(spacer(padding + (index < row.count - 1 ? gap : 0), attributes: rowAttributes))
            }
        }
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func spacer(_ advance: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard advance > 0.01 else { return NSAttributedString() }
        let space = NSAttributedString(string: " ", attributes: attributes)
        return NSAttributedString(string: " ", attributes: attributes.merging([.kern: advance - width(space)]) { _, new in new })
    }

    private static func width(_ text: NSAttributedString) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil))
    }
}
