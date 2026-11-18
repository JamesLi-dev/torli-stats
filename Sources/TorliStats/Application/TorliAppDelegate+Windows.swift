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
            codexTokenActivityService: codexTokenActivityService,
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
            guard let self, self.updateChecker.checkingController == nil else { return }
            self.announceAvailableUpdate(release, manual: false)
        }
    }

    @objc func checkForUpdates() {
        if let controller = updateChecker.installationController, controller.isVisible {
            controller.show()
            return
        }
        if let controller = updateChecker.checkingController {
            controller.show()
            return
        }
        let controller = UpdateCheckController { [weak checker = updateChecker] cancelled in
            if cancelled { checker?.cancelCheck() }
            checker?.checkingController = nil
        }
        updateChecker.checkingController = controller
        controller.show()
        updateChecker.check { [weak self, weak controller] release in
            guard let self, let controller, controller.isChecking,
                  self.updateChecker.checkingController === controller else { return }
            if let release {
                controller.finish()
                self.announceAvailableUpdate(release, manual: true)
            } else {
                controller.showResult(status: self.updateChecker.status, currentVersion: self.updateChecker.currentVersion)
            }
        }
    }

    private func announceAvailableUpdate(_ release: AppUpdateRelease?, manual: Bool) {
        guard let release else { return }
        if let controller = updateChecker.installationController, controller.isVisible {
            controller.show()
            return
        }
        guard manual || announcedUpdateVersion != release.version else { return }
        announcedUpdateVersion = release.version
        let controller = UpdateInstallationController(release: release, currentVersion: updateChecker.currentVersion)
        updateChecker.installationController = controller
        controller.show()
    }
}

final class UpdateCheckController: NSObject, ObservableObject, NSWindowDelegate {
    struct ResultMessage {
        let title: String
        let detail: String
    }

    @Published private(set) var result: ResultMessage?
    private(set) var isChecking = true
    private var window: NSWindow?
    private var onClose: ((Bool) -> Void)?

    init(onClose: @escaping (Bool) -> Void) {
        self.onClose = onClose
        super.init()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: UpdateWindowLayout.progressHeight),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = StatsL10n.text("update.window.title")
            window.isReleasedWhenClosed = false
            window.delegate = self
            let hosting = NSHostingController(rootView: UpdateCheckView(controller: self))
            hosting.sizingOptions = []
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 380, height: UpdateWindowLayout.progressHeight))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showResult(status: AppUpdateCheckStatus, currentVersion: String) {
        guard isChecking else { return }
        isChecking = false
        switch status {
        case .upToDate:
            result = ResultMessage(
                title: StatsL10n.text("update.check.current_title"),
                detail: StatsL10n.format("update.check.current_detail", currentVersion)
            )
        case .credentialRequired:
            result = ResultMessage(title: StatsL10n.text("update.window.title"), detail: status.description)
        case .unavailable:
            result = ResultMessage(
                title: StatsL10n.text("update.window.title"),
                detail: StatsL10n.text("update.unavailable")
            )
        default:
            result = ResultMessage(
                title: StatsL10n.text("update.failed"),
                detail: StatsL10n.text("update.check.failed_detail")
            )
        }
        window?.styleMask.insert(.resizable)
        window?.contentMinSize = NSSize(width: 380, height: 170)
        window?.setContentSize(NSSize(width: 380, height: 170))
    }

    func finish() {
        isChecking = false
        close()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let cancelled = isChecking
        isChecking = false
        window = nil
        let callback = onClose
        onClose = nil
        callback?(cancelled)
    }
}

final class UpdateInstallationController: NSObject, ObservableObject, NSWindowDelegate {
    enum State {
        case details
        case preparing
        case prepared
        case failed(String)
    }

    enum NotesState {
        case loading
        case loaded([UpdateReleaseNoteLine])
        case failed
    }

