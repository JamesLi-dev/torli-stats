import AppKit

/// Metadata used by the layout manager to draw a Todo marker in place of its
/// source glyph. Keeping this as an attribute leaves the stored note body plain
/// text and keeps the original checkbox character available to the editor.
final class TaskCheckboxStyle: NSObject, NSCopying {
    let isCompleted: Bool
    let ink: NSColor

    init(isCompleted: Bool, ink: NSColor) {
        self.isCompleted = isCompleted
        self.ink = ink
    }

    func copy(with zone: NSZone? = nil) -> Any {
        self
    }
}

enum TaskCheckboxRenderer {
    static let visualSize: CGFloat = 12
    static let clickPadding = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)

    static func draw(_ style: TaskCheckboxStyle, in frame: NSRect, isFlipped: Bool) {
        // The marker's advance is normally wide enough for this size. Use the
        // line height as the safety bound so the completed check does not
        // collapse into a tiny glyph on fonts with a narrow checkbox advance.
        let side = min(visualSize, max(1, frame.height - 2))
        let box = NSRect(x: frame.midX - side / 2,
                         y: frame.midY - side / 2,
                         width: side,
                         height: side)
        let path = NSBezierPath(roundedRect: box,
                                xRadius: min(2.5, side / 4),
                                yRadius: min(2.5, side / 4))
        path.lineWidth = min(1.35, side / 4)

        if style.isCompleted {
            style.ink.withAlphaComponent(0.88).setFill()
            path.fill()
            style.ink.withAlphaComponent(0.98).setStroke()
            path.stroke()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let check = NSBezierPath()
            let lowerY = isFlipped ? box.maxY - side * 0.25 : box.minY + side * 0.25
            let upperY = isFlipped ? box.minY + side * 0.22 : box.maxY - side * 0.22
            check.move(to: NSPoint(x: box.minX + side * 0.22, y: box.midY))
            check.line(to: NSPoint(x: box.minX + side * 0.42, y: lowerY))
            check.line(to: NSPoint(x: box.maxX - side * 0.18, y: upperY))
            check.lineWidth = min(1.65, side / 3.5)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        } else {
            style.ink.withAlphaComponent(0.78).setStroke()
            path.stroke()
        }
    }

    /// Measure the indentation needed by wrapped lines of a task. The first
    /// line still contains the source indentation and marker; subsequent lines
    /// start at the task body (a hanging indent).
    static func bodyHeadIndent(for task: TaskLine, line: String, font: NSFont) -> CGFloat {
        let indentation = displayWhitespace(task.indentation(in: line))
        let separator = displayWhitespace(task.separator(in: line))
        let marker = String(task.marker)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let indentationWidth = (indentation as NSString).size(withAttributes: attributes).width
        let markerWidth = (marker as NSString).size(withAttributes: attributes).width
        let separatorWidth = (separator as NSString).size(withAttributes: attributes).width
        return indentationWidth + markerWidth + separatorWidth
    }

    private static func displayWhitespace(_ value: String) -> String {
        value.map { $0 == "\t" ? "    " : " " }.reduce(into: "") { result, value in
            result.append(value)
        }
    }
}
