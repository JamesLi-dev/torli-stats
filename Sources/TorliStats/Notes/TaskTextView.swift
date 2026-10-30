import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class TaskTextView: NSTextView {

    /// Owns the image overlays and the line-height delegate for image tokens.
    /// Installed by NoteTextView.makeNSView; kept on the view so the editor
    /// coordinator can refresh it after every style pass.
    var imageOverlays: NoteImageOverlayManager?

    override func deleteBackward(_ sender: Any?) {
        // A range selection means the user deliberately selected content —
        // delete it straight away; the image-object path is for carets only.
        if selectedRange().length == 0, let token = hiddenImageTokenAtDeletionPoint() {
            deleteImageToken(token)
            return
        }
        super.deleteBackward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if handleListAutoContinuationOnNewline() { return }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if handleTabIndentation(shift: false) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if handleTabIndentation(shift: true) { return }
        super.insertBacktab(sender)
    }

    private func lineContentRange(for location: Int, in ns: NSString) -> (contentRange: NSRange, contentText: String) {
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        return (range, ns.substring(with: range))
    }

    private func handleListAutoContinuationOnNewline() -> Bool {
        guard let storage = textStorage else { return false }
        let ns = string as NSString
        let sel = selectedRange()
        guard !hasMarkedText(), sel.length == 0, sel.location <= ns.length else { return false }

        let (lineRange, lineText) = lineContentRange(for: sel.location, in: ns)

        // 1. Task checklist (☐ / ☑ or - [ ] / - [x])
        let taskPattern = try! NSRegularExpression(pattern: "^([ \\t]*)([\u{2610}\u{2611}]|- \\[([ xX])\\])[ \\t]*(.*)$")
        if let match = taskPattern.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) {
            let indent = (lineText as NSString).substring(with: match.range(at: 1))
            let bodyRange = match.range(at: 4)
            let body = (lineText as NSString).substring(with: bodyRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                // Empty item: pressing Enter clears the task marker and exits list
                let replacement = indent.isEmpty ? "" : indent
                if shouldChangeText(in: lineRange, replacementString: replacement) {
                    storage.replaceCharacters(in: lineRange, with: replacement)
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location + (replacement as NSString).length, length: 0))
                    return true
                }
            } else {
                // Continue new empty task item
                let nextPrefix = "\n\(indent)\(Tasks.openPrefix)"
                if shouldChangeText(in: sel, replacementString: nextPrefix) {
                    storage.replaceCharacters(in: sel, with: nextPrefix)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + (nextPrefix as NSString).length, length: 0))
                    return true
                }
            }
        }

        // 2. Unordered bullet list (- / * / +)
        let bulletPattern = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+])[ \\t]+(.*)$")
        if let match = bulletPattern.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) {
            let indent = (lineText as NSString).substring(with: match.range(at: 1))
            let bullet = (lineText as NSString).substring(with: match.range(at: 2))
            let body = (lineText as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                // Empty bullet item: exit list
                let replacement = indent.isEmpty ? "" : indent
                if shouldChangeText(in: lineRange, replacementString: replacement) {
                    storage.replaceCharacters(in: lineRange, with: replacement)
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location + (replacement as NSString).length, length: 0))
                    return true
                }
            } else {
                let nextPrefix = "\n\(indent)\(bullet) "
                if shouldChangeText(in: sel, replacementString: nextPrefix) {
                    storage.replaceCharacters(in: sel, with: nextPrefix)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + (nextPrefix as NSString).length, length: 0))
                    return true
                }
            }
        }

        // 3. Ordered / Hierarchical numbered list (e.g. 1. / 1.1 / 1.1.1.)
        let orderedPattern = try! NSRegularExpression(pattern: "^([ \\t]*)((?:\\d+\\.)*\\d+)[.)][ \\t]+(.*)$")
        if let match = orderedPattern.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) {
            let indent = (lineText as NSString).substring(with: match.range(at: 1))
            let rawNumber = (lineText as NSString).substring(with: match.range(at: 2))
            let body = (lineText as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                // Empty ordered item: exit list
                let replacement = indent.isEmpty ? "" : indent
                if shouldChangeText(in: lineRange, replacementString: replacement) {
                    storage.replaceCharacters(in: lineRange, with: replacement)
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location + (replacement as NSString).length, length: 0))
                    return true
                }
            } else {
                let nextNumber = incrementNumberSection(rawNumber)
                let nextPrefix = "\n\(indent)\(nextNumber). "
                if shouldChangeText(in: sel, replacementString: nextPrefix) {
                    storage.replaceCharacters(in: sel, with: nextPrefix)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + (nextPrefix as NSString).length, length: 0))
                    return true
                }
            }
        }

        return false
    }

    private func incrementNumberSection(_ numberStr: String) -> String {
        var parts = numberStr.split(separator: ".").map(String.init)
        if let last = parts.last, let val = Int(last), val < Int.max {
            parts[parts.count - 1] = String(val + 1)
            return parts.joined(separator: ".")
        }
        return numberStr
    }

    private func handleTabIndentation(shift: Bool) -> Bool {
        guard let storage = textStorage else { return false }
        let ns = string as NSString
        let sel = selectedRange()
        guard !hasMarkedText(), sel.length == 0, sel.location <= ns.length else { return false }
        let (lineRange, lineText) = lineContentRange(for: sel.location, in: ns)

        // Check if current line is an ordered list (e.g. "1. " -> "1.1 " on Tab, "1.1 " -> "1. " on Shift+Tab)
        let orderedPattern = try! NSRegularExpression(pattern: "^([ \\t]*)((?:\\d+\\.)*\\d+)[.)][ \\t]+(.*)$")
        if let match = orderedPattern.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) {
            let indent = (lineText as NSString).substring(with: match.range(at: 1))
            let numStr = (lineText as NSString).substring(with: match.range(at: 2))
            let rest = (lineText as NSString).substring(with: match.range(at: 3))

            if !shift {
                // Tab: create deeper sub-level (1. -> 1.1., 1.1 -> 1.1.1.)
                let newNum = numStr + ".1"
                let newLine = "\(indent)\(newNum). \(rest)"
                if shouldChangeText(in: lineRange, replacementString: newLine) {
                    storage.replaceCharacters(in: lineRange, with: newLine)
                    didChangeText()
                    let diff = (newLine as NSString).length - lineRange.length
                    setSelectedRange(NSRange(location: max(0, sel.location + diff), length: 0))
                    return true
                }
            } else {
                // Shift+Tab: pop out of sub-level (1.1.1 -> 1.1, 1.1 -> 1)
                var parts = numStr.split(separator: ".").map(String.init)
                if parts.count > 1 {
                    parts.removeLast()
                    let newNum = parts.joined(separator: ".")
                    let newLine = "\(indent)\(newNum). \(rest)"
                    if shouldChangeText(in: lineRange, replacementString: newLine) {
                        storage.replaceCharacters(in: lineRange, with: newLine)
                        didChangeText()
                        let diff = (newLine as NSString).length - lineRange.length
                        setSelectedRange(NSRange(location: max(0, sel.location + diff), length: 0))
                        return true
                    }
                }
            }
        }

        // Bullet list or task item: adjust leading spaces/tabs on Tab / Shift+Tab
        let bulletOrTaskPattern = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|[\u{2610}\u{2611}]|- \\[[ xX]\\])[ \\t]+(.*)$")
        if let match = bulletOrTaskPattern.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) {
            let indent = (lineText as NSString).substring(with: match.range(at: 1))
            let marker = (lineText as NSString).substring(with: match.range(at: 2))
            let rest = (lineText as NSString).substring(with: match.range(at: 3))

            if !shift {
                let newIndent = indent + "  "
                let newLine = "\(newIndent)\(marker) \(rest)"
                if shouldChangeText(in: lineRange, replacementString: newLine) {
                    storage.replaceCharacters(in: lineRange, with: newLine)
                    didChangeText()
                    setSelectedRange(NSRange(location: max(0, sel.location + 2), length: 0))
                    return true
                }
            } else if !indent.isEmpty {
                let newIndent: String
                let removedCount: Int
                if indent.hasPrefix("\t") {
                    newIndent = String(indent.dropFirst(1))
                    removedCount = 1
                } else if indent.hasPrefix("  ") {
                    newIndent = String(indent.dropFirst(2))
                    removedCount = 2
                } else {
                    newIndent = String(indent.dropFirst(1))
                    removedCount = 1
                }
                let newLine = "\(newIndent)\(marker) \(rest)"
                if shouldChangeText(in: lineRange, replacementString: newLine) {
                    storage.replaceCharacters(in: lineRange, with: newLine)
                    didChangeText()
                    setSelectedRange(NSRange(location: max(0, sel.location - removedCount), length: 0))
                    return true
                }
            }
            return true
        }

        return false
    }

    /// Symmetric with backspace-after-the-image: forward-deleting INTO a
    /// hidden token removes the whole image instead of eating a markup
    /// character the user cannot see.
    override func deleteForward(_ sender: Any?) {
        if selectedRange().length == 0, let storage = textStorage,
           let token = ImageStore.tokens(in: storage.string)
               .first(where: { $0.range.location == selectedRange().location }),
           storage.attribute(.notesHidden, at: token.range.location,
                             effectiveRange: nil) != nil {
            deleteImageToken(token)
            return
        }
        super.deleteForward(sender)
    }

    /// Deletes a hidden image token as one undoable edit. When the token
    /// occupies a whole line its line break goes along so the note does not
    /// keep an empty line where the picture was; an inline token keeps the
    /// surrounding line breaks untouched. Selecting the range and letting
    /// super delete keeps the removal grouped as a single ⌘Z step.
    func deleteImageToken(_ token: (id: String, width: CGFloat?, range: NSRange)) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        var range = token.range
        let precededByBreak = range.location == 0 || ns.character(at: range.location - 1) == 10
        let followedByBreak = NSMaxRange(range) == ns.length || ns.character(at: NSMaxRange(range)) == 10
        if precededByBreak && followedByBreak {
            if NSMaxRange(range) < ns.length {
                range.length += 1
            } else if range.location > 0 {
                range = NSRange(location: range.location - 1, length: range.length + 1)
            }
        }
        setSelectedRange(range)
        super.deleteBackward(nil)
    }


    // MARK: Character-like image navigation

    /// A hidden image token collapses to zero glyphs but should still walk
    /// like one character: arrow keys never park the caret inside the dozens
    /// of invisible markup characters. Left/right snap to the edge in the
    /// direction of travel; up/down land on the nearer edge.
    override func moveRight(_ sender: Any?) {
        super.moveRight(sender)
        snapCaretOutOfHiddenImageToken(edge: .trailing)
    }

    override func moveLeft(_ sender: Any?) {
        super.moveLeft(sender)
        snapCaretOutOfHiddenImageToken(edge: .leading)
    }

    override func moveUp(_ sender: Any?) {
        super.moveUp(sender)
        snapCaretOutOfHiddenImageToken(edge: .nearest)
    }

    override func moveDown(_ sender: Any?) {
        super.moveDown(sender)
        snapCaretOutOfHiddenImageToken(edge: .nearest)
    }

    private enum ImageCaretEdge { case leading, trailing, nearest }

    private func snapCaretOutOfHiddenImageToken(edge: ImageCaretEdge) {
        guard let storage = textStorage else { return }
        let caret = selectedRange()
        guard caret.length == 0 else { return }
        for token in ImageStore.tokens(in: storage.string)
        where caret.location > token.range.location && caret.location < NSMaxRange(token.range) {
            guard storage.attribute(.notesHidden, at: token.range.location,
                                    effectiveRange: nil) != nil else { return }
            let target: Int
            switch edge {
            case .leading: target = token.range.location
            case .trailing: target = NSMaxRange(token.range)
            case .nearest:
                let mid = token.range.location + token.range.length / 2
                target = caret.location <= mid ? token.range.location : NSMaxRange(token.range)
            }
            setSelectedRange(NSRange(location: target, length: 0))
            return
        }
    }

    /// The hidden image token a caret-backspace would eat into, if any: the
    /// caret sits inside/right after the markup (arrow keys can walk it onto
    /// the collapsed line), or directly below the image where deleting would
    /// consume the token line's newline.
    private func hiddenImageTokenAtDeletionPoint() -> (id: String, width: CGFloat?, range: NSRange)? {
        guard let storage = textStorage else { return nil }
        let caret = selectedRange().location
        let ns = storage.string as NSString
        for token in ImageStore.tokens(in: storage.string) {
            guard token.range.location < storage.length,
                  storage.attribute(.notesHidden, at: token.range.location,
                                    effectiveRange: nil) != nil else { continue }
            if caret > token.range.location, caret <= NSMaxRange(token.range) { return token }
            if caret == NSMaxRange(token.range) + 1, caret > 0,
               ns.character(at: caret - 1) == 10 { return token }
        }
        return nil
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    override func viewDidMoveToWindow() {
        // A closed or recycled note panel must not keep undo groups that point
        // at this text storage: a later ⌘Z would invoke them on a dead object
        // (EXC_BAD_ACCESS in _NSUndoStack.popAndInvoke).
        if window == nil { undoManager?.removeAllActions() }
        super.viewDidMoveToWindow()
        TaskTextView.wireEditMenu()
    }

    /// The Edit menu is built in AppDelegate, but the insert action belongs to
    /// whichever note has focus, so the item's target is left nil and travels
    /// the responder chain to this view.
    private static var editMenuWired = false

    private static func wireEditMenu() {
        guard !editMenuWired, let mainMenu = NSApp.mainMenu else { return }
        guard let edit = mainMenu.items.first(where: {
            $0.submenu?.title == NotesL10n.text("menu.edit")
        })?.submenu else { return }
        let action = #selector(insertImageFromPanel(_:))
        guard !edit.items.contains(where: { $0.action == action }) else {
            editMenuWired = true
            return
        }
        edit.addItem(.separator())
        edit.addItem(withTitle: NotesL10n.text("menu.insert_image"),
                     action: action, keyEquivalent: "")
        editMenuWired = true
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
        let visibleRange = NSRange(location: safeLocation, length: safeLength)

        ns.enumerateSubstrings(in: visibleRange, options: .byLines) { line, lineRange, _, _ in
            guard let line, Tasks.isTask(line) else { return }
            let lineText = line as NSString
            let indentRange = lineText.range(of: "^[ \\t]*", options: .regularExpression)
            let indentCount = indentRange.location != NSNotFound ? indentRange.length : 0
            let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: lineRange.location + indentCount, length: 1),
                                       actualCharacterRange: nil)
            var box = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            box.origin.x += origin.x
            box.origin.y += origin.y
            self.addCursorRect(box.insetBy(dx: -4, dy: -3), cursor: .pointingHand)
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

        let lineText = ns.substring(with: line)
        let indentRange = (lineText as NSString).range(of: "^[ \\t]*", options: .regularExpression)
        let indentCount = indentRange.location != NSNotFound ? indentRange.length : 0
        guard line.length > indentCount else { return false }

        let first = ns.character(at: line.location + indentCount)
        guard first == Tasks.open.unicodeScalars.first!.value ||
              first == Tasks.done.unicodeScalars.first!.value else { return false }

        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: line.location + indentCount, length: 1),
                                   actualCharacterRange: nil)
        var box = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        box.origin.x += textContainerOrigin.x
        box.origin.y += textContainerOrigin.y
        guard box.insetBy(dx: -4, dy: -3).contains(point) else { return false }

        let target = NSRange(location: line.location + indentCount, length: 1)
        let flipped = String(first == Tasks.open.unicodeScalars.first!.value ? Tasks.done : Tasks.open)
        guard shouldChangeText(in: target, replacementString: flipped) else { return true }
        storage.replaceCharacters(in: target, with: flipped)
        didChangeText()
        return true
    }

    // MARK: Images

    /// A plain-text view validates ⌘V off when the pasteboard holds only image
    /// data, which would keep paste(_:) from ever seeing it. Claim the command
    /// whenever the clipboard can provide an image.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if (item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:))),
           ImagePasteboard.canProvideImage(.general) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    /// An image on the pasteboard becomes a token on its own line; everything
    /// else keeps the plain-text paste behaviour.
    override func paste(_ sender: Any?) {
        guard ImagePasteboard.canProvideImage(.general) else { super.paste(sender); return }
        let ids = ImagePasteboard.imageIDs(from: .general)
        guard !ids.isEmpty else { return }
        insertImageTokens(ids.map { ImageStore.token(id: $0, width: nil) })
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImagePasteboard.canProvideImage(sender.draggingPasteboard)
            ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let ids = ImagePasteboard.imageIDs(from: sender.draggingPasteboard)
        guard !ids.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        insertImageTokens(ids.map { ImageStore.token(id: $0, width: nil) })
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        let item = NSMenuItem(title: NotesL10n.text("menu.insert_image"),
                              action: #selector(insertImageFromPanel(_:)),
                              keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func insertImageFromPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { ImagePasteboard.saveFile(at: $0) }
        insertImageTokens(ids.map { ImageStore.token(id: $0, width: nil) })
    }

    /// Insert each token on its own line at the caret as one undoable edit —
    /// the same shouldChangeText / replaceCharacters / didChangeText pattern
    /// as EditorBridge.toggleTaskLine, so undo and the style pipeline see a
    /// normal text change. The caret lands on a fresh line BELOW the token, so
    /// the next keystroke continues the note instead of touching the markup.
    func insertImageTokens(_ tokens: [String]) {
        guard !tokens.isEmpty, let storage = textStorage else { return }
        let ns = storage.string as NSString
        var range = selectedRange()
        if range.location == NSNotFound { range = NSRange(location: ns.length, length: 0) }
        range = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let atLineStart = range.location == 0 || ns.character(at: range.location - 1) == 10
        let atLineEnd = NSMaxRange(range) >= ns.length
            || ns.character(at: NSMaxRange(range)) == 10
        var insertion = tokens.joined(separator: "\n") + "\n"
        if !atLineStart { insertion = "\n" + insertion }
        if !atLineEnd { insertion += "\n" }
        guard shouldChangeText(in: range, replacementString: insertion) else { return }
        storage.replaceCharacters(in: range, with: insertion)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (insertion as NSString).length,
                                 length: 0))
    }
}
