import SwiftUI
import AppKit

// MARK: - NSTextView wrapper

/// Text view that treats an indented or unindented ☐ / ☑ as a real checkbox:
/// clicking the box toggles it, Return carries the list on, and finished lines
/// get struck through.
final class TaskTextView: NSTextView {
    private var checkboxCursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let area = checkboxCursorTrackingArea {
            removeTrackingArea(area)
        }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        checkboxCursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if checkboxHit(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

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
        let source = storage.string
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
            guard let sub, let task = TaskLine.parse(String(sub)),
                  let block = MarkdownBlockParser.block(containing: range.location,
                                                        in: source),
                  !block.kind.isCode else { return }
            let checkbox = NSRange(location: range.location + task.checkboxRange.location,
                                   length: task.checkboxRange.length)
            let glyphs = lm.glyphRange(forCharacterRange: checkbox,
                                       actualCharacterRange: nil)
            var r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            r.origin.x += origin.x
            r.origin.y += origin.y
            self.addCursorRect(
                r.insetBy(dx: -TaskCheckboxRenderer.clickPadding.left,
                          dy: -TaskCheckboxRenderer.clickPadding.top),
                cursor: .pointingHand)
        }
    }

    private func checkboxHit(at point: NSPoint) -> (range: NSRange, frame: NSRect, isCompleted: Bool)? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else {
            return nil
        }
        let ns = storage.mutableString
        guard ns.length > 0 else { return nil }
        let source = storage.string

        let index = min(characterIndexForInsertion(at: point), max(0, ns.length - 1))
        let line = ns.lineRange(for: NSRange(location: index, length: 0))
        guard line.length > 0 else { return nil }
        let lineText = ns.substring(with: line)
        guard let task = TaskLine.parse(lineText),
              let block = MarkdownBlockParser.block(containing: line.location, in: source),
              !block.kind.isCode else { return nil }

        let target = NSRange(location: line.location + task.checkboxRange.location,
                             length: task.checkboxRange.length)
        let glyphs = lm.glyphRange(forCharacterRange: target,
                                   actualCharacterRange: nil)
        var frame = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        frame.origin.x += textContainerOrigin.x
        frame.origin.y += textContainerOrigin.y
        let hitFrame = frame.insetBy(dx: -TaskCheckboxRenderer.clickPadding.left,
                                     dy: -TaskCheckboxRenderer.clickPadding.top)
        guard hitFrame.contains(point) else { return nil }
        return (target, frame, task.isCompleted)
    }

    /// Returns true when the click landed on a checkbox and was consumed.
    private func toggleBox(at point: NSPoint) -> Bool {
        guard let storage = textStorage, let hit = checkboxHit(at: point) else { return false }
        let flipped = hit.isCompleted ? String(Tasks.open) : String(Tasks.done)
        guard shouldChangeText(in: hit.range, replacementString: flipped) else { return true }
        storage.replaceCharacters(in: hit.range, with: flipped)
        didChangeText()
        return true
    }
}
