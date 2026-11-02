import SwiftUI
import AppKit

// MARK: - Bridge to the underlying NSTextView (used for ⌘F)

final class EditorBridge: ObservableObject {
    weak var textView: NSTextView?
    @Published var matchCount = 0

    func recount(_ q: String) {
        guard let tv = textView, !q.isEmpty else { matchCount = 0; return }
        let ns = tv.string as NSString
        var count = 0, loc = 0
        while loc < ns.length {
            let r = ns.range(of: q, options: [.caseInsensitive],
                             range: NSRange(location: loc, length: ns.length - loc))
            if r.location == NSNotFound { break }
            count += 1
            loc = r.location + max(1, r.length)
        }
        matchCount = count
    }

    func findNext(_ q: String, forward: Bool = true) {
        guard let tv = textView, !q.isEmpty else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        var found: NSRange

        if forward {
            let start = min(ns.length, NSMaxRange(sel))
            found = ns.range(of: q, options: [.caseInsensitive],
                             range: NSRange(location: start, length: ns.length - start))
            if found.location == NSNotFound {
                found = ns.range(of: q, options: [.caseInsensitive])   // wrap
            }
        } else {
            found = ns.range(of: q, options: [.caseInsensitive, .backwards],
                             range: NSRange(location: 0, length: sel.location))
            if found.location == NSNotFound {
                found = ns.range(of: q, options: [.caseInsensitive, .backwards])
            }
        }
        guard found.location != NSNotFound else { return }
        tv.setSelectedRange(found)
        tv.scrollRangeToVisible(found)
        tv.showFindIndicator(for: found)
    }

    /// Turn the caret's line into a task, or strip the checkbox back off it.
    func toggleTaskLine() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = tv.string as NSString
        let caret = min(tv.selectedRange().location, ns.length)
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        let text = ns.substring(with: line)

        guard !tv.hasMarkedText() else { return }
        let target: NSRange
        let replacement: String
        if let task = TaskLine.parse(text) {
            let local = task.completed ? task.prefixRange : task.markerRange
            target = NSRange(location: line.location + local.location, length: local.length)
            replacement = task.completed ? "" : task.marker(toggled: true)
        } else {
            let indentation = (text as NSString).range(of: "^[ \t]*", options: .regularExpression).length
            target = NSRange(location: line.location + indentation, length: 0)
            replacement = Tasks.openPrefix
        }
        let selection = tv.selectedRange()
        guard tv.shouldChangeText(in: target, replacementString: replacement) else { return }
        storage.replaceCharacters(in: target, with: replacement)
        func mapped(_ position: Int) -> Int {
            if position < target.location { return position }
            if position <= NSMaxRange(target) { return target.location + (replacement as NSString).length }
            return position + (replacement as NSString).length - target.length
        }
        let start = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        tv.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        tv.didChangeText()
    }

    func focusText() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }
}

/// Collapses glyphs carrying `.notesHidden` to nothing. This is the only way to
/// hide characters without deleting them: colouring them clear still leaves
/// their width behind, and the caret still walks through them.
final class HidingLayoutManager: NSLayoutManager {
    /// Shared drawing/hit-test geometry; a checkbox reserves paragraph space,
    /// not a font-dependent Unicode glyph advance.
    func checkboxRect(at character: Int) -> NSRect? {
        guard let storage = textStorage, character < storage.length,
              storage.attribute(.notesCheckbox, at: character, effectiveRange: nil) != nil else { return nil }
        let source = storage.string as NSString
        let range = source.lineRange(for: NSRange(location: character, length: 0))
        guard let task = TaskLine.parse(source.substring(with: range)) else { return nil }
        let bodyLocation = range.location + (task.body.isEmpty ? task.markerRange.location : task.bodyRange.location)
        let glyph = glyphIndexForCharacter(at: min(bodyLocation, storage.length - 1))
        guard let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return nil }
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let font = storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
        let paragraph = storage.attribute(.paragraphStyle, at: character, effectiveRange: nil) as? NSParagraphStyle
        let side = max(9, font.pointSize - 3)
        return NSRect(x: line.minX + container.lineFragmentPadding + (paragraph?.firstLineHeadIndent ?? 0) - (task.body.isEmpty ? 0 : side + 6),
                      y: line.midY - side / 2, width: side, height: side)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttributes(in: characters) { attrs, range, _ in
            guard attrs[.notesCheckbox] != nil || attrs[.notesRule] != nil else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            guard let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return }
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let ink = (attrs[.notesInk] as? NSColor) ?? .textColor
            if attrs[.notesRule] != nil {
                ink.withAlphaComponent(0.3).setFill()
                NSRect(x: origin.x + line.minX + container.lineFragmentPadding,
                       y: origin.y + line.midY,
                       width: max(0, line.width - 2 * container.lineFragmentPadding), height: 1).fill()
            } else {
                guard let local = checkboxRect(at: range.location) else { return }
                let rect = local.offsetBy(dx: origin.x, dy: origin.y)
                let side = rect.width
                let done = attrs[.notesCheckbox] as? Bool ?? false
                let box = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
                ink.withAlphaComponent(done ? 0.45 : 0.75).setStroke()
                box.lineWidth = 1.2
                box.stroke()
                if done {
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: rect.minX + side * 0.2, y: rect.midY))
                    check.line(to: NSPoint(x: rect.minX + side * 0.43, y: rect.minY + side * 0.72))
                    check.line(to: NSPoint(x: rect.minX + side * 0.82, y: rect.minY + side * 0.25))
                    check.lineWidth = 1.5
                    check.stroke()
                }
            }
        }
    }

    override func setGlyphs(_ glyphs: UnsafePointer<CGGlyph>,
                            properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                            characterIndexes charIndexes: UnsafePointer<Int>,
                            font aFont: NSFont,
                            forGlyphRange glyphRange: NSRange) {
        guard let storage = textStorage else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }
        var edited = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        for i in 0..<glyphRange.length {
            let ci = charIndexes[i]
            guard ci < storage.length else { continue }
            if storage.attribute(.notesHidden, at: ci, effectiveRange: nil) != nil {
                edited[i] = .null
                changed = true
            }
        }
        guard changed else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }
        edited.withUnsafeBufferPointer { buf in
            super.setGlyphs(glyphs, properties: buf.baseAddress!, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
        }
    }
}
