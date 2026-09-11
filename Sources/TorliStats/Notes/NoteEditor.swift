import SwiftUI
import AppKit

// MARK: - Editor

struct NoteTextDirectionLabel: View {
    let direction: NoteTextDirection
    let foreground: Color

    var body: some View {
        Group {
            if let symbol = direction.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Text(NotesL10n.text("direction.auto_short"))
                    .font(.system(size: 9.5, weight: .semibold))
            }
        }
        .foregroundStyle(foreground)
        .frame(width: direction == .automatic ? 27 : 18, height: 18)
        .contentShape(Rectangle())
    }
}

struct NoteTextDirectionMenu: View {
    let direction: NoteTextDirection
    let foreground: Color
    let select: (NoteTextDirection) -> Void

    var body: some View {
        Menu {
            ForEach(NoteTextDirection.allCases) { option in
                Button(option == direction ? "✓ \(option.title)" : option.title) {
                    select(option)
                }
            }
        } label: {
            NoteTextDirectionLabel(direction: direction, foreground: foreground)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Borderless menus use the control tint for their label on macOS,
        // overriding the label's foreground style (most visibly for "Auto").
        .tint(foreground)
        .fixedSize()
        .help(NotesL10n.format("help.text_direction", direction.title))
    }
}

struct NoteEditorView: View {
    let note: Note
    @ObservedObject var deck: DeckModel
    unowned let controller: DeckController
    var onRight: Bool = true

    @State private var text = ""
    @State private var title = ""
    @State private var saveWork: DispatchWorkItem?
    @State private var titleSaveWork: DispatchWorkItem?
    @State private var savedAt: Date?
    @State private var detaching = false
    @FocusState private var findFocused: Bool
    @FocusState private var titleFocused: Bool

    private var pal: NoteColor { note.palette }

    var body: some View {
        HStack(spacing: 0) {
            if onRight { gutter; sheet } else { sheet; gutter }
        }
        .opacity(deck.detachingID == note.id ? 0 : 1)
        .frame(width: deck.noteSize.width, height: deck.noteSize.height)
        .background(
            noteShape
                .fill(LinearGradient(colors: [pal.paper, pal.paper.opacity(0.88)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.34), radius: 28, x: onRight ? -12 : 12, y: 12)
        )
        .clipShape(noteShape)
        .overlay(noteShape.strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
        .onAppear {
            text = note.body
            title = note.title
            savedAt = note.modified
        }
        .onChange(of: text) { _, v in scheduleSave(v) }
        .onChange(of: title) { _, v in scheduleTitleSave(v) }
        .onChange(of: deck.findQuery) { _, q in
            if q != nil { findFocused = true } else { deck.bridge.focusText() }
        }
        .onDisappear { flush() }
    }

    /// Rounded where it leaves the deck, square where it meets the screen edge.
    private var noteShape: UnevenRoundedRectangle { edgeTabShape(onRight: onRight, radius: 14) }

    // MARK: The note itself

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            if deck.findQuery != nil { findBar }
            NoteTextView(text: $text, ink: NSColor(pal.ink),
                         bridge: deck.bridge, autofocus: true,
                         fontSize: deck.fontSize,
                         markdownEnabled: deck.markdown,
                         textDirection: note.textDirection,
                         styleToken: "\(note.color)|\(deck.fontSize)|\(NotesSettings.noteFontName)|\(deck.markdown)")
            footer
        }
    }

    /// The note's own tab, carried along so it reads as growing out of the deck.
    ///
    /// `rotationEffect` is a render transform, not a layout one: a rotated label
    /// still *measures* at its unrotated width, so the tint has to be sized on its
    /// own and the label clipped into it, or the background bleeds across the note.
    private var gutter: some View {
        Rectangle()
            .fill(pal.dash.opacity(0.20))
            .frame(width: DeckGeom.gutterWidth)
            .overlay {
                Text(note.displayTitle.uppercased())
                    .font(Ink.tabFont)
                    .tracking(Ink.tabTracking)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(pal.ink.opacity(0.7))
                    .frame(width: DeckGeom.editorHeight - 44)
                    .rotationEffect(.degrees(onRight ? 90 : -90))
            }
            .clipped()
            .overlay(alignment: onRight ? .trailing : .leading) {
                EdgeLine()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(pal.ink.opacity(0.22))
                    .frame(width: 1)
            }
            // Grab the tab and pull the note off the deck: past the threshold
            // the floating panel takes over under the cursor, and the sheet
            // here hides but stays in the hierarchy — removing it would end
            // this very gesture mid-drag.
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { v in
                    if detaching {
                        FloatingNote.shared.dragTo(NSEvent.mouseLocation)
                    } else if (onRight ? -v.translation.width : v.translation.width) > 40 {
                        detaching = true
                        deck.isDragging = true
                        flush()
                        controller.detachExpandedNote(at: NSEvent.mouseLocation)
                    }
                }
                .onEnded { _ in
                    guard detaching else { return }
                    detaching = false
                    deck.isDragging = false
                    controller.finishDetach()
                })
    }

