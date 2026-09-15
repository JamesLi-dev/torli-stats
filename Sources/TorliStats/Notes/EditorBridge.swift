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
        if let block = MarkdownBlockParser.block(containing: line.location, in: tv.string),
           block.kind.isCode {
            return
        }

        if let task = TaskLine.parse(text) {
            let range = NSRange(location: line.location + task.taskPrefixRange.location,
                                 length: task.taskPrefixRange.length)
            guard tv.shouldChangeText(in: range, replacementString: "") else { return }
            storage.replaceCharacters(in: range, with: "")
        } else {
            let indentation = TaskLine.leadingIndentationRange(in: text)
            let range = NSRange(location: line.location + indentation.length, length: 0)
            guard tv.shouldChangeText(in: range, replacementString: Tasks.openPrefix) else { return }
            storage.replaceCharacters(in: range, with: Tasks.openPrefix)
        }
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

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0 else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        enumerateLineFragments(forGlyphRange: glyphsToShow) { lineRect, usedRect, _, lineGlyphRange, _ in
            guard lineGlyphRange.length > 0 else { return }
            let characters = self.characterRange(forGlyphRange: lineGlyphRange,
                                                 actualGlyphRange: nil)
            guard characters.location != NSNotFound,
                  characters.location < storage.length else { return }

            if let decoration = storage.attribute(.quoteDecoration,
                                                  at: characters.location,
                                                  effectiveRange: nil) as? QuoteDecoration {
                var background = lineRect
                background.origin.x += origin.x
                background.origin.y += origin.y
                decoration.fill.setFill()
                background.fill()

                let contentStart = max(lineRect.minX, usedRect.minX)
                let barX = max(lineRect.minX + 2,
                               contentStart - decoration.barGap - decoration.barWidth)
                let barHeight = max(0, lineRect.height - 2)
                let bar = NSRect(x: origin.x + barX,
                                 y: origin.y + lineRect.minY + 1,
                                 width: decoration.barWidth,
                                 height: barHeight)
                decoration.bar.setFill()
                NSBezierPath(roundedRect: bar,
                             xRadius: decoration.barRadius,
                             yRadius: decoration.barRadius).fill()
            } else if let decoration = storage.attribute(.frontMatterDecoration,
                                                         at: characters.location,
                                                         effectiveRange: nil) as? FrontMatterDecoration {
                var background = lineRect
                background.origin.x += origin.x
                background.origin.y += origin.y
                decoration.fill.setFill()
                background.fill()

                if decoration.placeholder {
                    let hint = NSAttributedString(
                        string: "input YAML Front Matter.",
                        attributes: [.font: decoration.font,
                                     .foregroundColor: decoration.text])
                    let textHeight = decoration.font.ascender - decoration.font.descender
                    let baseline = origin.y + lineRect.minY +
                        max(0, (lineRect.height - textHeight) / 2) + decoration.font.ascender
                    hint.draw(at: NSPoint(x: origin.x + lineRect.minX + 28,
                                          y: baseline - decoration.font.ascender))
                }
            } else if let decoration = storage.attribute(.codeBlockDecoration,
                                                         at: characters.location,
                                                         effectiveRange: nil) as? CodeBlockDecoration {
                var background = lineRect
                background.origin.x += origin.x
                background.origin.y += origin.y
                decoration.fill.setFill()
                background.fill()
            } else if let decoration = storage.attribute(.dividerDecoration,
                                                         at: characters.location,
                                                         effectiveRange: nil) as? DividerDecoration {
                let line = NSRect(x: origin.x + lineRect.minX + 4,
                                  y: origin.y + lineRect.midY - decoration.thickness / 2,
                                  width: max(0, lineRect.width - 8),
                                  height: decoration.thickness)
                decoration.color.setFill()
                line.fill()
            }
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, glyphsToShow.length > 0 else { return }

        let characters = characterRange(forGlyphRange: glyphsToShow,
                                        actualGlyphRange: nil)
        storage.enumerateAttribute(.taskCheckbox, in: characters, options: []) { value, range, _ in
            guard let style = value as? TaskCheckboxStyle else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.location != NSNotFound,
                  let container = textContainer(forGlyphAt: glyphs.location,
                                                 effectiveRange: nil) else { return }
            var frame = boundingRect(forGlyphRange: glyphs, in: container)
            frame.origin.x += origin.x
            frame.origin.y += origin.y
            TaskCheckboxRenderer.draw(style,
                                      in: frame,
                                      isFlipped: container.textView?.isFlipped ?? false)
        }
    }
}
