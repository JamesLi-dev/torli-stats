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
            self?.announceAvailableUpdate(release, manual: false)
        }
    }

    @objc func checkForUpdates() {
        updateChecker.check { [weak self] release in
            self?.announceAvailableUpdate(release, manual: true)
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
        if let controller = updateChecker.installationController, controller.isPreparing {
            controller.show()
        } else {
            let controller = UpdateInstallationController(release: release)
            updateChecker.installationController = controller
            controller.show()
        }
    }
}

final class UpdateInstallationController: NSObject, ObservableObject, NSWindowDelegate {
    enum State {
        case ready
        case preparing
        case failed(String)
    }

    enum NotesState {
        case loading
        case loaded(String)
        case failed
    }

    let release: AppUpdateRelease
    @Published private(set) var state: State = .ready
    @Published private(set) var notesState: NotesState = .loading
    private var window: NSWindow?
    private var cancelled = false
    private var isConfirming = false

    init(release: AppUpdateRelease) {
        self.release = release
        super.init()
        AppUpdateReleaseNotes.load(release: release) { [weak self] notes in
            self?.notesState = notes.map { .loaded($0) } ?? .failed
        }
    }

    var isVisible: Bool { window?.isVisible == true }
    var isPreparing: Bool {
        if case .preparing = state { return true }
        return false
    }

    var actionTitle: String {
        if case .failed = state { return StatsL10n.text("update.install.retry") }
        return StatsL10n.text("update.install.action")
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = StatsL10n.format("update.alert.title", release.version)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 460, height: 320)
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: UpdateInstallationView(controller: self))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if isPreparing { cancelled = true }
        window = nil
    }

    func cancel() {
        if isPreparing { cancelled = true }
        window?.close()
    }

    func install() {
        guard !isPreparing, !isConfirming else { return }
        isConfirming = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = StatsL10n.text("update.confirm.title")
        alert.informativeText = StatsL10n.text("update.alert.message")
        alert.addButton(withTitle: StatsL10n.text("update.install.action"))
        alert.addButton(withTitle: StatsL10n.text("update.install.confirm_cancel"))
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        isConfirming = false
        guard confirmed, isVisible else { return }
        cancelled = false
        state = .preparing
        AppUpdateInstaller().prepare(release: release) { [self] result in
            guard !cancelled else {
                state = .ready
                return
            }
            switch result {
            case let .failure(error):
                state = .failed(error.localizedDescription)
            case let .success(prepared):
                guard NoteStore.shared.flushAll() else {
                    state = .failed(StatsL10n.text("update.install.notes_unsaved"))
                    return
                }
                do {
                    try prepared.launchInstaller()
                    NSApp.terminate(nil)
                    prepared.cancelInstaller()
                    state = .failed(StatsL10n.text("update.install.termination_cancelled"))
                } catch {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

private struct UpdateInstallationView: View {
    @ObservedObject var controller: UpdateInstallationController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(StatsL10n.format("update.alert.title", controller.release.version))
                .font(.headline)
            Text(StatsL10n.text("update.notes.title"))
                .font(.subheadline.weight(.semibold))
            ScrollView {
                Group {
                    switch controller.notesState {
                    case .loading:
                        Text(StatsL10n.text("update.notes.loading"))
                            .foregroundStyle(.secondary)
                    case let .loaded(notes):
                        Text(verbatim: notes.isEmpty ? StatsL10n.text("update.notes.empty") : notes)
                            .textSelection(.enabled)
                    case .failed:
                        Text(StatsL10n.text("update.notes.failed"))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: .infinity)
            .padding(8)
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            switch controller.state {
            case .ready:
                EmptyView()
            case .preparing:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(StatsL10n.text("update.install.preparing"))
                }
            case let .failed(message):
                ScrollView {
                    Text(StatsL10n.format("update.install.failed", message))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            Spacer(minLength: 0)
            HStack {
                Button(StatsL10n.text("update.alert.download")) {
                    NSWorkspace.shared.open(controller.release.downloadURL)
                }
                Spacer()
                Button(StatsL10n.text(controller.isPreparing ? "update.install.cancel" : "update.alert.later")) {
                    controller.cancel()
                }
                Button(controller.actionTitle) {
                    controller.install()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isPreparing)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 320, alignment: .topLeading)
    }
}
