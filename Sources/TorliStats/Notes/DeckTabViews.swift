import SwiftUI
import AppKit

// MARK: - Tabs

/// A tab keeps its colour and carries its label turned on its side.
///
/// Tabs overlap, so the label is pinned to the top of the tab — the part that
/// stays uncovered. Hovering lifts the whole tab clear to reveal the rest of it.
struct VerticalTab: View {
    let note: Note
    let isOpen: Bool
    let height: CGFloat
    let strip: CGFloat          // the part of this tab the next one does not cover
    let onRight: Bool
    var lifted: Bool = false
    let action: () -> Void
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }

    @State private var hovering = false
    @State private var dragging = false
    /// Held here rather than on the column: the dragged tab has to follow the
    /// pointer every frame, and keeping that state local means one small view
    /// redraws instead of every tab, its shadow and its material.
    @State private var dy: CGFloat = 0

    /// Past this much vertical travel it is a reorder, not a tap.
    private static let slop: CGFloat = 5

    /// One gesture, not a tap competing with a long-press. A press that never
    /// travels is a tap; anything that travels is a drag — and once it is a drag
    /// the tap can no longer fire, so dragging a tab cannot also open its note.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !dragging, abs(v.translation.height) > Self.slop { dragging = true }
                guard dragging else { return }
                dy = v.translation.height
                onDragChanged(dy)          // the column only reacts if the slot changed
            }
            .onEnded { v in
                if dragging {
                    onDragEnded(v.translation.height)
                } else if abs(v.translation.height) <= Self.slop {
                    action()
                }
                dragging = false
                dy = 0
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            edgeTabShape(onRight: onRight)
                .fill(note.palette.paper)
                .shadow(color: .black.opacity(lifted ? 0.42 : (isOpen || hovering ? 0.32 : 0.22)),
                        radius: lifted ? 16 : (isOpen || hovering ? 9 : 6),
                        x: onRight ? -3 : 3, y: lifted ? 6 : 2)
            Text(note.displayTitle.uppercased())
                .font(Ink.tabFont)
                .tracking(Ink.tabTracking)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(note.palette.ink.opacity(0.85))
                .frame(width: max(20, strip - DeckGeom.labelInset),
                       height: DeckGeom.tabWidth)
                .rotationEffect(.degrees(onRight ? 90 : -90))
                .frame(width: DeckGeom.tabWidth, height: strip)
                .offset(x: onRight ? -DeckGeom.bleed / 2 : DeckGeom.bleed / 2)
        }
        .frame(width: DeckGeom.tabWidth + DeckGeom.bleed, height: height, alignment: .top)
        .scaleEffect(lifted ? 1.04 : 1, anchor: onRight ? .trailing : .leading)
        .rotationEffect(.degrees(DeckGeom.lean(onRight: onRight)), anchor: onRight ? .trailing : .leading)
        .offset(x: onRight ? DeckGeom.bleed : -DeckGeom.bleed)
        .frame(width: DeckGeom.tabWidth)
        // Deliberately not animated: the dragged tab must track the pointer
        // exactly. A spring here reads as lag.
        .offset(y: dy)
        .contentShape(Rectangle())
        .overlay(alignment: onRight ? .topTrailing : .topLeading) {
            if note.pinned {
                Circle()
                    .fill(note.palette.dash)
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)
                    .padding(onRight ? .trailing : .leading, 9)
            }
        }
        .gesture(press)
        .onHover { hovering = $0; onHoverChanged($0) }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOpen)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: lifted)
        .noteContextMenu(note)
        .help(note.displayTitle)
    }
}

/// Compact style — colour only, so the deck barely touches the screen.
struct ChipTab: View {
    let note: Note
    let isOpen: Bool
    let onRight: Bool
    let action: () -> Void
    var onHoverChanged: (Bool) -> Void = { _ in }

