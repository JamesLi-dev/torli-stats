import AppKit
import SwiftUI

extension TorliAppDelegate {
    func startNotesDeckIfNeeded() {
        guard deckManager == nil else { return }
        deckManager = DeckManager()
        UndoToast.shared.start()
        HotKeys.shared.register(
            newNote: { [weak self] in self?.newNote() },
            allNotes: { [weak self] in self?.openAllNotes() },
            archive: { [weak self] in self?.openArchive() },
            capture: { QuickCapture.shared.toggle() }
        )
    }

    @objc func toggleNotesDeck() {
        NotesSettings.notesDeckEnabled.toggle()
        if NotesSettings.notesDeckEnabled {
            startNotesDeckIfNeeded()
        } else {
            deckManager = nil
            HotKeys.shared.unregisterAll()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "torli-notes" {
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "text" })?
                .value ?? ""
            switch url.host {
            case "new" where !text.isEmpty:
                if !NotesSettings.notesDeckEnabled {
                    NotesSettings.notesDeckEnabled = true
                    startNotesDeckIfNeeded()
                }
                let note = NoteStore.shared.create(body: text)
                deckManager?.focused?.expand(note.id)
            case "new", "capture":
                QuickCapture.shared.show()
            case "all":
                openAllNotes()
            case "settings":
                openNoteSettings()
            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeys.shared.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func newNote() {
        if !NotesSettings.notesDeckEnabled {
            NotesSettings.notesDeckEnabled = true
            startNotesDeckIfNeeded()
        }
        let note = NoteStore.shared.create()
        deckManager?.focused?.expand(note.id)
    }

    @objc func openAllNotes() { LibraryWindow.shared.show(mode: .all) }
    @objc func openArchive() { LibraryWindow.shared.show(mode: .archive) }
    @objc func quickCapture() { QuickCapture.shared.toggle() }
    func refreshDecks() { deckManager?.refreshAll() }

    @objc func toggleOverFullScreen() {
        NotesSettings.showOverFullScreen.toggle()
        refreshDecks()
    }

    @objc func setDeckStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = DeckStyle(rawValue: raw) else { return }
        NotesSettings.deckStyle = style
        refreshDecks()
    }

    @objc func setFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        NotesSettings.noteFontSize = size
        refreshDecks()
    }

    func stepFontSize(by delta: Double) {
        NotesSettings.noteFontSize += delta
        refreshDecks()
    }

    @objc func setNoteFont(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NotesSettings.noteFontName = name
        refreshDecks()
    }

    @objc func toggleDeckAlwaysShown() {
        NotesSettings.deckAlwaysShown.toggle()
        refreshDecks()
    }

    @objc func setDeckScale(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double else { return }
        NotesSettings.deckScale = scale
        refreshDecks()
    }

    @objc func toggleDeckEdge() {
        NotesSettings.deckOnLeftEdge.toggle()
        refreshDecks()
    }

    @objc func setDisplayTarget(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        NotesSettings.displayTarget = target
        refreshDecks()
    }

    @objc func exportMarkdown() { Transfer.export(.markdown, notes: NoteStore.shared.notes) }
    @objc func exportPlainText() { Transfer.export(.plainText, notes: NoteStore.shared.notes) }
    @objc func exportSingleFile() { Transfer.export(.singleFile, notes: NoteStore.shared.notes) }
    @objc func exportStickies() { Transfer.export(.stickies, notes: NoteStore.shared.notes) }
    @objc func importStickies() { Transfer.importFiles() }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func openNoteSettings() {
        NotesSettingsWindow.shared.show()
    }

    func relaunchForLanguageChange(previous: AppLanguage) {
        // Notes language is currently scoped to the shared Torli app bundle.
        // Apply the preference to future launches without interrupting metrics.
    }
}
