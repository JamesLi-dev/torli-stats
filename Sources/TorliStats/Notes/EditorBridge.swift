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

        if Tasks.isTask(text) {
            var length = 1
            if line.length > 1, ns.character(at: line.location + 1) == 32 { length = 2 }
            let range = NSRange(location: line.location, length: length)
            guard tv.shouldChangeText(in: range, replacementString: "") else { return }
            storage.replaceCharacters(in: range, with: "")
        } else {
            let range = NSRange(location: line.location, length: 0)
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
}