    var body: some View {
        Button(action: action) {
            edgeTabShape(onRight: onRight, radius: 7)
                .fill(note.palette.dash)
                .frame(width: DeckGeom.chipWidth, height: DeckGeom.chipHeight)
                .shadow(color: .black.opacity(isOpen ? 0.34 : 0.22), radius: isOpen ? 8 : 5,
                        x: onRight ? -2 : 2, y: 1)
                .rotationEffect(.degrees(DeckGeom.lean(onRight: onRight) * 0.6), anchor: onRight ? .trailing : .leading)
                .offset(x: onRight ? DeckGeom.bleed / 2 : -DeckGeom.bleed / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: isOpen)
        .onHover { onHoverChanged($0) }
        .noteContextMenu(note)
        .help(note.displayTitle)
    }
}

/// Flyout preview card showing a note's title, checklist progress, and body snippet on tab hover.
struct NotePreviewCard: View {
    let note: Note
    let onRight: Bool
    var onHoverChanged: ((Bool) -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(note.palette.dash)
                        .frame(width: 7, height: 7)
                    Text(note.displayTitle)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(note.palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let prog = note.taskProgress {
                        Text("\(prog.done)/\(prog.total)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(note.palette.ink.opacity(0.65))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(note.palette.ink.opacity(0.12)))
                    }
                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(note.palette.ink.opacity(0.7))
                    }
                }

                let lines = note.body.split(whereSeparator: \.isNewline).map(String.init)
                let previewLines = Array((note.hasCustomTitle ? lines : Array(lines.dropFirst())).prefix(4))
                if !previewLines.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                            if Tasks.isTask(line) {
                                let isDone = Tasks.marker(of: line) == Tasks.done
                                HStack(spacing: 4) {
                                    // Done tasks dim in the note's own ink, exactly as the
                                    // editor draws them. Color.secondary follows the system
                                    // appearance, not the paper — near-white in dark mode.
                                    Image(systemName: isDone ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(note.palette.ink.opacity(isDone ? 0.45 : 0.75))
                                    Text(Tasks.stripped(line))
                                        .font(.system(size: 10.5))
                                        .strikethrough(isDone, color: note.palette.ink.opacity(0.45))
                                        .foregroundStyle(note.palette.ink.opacity(isDone ? 0.45 : 0.85))
                                        .lineLimit(1)
                                }
                            } else {
                                Text(line)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(note.palette.ink.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Text(NotesL10n.text("note.empty"))
                        .font(.system(size: 10).italic())
                        .foregroundStyle(note.palette.ink.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: 210, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(note.palette.paper)
                    .shadow(color: .black.opacity(0.26), radius: 9, x: onRight ? -3 : 3, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(note.palette.ink.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { onHoverChanged?($0) }
    }
}

struct MoreTab: View {
    let count: Int
    let height: CGFloat
    let onRight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                edgeTabShape(onRight: onRight, radius: 9)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 5, x: onRight ? -2 : 2, y: 1)
                Text("+\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: DeckGeom.tabWidth, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .help(NotesL10n.plural("notes.more", count))
    }
}

struct EmptyTab: View {
    let height: CGFloat
    let strip: CGFloat
    let onRight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                edgeTabShape(onRight: onRight).fill(.ultraThinMaterial)
                Text(NotesL10n.text("note.new_tab").uppercased())
                    .font(Ink.tabFont)
                    .tracking(Ink.tabTracking)
                    .foregroundStyle(.secondary)
                    .frame(width: max(20, strip - DeckGeom.labelInset),
                           height: DeckGeom.tabWidth)
                    .rotationEffect(.degrees(onRight ? 90 : -90))
                    .frame(width: DeckGeom.tabWidth, height: strip)
            }
            .frame(width: DeckGeom.tabWidth, height: height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
    }
}

struct PlusButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: DeckGeom.plusSize, height: DeckGeom.plusSize)
                .background(Circle().fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 1))
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(NotesL10n.text("help.new_note"))
    }
}

/// NotesSettings, one step below the new-note button. The pill's context menu still
/// has everything; this is just the door people can find.
struct CogButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(hovering ? 0.8 : 0.5))
                .frame(width: DeckGeom.cogSize, height: DeckGeom.cogSize)
                .background(Circle().fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1))
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(NotesL10n.text("help.settings"))
    }
}
