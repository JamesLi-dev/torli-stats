import SwiftUI
import AppKit

struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let ink: NSColor
    let bridge: EditorBridge
    var autofocus: Bool
    var fontSize: CGFloat = 13.5
    var markdownEnabled: Bool = NotesSettings.markdownStyling
    var textDirection: NoteTextDirection = .automatic
    /// Everything that affects how the text is drawn, as one cheap value. The
    /// alternative — comparing a freshly built NSColor and NSFont — is not
    /// reliably equal, so a full restyle ran on every re-render.
    var styleToken: String = ""

    static func bodyFont(_ size: CGFloat) -> NSFont { Ink.body(size) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        // An explicit TextKit 1 stack: a plain NSTextView would get TextKit 2,
        // where NSLayoutManager — and so the glyph hiding — is never consulted.
        let storage = NSTextStorage()
        let layout = HidingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let tv = TaskTextView(frame: .zero, textContainer: container)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = Self.bodyFont(fontSize)
        tv.textColor = ink
        tv.insertionPointColor = ink
        tv.textContainerInset = NSSize(width: 15, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        // AppKit paints .link ranges system blue by default, which fights every
        // paper colour in the deck. Keep the underline and the cursor, and let
        // the note's own ink through.
        tv.linkTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        tv.string = text
        scroll.documentView = tv
        bridge.textView = tv
        let activeLine = EditorStyleEngine.lineRange(
            containing: tv.selectedRange().location, in: storage.mutableString)
        Self.applyStyles(to: tv,
                         ranges: [NSRange(location: 0, length: storage.length)],
                         revealing: activeLine,
                         ink: ink,
                         size: fontSize,
                         markdownEnabled: markdownEnabled,
                         textDirection: textDirection)
        Self.applyTextDirection(textDirection, to: tv)
        context.coordinator.attach(to: tv)
        if autofocus {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        context.coordinator.synchronize(tv)
        Self.applyTextDirection(textDirection, to: tv)
        if bridge.textView !== tv { bridge.textView = tv }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        tv.delegate = nil
        tv.textStorage?.delegate = nil
    }

    static func applyTextDirection(_ direction: NoteTextDirection, to textView: NSTextView) {
        // Automatic is applied per paragraph by EditorStyleEngine. Assigning
        // NSTextView.alignment/baseWritingDirection here would rewrite every
        // paragraph back to AppKit's locale-based `.natural` alignment after
        // the engine had resolved its first strong character.
        guard direction != .automatic else { return }
        textView.baseWritingDirection = direction.writingDirection
        textView.alignment = direction.alignment
    }

    @discardableResult
    private static func applyStyles(to tv: NSTextView,
                                    ranges: [NSRange],
                                    revealing activeLine: NSRange?,
                                    ink: NSColor,
                                    size: CGFloat,
                                    markdownEnabled: Bool,
                                    textDirection: NoteTextDirection) -> [NSRange] {
        EditorStyleEngine.apply(to: tv,
                                ranges: ranges,
                                revealing: activeLine,
                                ink: ink,
                                size: size,
                                markdownEnabled: markdownEnabled,
                                textDirection: textDirection,
                                bodyFont: bodyFont,
                                isCompletedTask: { Tasks.marker(of: $0) == Tasks.done })
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: NoteTextView

        private var edits = EditorEditAccumulator()
        private var lastLine = NSRange(location: NSNotFound, length: 0)
        private var isApplyingStyles = false
        private var needsFullPass = false
        /// The style token last applied. Comparing one string beats rebuilding
        /// an NSColor and an NSFont and hoping they compare equal — they do not
        /// reliably, and every re-render then ran a full restyle.
        private var appliedStyle: String?

        init(_ p: NoteTextView) { parent = p }

        func attach(to tv: NSTextView) {
            tv.textStorage?.delegate = self
            lastLine = activeLine(in: tv)
            rememberConfiguration()
        }

        func synchronize(_ tv: NSTextView) {
            if tv.string != parent.text {
                // SwiftUI can update around every IME composition event. Never
                // replace the native string while the input method owns it.
                guard !tv.hasMarkedText() else {
                    needsFullPass = true
                    return
                }
                let selection = tv.selectedRange()
                isApplyingStyles = true
                tv.string = parent.text
                edits.clear()
                tv.setSelectedRange(clamped(selection, to: tv.string.utf16.count))
                isApplyingStyles = false
                needsFullPass = true
            }

            if configurationChanged() { needsFullPass = true }
            if needsFullPass { applyFullPassIfSafe(to: tv) }
        }

        func textStorage(_ textStorage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange,
                         changeInLength delta: Int) {
            guard !isApplyingStyles, editedMask.contains(.editedCharacters) else { return }
            edits.record(editedRange)
        }

        /// Moving the caret to another line changes which markers are revealed.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingStyles,
                  let tv = notification.object as? NSTextView,
                  !tv.hasMarkedText() else { return }

            // TextKit can post a selection change while a character edit is
            // still being finalized. Touching attributes in that intermediate
            // state can leave the newly generated glyphs absent until a later
            // edit. Let textDidChange perform the one incremental style pass
            // after the edit notification has completed.
            guard !edits.hasPendingEdits else { return }

            let line = activeLine(in: tv)
            guard parent.markdownEnabled else {
                lastLine = line
                return
            }
            guard line.location != lastLine.location else { return }

            let previous = lastLine
            lastLine = line
            applyIncremental([previous, line], to: tv, invalidateCursors: false)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingStyles,
                  let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string

            // Binding updates are safe during composition; attributes, layout,
            // cursor rectangles, and selection writes are deliberately deferred.
            guard !tv.hasMarkedText() else { return }

            if needsFullPass {
                applyFullPassIfSafe(to: tv)
                return
            }
            let dirty = consumeEdits(in: tv)
            if !dirty.isEmpty {
                applyIncremental(dirty, to: tv, invalidateCursors: true)
            } else {
                lastLine = activeLine(in: tv)
            }
        }

        private func consumeEdits(in tv: NSTextView) -> [NSRange] {
            guard let storage = tv.textStorage else { return [] }
            return edits.consume(in: storage.mutableString, hasMarkedText: tv.hasMarkedText())
        }

        private func applyIncremental(_ ranges: [NSRange], to tv: NSTextView,
                                      invalidateCursors: Bool) {
            guard !tv.hasMarkedText(), !ranges.isEmpty else { return }

            let line = activeLine(in: tv)
            isApplyingStyles = true
            NoteTextView.applyStyles(to: tv,
                                     ranges: ranges,
                                     revealing: line,
                                     ink: parent.ink,
                                     size: parent.fontSize,
                                     markdownEnabled: parent.markdownEnabled,
                                     textDirection: parent.textDirection)
            isApplyingStyles = false
            lastLine = line
            if invalidateCursors { tv.window?.invalidateCursorRects(for: tv) }
        }

        private func applyFullPassIfSafe(to tv: NSTextView) {
            guard !tv.hasMarkedText(), let storage = tv.textStorage else {
                needsFullPass = true
                return
            }

            let font = NoteTextView.bodyFont(parent.fontSize)
            let line = activeLine(in: tv)
            isApplyingStyles = true
            tv.textColor = parent.ink
            tv.insertionPointColor = parent.ink
            tv.font = font
            NoteTextView.applyStyles(to: tv,
                                     ranges: [NSRange(location: 0, length: storage.length)],
                                     revealing: line,
                                     ink: parent.ink,
                                     size: parent.fontSize,
                                     markdownEnabled: parent.markdownEnabled,
                                     textDirection: parent.textDirection)
            isApplyingStyles = false

            edits.clear()
            lastLine = line
            needsFullPass = false
            rememberConfiguration()
            tv.window?.invalidateCursorRects(for: tv)
        }

        private func activeLine(in tv: NSTextView) -> NSRange {
            guard let storage = tv.textStorage else {
                return NSRange(location: 0, length: 0)
            }
            return EditorStyleEngine.lineRange(containing: tv.selectedRange().location,
                                               in: storage.mutableString)
        }

        private func configurationChanged() -> Bool {
            appliedStyle != configurationToken
        }

        private func rememberConfiguration() {
            appliedStyle = configurationToken
        }

        private var configurationToken: String {
            "\(parent.styleToken)|\(parent.textDirection.rawValue)"
        }

        private func clamped(_ selection: NSRange, to length: Int) -> NSRange {
            let location = min(selection.location == NSNotFound ? length : selection.location, length)
            return NSRange(location: location,
                           length: min(selection.length, length - location))
        }

        /// Return on a task line starts the next task; on an empty one, ends the list.
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString replacement: String?) -> Bool {
            guard replacement == "\n" else { return true }
            let ns = tv.string as NSString
            guard range.location <= ns.length else { return true }
            let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let text = ns.substring(with: line)
            guard Tasks.isTask(text) else { return true }

            if Tasks.stripped(text.trimmingCharacters(in: .newlines)).isEmpty {
                let clear = NSRange(location: line.location,
                                    length: min(line.length, ns.length - line.location))
                if tv.shouldChangeText(in: clear, replacementString: "") {
                    tv.textStorage?.replaceCharacters(in: clear, with: "")
                    tv.didChangeText()
                }
                return false
            }
            tv.insertText("\n" + Tasks.openPrefix, replacementRange: range)
            return false
        }
    }
}
