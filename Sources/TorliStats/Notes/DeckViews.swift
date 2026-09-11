import SwiftUI

// MARK: - Root

struct DeckRootView: View {
    @ObservedObject var deck: DeckModel
    unowned let controller: DeckController
    @ObservedObject var store = NoteStore.shared

    private var onRight: Bool { !deck.onLeftEdge }
    private var edge: Edge { onRight ? .trailing : .leading }

    private var visible: [Note] {
        deck.showAll ? store.active : Array(store.active.prefix(NotesSettings.fanLimit))
    }
    private var hiddenCount: Int { max(0, store.active.count - NotesSettings.fanLimit) }
    private var showsMoreTab: Bool { !deck.showAll && hiddenCount > 0 }
    /// An empty deck still draws one tab, so the stack is never zero-height.
    private var itemCount: Int { max(1, visible.count) }

    /// Widest label currently on the deck — drives how tall each tab's strip is.
    private var longestLabel: CGFloat {
        visible.map { DeckGeom.labelWidth($0.displayTitle) }.max() ?? 0
    }

    private func layout(_ panelHeight: CGFloat) -> DeckLayout {
        DeckGeom.layout(panelHeight: panelHeight, count: itemCount,
                        hasMore: showsMoreTab, style: deck.style,
                        longestLabel: longestLabel)
    }

    var body: some View {
        // The height comes from the live layout pass, not from a value cached on
        // the model. When the panel resizes, AppKit relays out the existing view
        // tree at the new size *before* SwiftUI re-evaluates this body; anything
        // computed from a stored height is stale for that frame, and the pill
        // drew with zero padding at the top corner of the screen.
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let lay = layout(h)

            ZStack(alignment: onRight ? .topTrailing : .topLeading) {

                if deck.fanVisible || h > lay.stackHeight {
                    FanColumn(deck: deck, controller: controller,
                              notes: visible, hiddenCount: showsMoreTab ? hiddenCount : 0,
                              layout: lay, onRight: onRight)
                        .padding(.top, fanTop(lay, panelHeight: h))
                }

                PillView(notes: store.active)
                    .padding(.top, pillTop(panelHeight: h))
                    .padding(onRight ? .trailing : .leading, 1)
                    .opacity(deck.state == .rest && !deck.pillHidden ? 1 : 0)
                    .animation(.easeInOut(duration: 0.20).delay(deck.state == .rest ? 0.12 : 0), value: deck.state)

                // Declared last so it covers the deck, flush to the screen edge.
                if let id = deck.state.expandedID, let note = store.note(id: id) {
                    NoteEditorView(note: note, deck: deck, controller: controller, onRight: onRight)
                        .padding(.top, editorTop(lay, id: id))
                        .transition(.modifier(
                            active: NotePull(hidden: true, onRight: onRight),
                            identity: NotePull(hidden: false, onRight: onRight)))
                        .id(id)
                }
            }
            // A ZStack is only as wide as its widest child, so it has to be told to fill
            // the panel — otherwise the deck sits at the panel's left edge with a dead
            // gap against the screen. Filling from the parent's proposal (rather than a
            // measured width) keeps it pinned to the edge through a resize.
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: onRight ? .topTrailing : .topLeading)
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.9), value: deck.fanVisible)
        .animation(.easeInOut(duration: 0.22), value: deck.style)
    }

    /// Where the pill sits, for any panel height. At rest the panel is exactly the
    /// pill's height and this is zero; in a full-height panel it lands on the same
    /// screen position the resting panel occupies, so the pill does not move as the
    /// panel grows around it or shrinks back to it.
    private func pillTop(panelHeight h: CGFloat) -> CGFloat {
        let pillH = DeckGeom.pillHeight(noteCount: max(1, store.active.count))
        return (1.0 - NotesSettings.deckYRatio) * max(0, h - pillH)
    }

    private func fanTop(_ lay: DeckLayout, panelHeight h: CGFloat) -> CGFloat {
        let pillH = DeckGeom.pillHeight(noteCount: max(1, store.active.count))
        let availableH = max(1, h - pillH)
        let pillCenter = (1.0 - NotesSettings.deckYRatio) * availableH + pillH / 2
        let ideal = pillCenter - lay.stackHeight / 2
        return min(max(12, ideal), max(12, h - lay.stackHeight - 12))
    }

    /// Keep the open note level with its own tab, without letting it run off-screen.
    private func editorTop(_ lay: DeckLayout, id: String) -> CGFloat {
        if let top = deck.openedTop { return top }
        let idx = visible.firstIndex { $0.id == id } ?? 0
        let h = deck.openedHeight
        let fTop = fanTop(lay, panelHeight: lay.panelHeight)
        let strip = idx == lay.count - 1 ? lay.itemHeight : lay.pitch
        let stripCenter = fTop + CGFloat(idx) * lay.pitch + strip / 2
        let ideal = stripCenter - h / 2
        let lowest = max(10, lay.panelHeight - h - 10)
        let resolved = min(max(10, ideal), lowest)
        DispatchQueue.main.async { deck.openedTop = resolved }
        return resolved
    }
}

// MARK: - Pill (at rest)

struct PillView: View {
    let notes: [Note]

    private var shown: [Note] { Array(notes.prefix(DeckGeom.maxDashes)) }
    private var overflow: Int { max(0, notes.count - DeckGeom.maxDashes) }

    var body: some View {
        VStack(spacing: DeckGeom.dashGap) {
            if notes.isEmpty { dash(Color.secondary.opacity(0.4)) }
            ForEach(shown) { dash($0.palette.dash) }
            if overflow > 0 { dash(Color.secondary.opacity(0.5)) }
        }
        .padding(.vertical, DeckGeom.pillPad)
        .frame(width: DeckGeom.pillWidth)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 6, x: -2, y: 1)
        )
    }

    private func dash(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: DeckGeom.dashWidth, height: DeckGeom.dashHeight)
    }
}

struct NotePull: ViewModifier {
    let hidden: Bool
    let onRight: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: hidden ? (onRight ? 40 : -40) : 0)
            .scaleEffect(hidden ? 0.965 : 1, anchor: onRight ? .trailing : .leading)
            .opacity(hidden ? 0 : 1)
    }
}

struct EdgeLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

/// Rounded on the outward-facing side only, so the tab reads as docked to the edge.
func edgeTabShape(onRight: Bool, radius r: CGFloat = 11) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: onRight ? r : 0,
        bottomLeadingRadius: onRight ? r : 0,
        bottomTrailingRadius: onRight ? 0 : r,
        topTrailingRadius: onRight ? 0 : r,
        style: .continuous)
}

// MARK: - Shared bits

extension View {
    func noteContextMenu(_ note: Note) -> some View {
        contextMenu {
            Button(note.pinned ? NotesL10n.text("action.unpin") : NotesL10n.text("action.pin")) { NoteStore.shared.togglePin(id: note.id) }
            Button(NotesL10n.text("action.archive")) { NoteStore.shared.setArchived(id: note.id, true) }
            Button(NotesL10n.text("help.cycle_colour")) { NoteStore.shared.cycleColor(id: note.id) }
            Divider()
            Button(NotesL10n.text("action.delete")) { NoteStore.shared.delete(id: note.id) }
        }
    }
}
