import AppKit
import SwiftUI

extension TorliAppDelegate {
    func showContextMenu() {
        guard let button = statusItem.button else { return }
        closePopover()

        let menu = NSMenu()
        menu.autoenablesItems = false
        // Privacy mode previously used NSMenuItem.state, which makes AppKit
        // reserve an empty state/checkmark column for every menu item. Use
        // matching symbols instead so the leading edges stay compact.
        menu.showsStateColumn = false

        let aboutItem = NSMenuItem(
            title: StatsL10n.text("menu.about"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.image = menuSymbol("info.circle")
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: StatsL10n.text("menu.open_settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.image = menuSymbol("gearshape")
        menu.addItem(settingsItem)

        let notesToggleItem = NSMenuItem(
            title: StatsL10n.text(NotesSettings.notesDeckEnabled ? "menu.disable_notes" : "menu.enable_notes"),
            action: #selector(toggleNotesDeck),
            keyEquivalent: ""
        )
        notesToggleItem.image = menuSymbol(NotesSettings.notesDeckEnabled ? "note.text" : "note.text.badge.plus")
        menu.addItem(notesToggleItem)

        if NotesSettings.notesDeckEnabled {
            let newNoteItem = NSMenuItem(title: StatsL10n.text("menu.new_note"), action: #selector(newNote), keyEquivalent: "n")
            newNoteItem.image = menuSymbol("square.and.pencil")
            menu.addItem(newNoteItem)

            let allNotesItem = NSMenuItem(title: StatsL10n.text("menu.all_notes"), action: #selector(openAllNotes), keyEquivalent: "")
            allNotesItem.image = menuSymbol("note.text")
            menu.addItem(allNotesItem)
        }

        let noteSettingsItem = NSMenuItem(title: StatsL10n.text("menu.notes_settings"), action: #selector(openNoteSettings), keyEquivalent: "")
        noteSettingsItem.image = menuSymbol("slider.horizontal.3")
        menu.addItem(noteSettingsItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: StatsL10n.text("menu.refresh_all"),
            action: #selector(refreshAllData),
            keyEquivalent: "r"
        )
        refreshItem.image = menuSymbol("arrow.clockwise")
        menu.addItem(refreshItem)

        let monitoringPauseItem = NSMenuItem(
            title: StatsL10n.text(settings.manualMonitoringPaused ? "menu.resume_monitoring" : "menu.pause_monitoring"),
            action: #selector(toggleManualMonitoringPause),
            keyEquivalent: ""
        )
        monitoringPauseItem.image = menuSymbol(settings.manualMonitoringPaused ? "play.circle" : "pause.circle")
        menu.addItem(monitoringPauseItem)

        let privacyItem = NSMenuItem(
            title: StatsL10n.text("menu.privacy_mode"),
            action: #selector(togglePrivacyMode),
            keyEquivalent: ""
        )
        privacyItem.image = menuSymbol(settings.privacyMode ? "eye.slash.fill" : "eye.slash")
        menu.addItem(privacyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: StatsL10n.text("menu.quit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.image = menuSymbol("power")
        menu.addItem(quitItem)
        menu.items.forEach { $0.target = self }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY - 4),
            in: button
        )
    }

    private func menuSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func refreshAllData() {
        monitoringPauseController.recordUserInteraction()
        store.refreshNow()
        codexUsageStore.refresh()
    }

    @objc private func toggleManualMonitoringPause() {
        settings.manualMonitoringPaused.toggle()
    }

    @objc private func togglePrivacyMode() {
        settings.privacyMode.toggle()
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? StatsL10n.text("about.development_version")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let sensorStatus = StatsL10n.text(settings.sensorHelperEnabled ? "about.sensor.authorized" : "about.sensor.unavailable")
        let alert = NSAlert()
        alert.messageText = "Torli Stats"
        alert.informativeText = StatsL10n.format(
            "about.diagnostic", version, build, appArchitecture,
            system.majorVersion, system.minorVersion, system.patchVersion, sensorStatus
        )
        alert.addButton(withTitle: StatsL10n.text("about.ok"))
        alert.addButton(withTitle: StatsL10n.text("about.copy_diagnostics"))
        alert.addButton(withTitle: StatsL10n.text("about.third_party_licenses"))

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            copyDiagnosticInfo(version: version, build: build, sensorStatus: sensorStatus)
        case .alertThirdButtonReturn:
            if let noticeURL = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                NSWorkspace.shared.open(noticeURL)
            }
        default:
            break
        }
    }

    private var appArchitecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return StatsL10n.text("common.unknown")
        #endif
    }

    private func copyDiagnosticInfo(version: String, build: String, sensorStatus: String) {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let diagnostic = StatsL10n.format(
            "about.diagnostic", version, build, appArchitecture,
            system.majorVersion, system.minorVersion, system.patchVersion, sensorStatus
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic, forType: .string)
    }
    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
