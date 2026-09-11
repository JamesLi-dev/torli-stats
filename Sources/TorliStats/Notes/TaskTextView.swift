import SwiftUI
import AppKit

// MARK: - NSTextView wrapper

/// Text view that treats a leading ☐ / ☑ as a real checkbox: clicking the box
/// toggles it, Return carries the list on, and finished lines get struck through.
final class TaskTextView: NSTextView {

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if toggleBox(at: point) { return }
        // ⌘-click follows a link. A plain click has to keep placing the caret —
        // the note is a thing you edit first and read second.
        if event.modifierFlags.contains(.command), openLink(at: point) { return }
        super.mouseDown(with: event)
    }

    /// Returns true when the click landed on a link and opened it.
    private func openLink(at point: NSPoint) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let index = min(characterIndexForInsertion(at: point), storage.length - 1)
        guard let value = storage.attribute(.link, at: index, effectiveRange: nil) else { return false }
        // The engine only ever stores a vetted URL here, but this is the point
        // where a note's own text would reach NSWorkspace, so it is checked again.
        let raw = (value as? URL)?.absoluteString ?? value as? String
        guard let raw, let url = EditorStyleEngine.openableURL(raw) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let lm = layoutManager, let tc = textContainer,
              let storage = textStorage else { return }
        let ns = storage.mutableString
        guard ns.length > 0, !visibleRect.isEmpty else { return }

        let origin = textContainerOrigin
        var containerVisible = visibleRect
        containerVisible.origin.x -= origin.x
        containerVisible.origin.y -= origin.y
        let visibleGlyphs = lm.glyphRange(forBoundingRect: containerVisible, in: tc)
        let visibleCharacters = lm.characterRange(forGlyphRange: visibleGlyphs,
                                                   actualGlyphRange: nil)
        let safeLocation = min(visibleCharacters.location, ns.length)
        let safeLength = min(visibleCharacters.length, ns.length - safeLocation)
        let lines = ns.lineRange(for: NSRange(location: safeLocation, length: safeLength))

        ns.enumerateSubstrings(in: lines,
                               options: .byLines) { sub, range, _, _ in
            guard let sub, Tasks.isTask(sub) else { return }
            let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1),
                                       actualCharacterRange: nil)
            var r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            r.origin.x += origin.x
            r.origin.y += origin.y
            self.addCursorRect(r.insetBy(dx: -3, dy: -2), cursor: .pointingHand)
        }
    }

    /// Returns true when the click landed on a checkbox and was consumed.
    private func toggleBox(at point: NSPoint) -> Bool {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return false }
        let ns = string as NSString
        guard ns.length > 0 else { return false }

        let index = min(characterIndexForInsertion(at: point), max(0, ns.length - 1))
        let line = ns.lineRange(for: NSRange(location: index, length: 0))
        guard line.length > 0 else { return false }
        let first = ns.character(at: line.location)
        guard first == Tasks.open.unicodeScalars.first!.value ||
              first == Tasks.done.unicodeScalars.first!.value else { return false }

        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: line.location, length: 1),
                                   actualCharacterRange: nil)
        var box = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        box.origin.x += textContainerOrigin.x
        box.origin.y += textContainerOrigin.y
        guard box.insetBy(dx: -4, dy: -3).contains(point) else { return false }

        let target = NSRange(location: line.location, length: 1)
        let flipped = String(first == Tasks.open.unicodeScalars.first!.value ? Tasks.done : Tasks.open)
        guard shouldChangeText(in: target, replacementString: flipped) else { return true }
        storage.replaceCharacters(in: target, with: flipped)
        didChangeText()
        return true
    }
}
