import SwiftUI
import AppKit

// MARK: - Fan

struct FanColumn: View {
    @ObservedObject var deck: DeckModel
    unowned let controller: DeckController
    let notes: [Note]
    let hiddenCount: Int
    let layout: DeckLayout
    let onRight: Bool

    @State private var appeared = false
    @State private var hoverWork: DispatchWorkItem?
    @State private var previewWork: DispatchWorkItem?
    @State private var previewNoteID: String?
    @State private var dragID: String?
    @State private var dragTarget: Int = 0

    private var isRevealed: Bool {
        deck.state != .rest && appeared
    }

    private var activePreviewNote: Note? {
        guard let id = previewNoteID, dragID == nil, deck.state.expandedID == nil else { return nil }
        return notes.first { $0.id == id }
    }

    private var previewIndex: Int {
        guard let id = previewNoteID, let idx = notes.firstIndex(where: { $0.id == id }) else { return 0 }
        return idx
    }

    var body: some View {
        ZStack(alignment: onRight ? .topTrailing : .topLeading) {
            Group {
                if deck.showAll && layout.overflows {
                    ScrollView(.vertical, showsIndicators: false) {
                        stack.padding(.vertical, 4)
                    }
                    .frame(height: layout.cap)
                    .scrollClipDisabled()
                } else {
                    stack
                }
            }
            .overlay(alignment: onRight ? .trailing : .leading) { spine }

            if let previewNote = activePreviewNote {
                NotePreviewCard(note: previewNote, onRight: onRight, onHoverChanged: { inside in
                    if inside {
                        previewWork?.cancel()
                    } else {
                        cancelHoverPreview(for: previewNote.id)
                    }
                }) {
                    previewNoteID = nil
                    open(previewNote)
                }
                .padding(.top, CGFloat(previewIndex) * layout.pitch)
                .padding(onRight ? .trailing : .leading, DeckGeom.tabWidth + 10)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: onRight ? 10 : -10)),
                    removal: .opacity
                ))
            }
        }
        .onAppear {
            DispatchQueue.main.async { appeared = true }
        }
        .onChange(of: deck.revealTick) { _, _ in
            appeared = false
            previewNoteID = nil
            DispatchQueue.main.async { appeared = true }
        }
        .onChange(of: deck.state) { _, newState in
            if newState == .rest {
                appeared = false
                previewNoteID = nil
                cancelHoverPreview()
            }
        }
    }

    /// The lap comes from negative stack spacing — real layout, so hit areas follow
    /// the tabs. (`.offset` would draw them in the right place but leave their taps
    /// behind at the top of the stack.) Paint order is left to declaration order: a
    /// stack draws later children on top, which is exactly the lap we want. An
    /// explicit `zIndex` per tab is *not* equivalent — it reorders neighbours and
    /// breaks the shingle.
    private var stack: some View {
        let total = notes.count + (hiddenCount > 0 ? 1 : 0) + 2
        return VStack(spacing: layout.spacing) {
            if notes.isEmpty {
                EmptyTab(height: layout.itemHeight, strip: layout.pitch, onRight: onRight) {
                    NotesAppBridge.shared.delegate?.newNote()
                }
                .staged(index: 0, total: 3, revealed: isRevealed, onRight: onRight)
            }
            ForEach(Array(notes.enumerated()), id: \.element.id) { idx, note in
                Group {
                    if deck.style == .compact {
                        ChipTab(note: note,
                                isOpen: deck.state.expandedID == note.id,
                                onRight: onRight,
                                action: { open(note) },
                                onHoverChanged: { inside in
                                    handleHover(note: note, inside: inside)
                                })
                    } else {
                        VerticalTab(note: note,
                                    isOpen: deck.state.expandedID == note.id,
                                    height: layout.itemHeight,
                                    strip: layout.pitch,
                                    onRight: onRight,
                                    lifted: dragID == note.id,
                                    action: { open(note) },
                                    onDragChanged: { dy in
                                        if dragID != note.id {
                                            dragID = note.id
                                            dragTarget = idx
                                            deck.isDragging = true
                                            cancelHoverOpen()
                                            cancelHoverPreview()
                                        }
                                        // Assign only on a real slot change, so the
                                        // column redraws a handful of times per drag
                                        // rather than on every pointer move.
                                        let next = target(from: idx, dy: dy)
                                        if next != dragTarget { dragTarget = next }
                                    },
                                    onHoverChanged: { inside in
                                        handleHover(note: note, inside: inside)
                                    },
                                    onDragEnded: { dy in
                                        let to = target(from: idx, dy: dy)
                                        dragID = nil
                                        deck.isDragging = false
                                        if to != idx { NoteStore.shared.reorder(id: note.id, by: to - idx) }
                                    })
                    }
                }
                // Only the tabs stepping aside animate; the dragged one carries its
                // own un-animated offset.
                .offset(y: shift(idx))
                .animation(dragID == note.id ? nil
                           : .spring(response: 0.26, dampingFraction: 0.86), value: dragTarget)
                // Only the tab being dragged is raised. Giving *every* tab a
                // zIndex reorders neighbours and breaks the shingle; leaving the
                // rest at the default keeps their declaration order intact.
                .zIndex(dragID == note.id ? 900 : 0)
                .staged(index: idx, total: total, revealed: isRevealed, onRight: onRight)
            }
            if hiddenCount > 0 {
                MoreTab(count: hiddenCount, height: layout.moreHeight, onRight: onRight) {
                    deck.showAll = true
                }
                .padding(.top, layout.moreGap - layout.spacing)   // undo the lap
                .staged(index: notes.count, total: total, revealed: isRevealed, onRight: onRight)
            }
            PlusButton { NotesAppBridge.shared.delegate?.newNote() }
                .padding(.top, DeckGeom.plusGap - layout.spacing)
                .staged(index: notes.count + (hiddenCount > 0 ? 1 : 0), total: total, revealed: isRevealed, onRight: onRight)
            CogButton { NotesAppBridge.shared.delegate?.openNoteSettings() }
                .padding(.top, DeckGeom.cogGap - layout.spacing)
                .staged(index: notes.count + (hiddenCount > 0 ? 1 : 0) + 1, total: total, revealed: isRevealed, onRight: onRight)
        }
        .frame(width: DeckGeom.tabWidth)
    }

    private func handleHover(note: Note, inside: Bool) {
        guard dragID == nil, deck.state.expandedID == nil else {
            cancelHoverOpen()
            cancelHoverPreview()
            return
        }
        if inside {
            // Hover-to-open makes the preview pointless — the note itself is
            // about to appear — so it wins and the card is skipped entirely.
            if deck.openOnHover { scheduleHoverOpen(note.id) }
            else if deck.tabPreview { scheduleHoverPreview(note) }
        } else {
            cancelHoverOpen()
            cancelHoverPreview(for: note.id)
        }
    }

    /// The pointer has to rest on a tab before it opens, or sweeping across the
    /// deck opens every note on the way past.
    private func scheduleHoverOpen(_ id: String) {
        hoverWork?.cancel()
        let work = DispatchWorkItem {
            guard deck.openOnHover, dragID == nil, deck.state.expandedID != id else { return }
            previewNoteID = nil
            controller.expand(id)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotesSettings.openOnHoverDelay, execute: work)
    }

    private func cancelHoverOpen() { hoverWork?.cancel(); hoverWork = nil }

    private func scheduleHoverPreview(_ note: Note) {
        previewWork?.cancel()
        if previewNoteID != nil, previewNoteID != note.id {
            withAnimation(.easeOut(duration: 0.10)) {
                previewNoteID = nil
            }
        }
        let work = DispatchWorkItem {
            guard dragID == nil, deck.state.expandedID == nil, deck.tabPreview,
                  !deck.openOnHover else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                previewNoteID = note.id
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotesSettings.tabPreviewDelay, execute: work)
    }

    private func cancelHoverPreview(for id: String? = nil) {
        previewWork?.cancel()
        let work = DispatchWorkItem {
            if id == nil || previewNoteID == id {
                withAnimation(.easeOut(duration: 0.12)) {
                    previewNoteID = nil
                }
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private var dragFrom: Int? { notes.firstIndex { $0.id == dragID } }

    /// Which slot the tab would drop into. A tab has to travel 60% of a slot
    /// before the target moves, not 50% — at the halfway mark the smallest
    /// pointer jitter flips the answer back and forth every frame, and each flip
    /// animates a whole row of tabs. That oscillation is the flashing.
    private func target(from: Int, dy: CGFloat) -> Int {
        let pitch = max(1, layout.pitch)
        let raw = dy / pitch
        let slots = raw > 0 ? Int(floor(raw + 0.4)) : Int(ceil(raw - 0.4))
        return min(max(0, from + slots), notes.count - 1)
    }

    /// The other tabs step aside as the dragged one passes, so the gap you are
    /// dropping into is always visible.
    private func shift(_ index: Int) -> CGFloat {
        guard let from = dragFrom, index != from else { return 0 }
        let to = dragTarget
        if from < to, index > from, index <= to { return -layout.pitch }
        if from > to, index < from, index >= to { return layout.pitch }
        return 0
    }

    private func open(_ note: Note) {
        if deck.state.expandedID == note.id { controller.collapse() }
        else { controller.expand(note.id) }
    }

    /// The dashed rule the deck hangs from, right at the screen edge.
    private var spine: some View {
        EdgeLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 1, height: min(layout.stackHeight + 26, layout.cap))
            .padding(onRight ? .trailing : .leading, 3)
            .allowsHitTesting(false)
    }
}

/// The note emerging from its tab: a short slide off the edge, a touch of scale
/// anchored there, and a fade. A full-width slide reads as a window flying in.
