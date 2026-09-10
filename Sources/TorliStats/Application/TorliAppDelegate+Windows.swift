import AppKit
import SwiftUI

extension TorliAppDelegate {
    @objc func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settings = SettingsView(
            settings: self.settings,
            codexUsageStore: codexUsageStore,
            wakaTimeUsageStore: wakaTimeUsageStore,
            typingStats: typingStats,
            updateChecker: updateChecker,
            onCodexRefresh: { [weak self] in
                self?.codexUsageStore.refresh()
            },
            onWakaTimeRefresh: { [weak self] in
                self?.wakaTimeUsageStore.refresh()
            },
            onRequestTypingStatsPermission: { [weak self] in
                self?.typingStats.requestPermissionAndStart()
            },
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdates()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 760),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = StatsL10n.text("window.settings_title")
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = self.settings.theme.windowAppearance
        window.minSize = NSSize(width: 900, height: 520)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: settings)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showStatisticsDetails(initialTab: StatisticsDetailTab) {
        statisticsDetailsWindow?.close()
        SettingsNavigation.shared.selectedStatisticsTab = initialTab
        SettingsNavigation.shared.selectedCategory = .statistics
        openSettings()
    }

    func checkForUpdatesIfNeeded() {
        updateChecker.checkIfNeeded(isEnabled: settings.automaticUpdateChecks) { [weak self] release in
            self?.announceAvailableUpdate(release)
        }
    }

    @objc func checkForUpdates() {
        updateChecker.check { [weak self] release in
            self?.announceAvailableUpdate(release)
        }
    }

    private func announceAvailableUpdate(_ release: AppUpdateRelease?) {
        guard let release, announcedUpdateVersion != release.version else { return }
        announcedUpdateVersion = release.version

        let alert = NSAlert()
        alert.messageText = StatsL10n.format("update.alert.title", release.version)
        alert.informativeText = StatsL10n.text("update.alert.message")
        alert.addButton(withTitle: StatsL10n.text("update.alert.download"))
        alert.addButton(withTitle: StatsL10n.text("update.alert.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.downloadURL)
        }
    }
}