    private var header: some View {
        HStack(spacing: 8) {
            // No `prompt:` — a plain-style field draws its placeholder in the
            // system secondary label colour and ignores every modifier put on
            // it, which reads as white on the paper in dark mode. A derived
            // title always shows *as* the placeholder, so it has to be our own
            // Text, which styles like anything else.
            ZStack(alignment: .leading) {
                if title.isEmpty {
                    Text(note.hasCustomTitle ? NotesL10n.text("note.title_prompt") : (Note.derivedTitle(from: text).isEmpty ? NotesL10n.text("note.untitled") : Note.derivedTitle(from: text)))
                        .foregroundStyle(pal.ink.opacity(titleFocused ? 0.35 : 0.92))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .foregroundStyle(pal.ink.opacity(0.92))
                    .focused($titleFocused)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .tint(pal.ink)
            .onSubmit {
                flushTitle()
                deck.bridge.focusText()
            }
            .contextMenu {
                if note.hasCustomTitle {
                    Button(NotesL10n.text("note.title_reset")) {
                        title = ""
                        NoteStore.shared.updateTitle(id: note.id, title: "")
                    }
                }
            }

            Spacer(minLength: 6)
            Text(savedAt.map { NotesL10n.format("note.saved", Fmt.ago($0)) }
                 ?? NotesL10n.text("note.not_saved"))
                .font(.system(size: 10))
                .foregroundStyle(pal.ink.opacity(0.42))
            Button { NoteStore.shared.togglePin(id: note.id) } label: {
                Image(systemName: note.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(note.pinned ? 0 : 32))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(pal.ink.opacity(note.pinned ? 0.85 : 0.4))
            .help(note.pinned ? NotesL10n.text("help.unpin") : NotesL10n.text("help.pin"))

            NoteTextDirectionMenu(direction: note.textDirection,
                                  foreground: pal.ink.opacity(0.5)) {
                NoteStore.shared.setTextDirection(id: note.id, direction: $0)
            }

            Button { deck.bridge.toggleTaskLine() } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(pal.ink.opacity(0.5))
            .help(NotesL10n.text("help.task"))
            Button { deck.findQuery = deck.findQuery == nil ? "" : nil } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(pal.ink.opacity(0.5))
            .help(NotesL10n.text("help.find"))
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10)).foregroundStyle(pal.ink.opacity(0.45))
            TextField(NotesL10n.text("note.find_placeholder"), text: Binding(
                get: { deck.findQuery ?? "" },
                set: { deck.findQuery = $0; deck.bridge.recount($0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(pal.ink)
                .focused($findFocused)
                .onSubmit { deck.bridge.findNext(deck.findQuery ?? "") }
            Text(deck.bridge.matchCount == 0 ? "—" : "\(deck.bridge.matchCount)")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(pal.ink.opacity(0.45))
            Button { deck.bridge.findNext(deck.findQuery ?? "", forward: false) } label: {
                Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
            }.buttonStyle(.plain).foregroundStyle(pal.ink.opacity(0.55))
            Button { deck.bridge.findNext(deck.findQuery ?? "") } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }.buttonStyle(.plain).foregroundStyle(pal.ink.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(pal.dash.opacity(0.12))
    }

    private var footer: some View {
        HStack(spacing: 7) {
            ForEach(Array(NoteColor.all.enumerated()), id: \.offset) { idx, c in
                Button { NoteStore.shared.setColor(id: note.id, color: idx) } label: {
                    Circle()
                        .fill(c.dash)
                        .frame(width: 11, height: 11)
                        .overlay(
                            Circle().strokeBorder(pal.ink.opacity(0.55),
                                                  lineWidth: idx == note.color ? 1.5 : 0)
                                .padding(-2.5)
                        )
                        .padding(2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(c.localizedName)
            }
            Spacer(minLength: 8)
            footerButton(NotesL10n.text("action.archive")) {
                NoteStore.shared.setArchived(id: note.id, true)
                controller.collapse()
            }
            footerButton(NotesL10n.text("action.delete")) {
                NoteStore.shared.delete(id: note.id)
                controller.collapse()
            }
            footerButton(NotesL10n.text("action.close")) { controller.collapse() }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(pal.ink.opacity(0.72))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(pal.ink.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Autosave — 250 ms after typing stops

    private func scheduleSave(_ value: String) {
        saveWork?.cancel()
        let work = DispatchWorkItem {
            NoteStore.shared.updateBody(id: note.id, body: value)
            savedAt = Date()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func scheduleTitleSave(_ value: String) {
        titleSaveWork?.cancel()
        let work = DispatchWorkItem {
            NoteStore.shared.updateTitle(id: note.id, title: value)
            savedAt = Date()
        }
        titleSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func flushTitle() {
        titleSaveWork?.cancel()
        NoteStore.shared.updateTitle(id: note.id, title: title)
    }

    private func flush() {
        saveWork?.cancel()
        titleSaveWork?.cancel()
        NoteStore.shared.updateBody(id: note.id, body: text)
        NoteStore.shared.updateTitle(id: note.id, title: title)
    }
}
