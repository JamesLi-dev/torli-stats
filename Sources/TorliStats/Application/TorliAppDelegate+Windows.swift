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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Torli Stats 设置"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = AppColors.backgroundNSColor
        window.appearance = self.settings.theme.windowAppearance
        window.minSize = NSSize(width: 860, height: 420)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: settings)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showStatisticsDetails(initialTab: StatisticsDetailTab) {
        if let statisticsDetailsWindow {
            statisticsDetailsWindow.contentViewController = NSHostingController(
                rootView: StatisticsDetailView(
                    typingStats: typingStats,
                    wakaTimeUsageStore: wakaTimeUsageStore,
                    initialTab: initialTab,
                    onClose: { [weak statisticsDetailsWindow] in
                        statisticsDetailsWindow?.close()
                    }
                )
            )
            statisticsDetailsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "详细统计"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = AppColors.backgroundNSColor
        window.appearance = settings.theme.windowAppearance
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: StatisticsDetailView(
                typingStats: typingStats,
                wakaTimeUsageStore: wakaTimeUsageStore,
                initialTab: initialTab,
                onClose: { [weak window] in
                    window?.close()
                }
            )
        )
        window.center()
        statisticsDetailsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        alert.messageText = "Torli Stats \(release.version) 已可更新"
        alert.informativeText = "当前版本可在 GitHub Releases 页面下载。"
        alert.addButton(withTitle: "查看下载")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.downloadURL)
        }
    }
}