    let release: AppUpdateRelease
    let currentVersion: String
    @Published private(set) var state: State = .details
    @Published private(set) var notesState: NotesState = .loading
    @Published private(set) var progress: UpdatePreparationProgress = .preparing
    private(set) var usesHomebrew = false
    private var window: NSWindow?
    private var preparationTask: UpdatePreparationTask?
    private var preparedUpdate: PreparedAppUpdate?
    private var operation = 0
    private var isConfirming = false
    private var hasConfirmedInstallation = false
    private var isInstalling = false

    init(release: AppUpdateRelease, currentVersion: String) {
        self.release = release
        self.currentVersion = currentVersion
        super.init()
        AppUpdateReleaseNotes.load(release: release) { [weak self] notes in
            self?.notesState = notes.map { .loaded(UpdateReleaseNoteLine.parse($0)) } ?? .failed
        }
    }

    var isVisible: Bool { window?.isVisible == true }

    var actionTitle: String {
        switch state {
        case .prepared: return StatsL10n.text("update.install.relaunch")
        case .failed: return StatsL10n.text("update.install.retry")
        default: return StatsL10n.text("update.install.action")
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = StatsL10n.text("update.window.title")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 500, height: 350)
            window.delegate = self
            let hosting = NSHostingController(rootView: UpdateInstallationView(controller: self))
            hosting.sizingOptions = []
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 500, height: 350))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        operation += 1
        preparationTask?.cancel()
        preparationTask = nil
        preparedUpdate = nil
        hasConfirmedInstallation = false
        state = .details
        window = nil
    }

    func cancel() {
        window?.close()
    }

    private func transition(to state: State) {
        self.state = state
        let size: NSSize
        switch state {
        case .details: size = NSSize(width: 500, height: 350)
        case .preparing: size = NSSize(width: 400, height: UpdateWindowLayout.progressHeight)
        case .prepared: size = NSSize(width: 400, height: 210)
        case .failed: size = NSSize(width: 500, height: 320)
        }
        window?.contentMinSize = size
        window?.setContentSize(size)
    }

    func install() {
        guard !isConfirming, !isInstalling, preparationTask == nil, isVisible else { return }
        if case .prepared = state {
            installPreparedUpdate()
            return
        }
        if case .preparing = state { return }
        if !hasConfirmedInstallation {
            isConfirming = true
            let confirmationOperation = operation
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = StatsL10n.text("update.confirm.title")
            alert.informativeText = StatsL10n.text("update.alert.message")
            alert.addButton(withTitle: StatsL10n.text("update.install.action"))
            alert.addButton(withTitle: StatsL10n.text("update.install.confirm_cancel"))
            let confirmed = alert.runModal() == .alertFirstButtonReturn
            isConfirming = false
            guard confirmed, isVisible, operation == confirmationOperation else { return }
            // The release is fixed for this controller; retries keep this window's consent.
            hasConfirmedInstallation = true
        }
        operation += 1
        let currentOperation = operation
        usesHomebrew = false
        progress = .preparing
        transition(to: .preparing)
        preparationTask = AppUpdateInstaller().prepare(release: release, progress: { [weak self] progress in
            guard let self, self.operation == currentOperation, self.isVisible else { return }
            if case .homebrew = progress { self.usesHomebrew = true }
            self.progress = progress
        }, completion: { [weak self] result in
            guard let self, self.operation == currentOperation, self.isVisible else { return }
            self.preparationTask = nil
            switch result {
            case let .failure(error):
                self.transition(to: .failed(error.localizedDescription))
            case let .success(prepared):
                self.preparedUpdate = prepared
                self.transition(to: .prepared)
            }
        })
    }

    private func installPreparedUpdate() {
        guard let prepared = preparedUpdate else { return }
        guard NoteStore.shared.flushAll() else {
            preparedUpdate = nil
            transition(to: .failed(StatsL10n.text("update.install.notes_unsaved")))
            return
        }
        isInstalling = true
        defer { isInstalling = false }
        do {
            try prepared.launchInstaller()
            NSApp.terminate(nil)
            prepared.cancelInstaller()
            preparedUpdate = nil
            transition(to: .failed(StatsL10n.text("update.install.termination_cancelled")))
        } catch {
            prepared.cancelInstaller()
            preparedUpdate = nil
            transition(to: .failed(error.localizedDescription))
        }
    }
}
