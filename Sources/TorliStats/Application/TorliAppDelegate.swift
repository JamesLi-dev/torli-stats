import AppKit
import Combine
import SwiftUI

final class TorliAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    // Shared state for the feature extensions; launch wiring stays in this file.
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var localOutsideClickMonitor: Any?
    var globalOutsideClickMonitor: Any?
    let settings: AppSettings
    let store: MetricsStore
    let codexUsageStore: CodexAccountsUsageStore
    let wakaTimeUsageStore: WakaTimeUsageStore
    var deckManager: DeckManager?
    let typingStats = TypingStatsService()
    let updateChecker = AppUpdateChecker()
    var announcedUpdateVersion: String?
    var settingsWindow: NSWindow?
    var statisticsDetailsWindow: NSWindow?
    var typingStatusUpdateWorkItem: DispatchWorkItem?
    var lastTypingStatusUpdate = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    var statusLogoAnimator: StatusBarLogoAnimator?
    var statusLogoImage: NSImage?
    private var codexSettingsUpdateWorkItem: DispatchWorkItem?
    private var pendingCodexDefaultRefresh = false
    var statusBarLayeredContentView: StatusBarLayeredContentView?
    var appliedStatusLogoConfiguration: StatusBarLogoConfiguration?

    override init() {
        let appSettings = AppSettings()
        settings = appSettings
        store = MetricsStore(refreshInterval: appSettings.refreshInterval)
        codexUsageStore = CodexAccountsUsageStore(
            configurationsProvider: { appSettings.codexAccounts },
            refreshSettingsProvider: { appSettings.codexRefreshSettings }
        )
        wakaTimeUsageStore = WakaTimeUsageStore(
            apiKeyProvider: WakaTimeKeychain.readAPIKey,
            rangeProvider: { appSettings.wakaTimeRange }
        )
        super.init()
        store.setProcessLimit(settings.processLimit)
        store.setProcessSort(settings.processSort)
        store.setPowerSavingMode(settings.powerSavingMode)
        store.setPowerPolicy(
            batteryRefreshInterval: settings.batteryRefreshInterval,
            enablesLowBatterySaving: settings.lowBatterySavingEnabled,
            lowBatteryThreshold: settings.lowBatteryThreshold
        )
        store.setSensorHelperEnabled(settings.sensorHelperEnabled)
        store.setGPUMonitoringEnabled(settings.showGPUCard)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotesAppBridge.shared.delegate = self

        if NotesSettings.notesDeckEnabled {
            startNotesDeckIfNeeded()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Torli Stats"

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(
            width: 360,
            height: min(
                DashboardView.preferredHeight(
                    for: settings,
                    codexAccountCount: codexUsageStore.accounts.filter(\.isDashboardVisible).count
                ),
                DashboardView.maximumPopoverHeight
            )
        )
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                store: store,
                settings: settings,
                codexUsageStore: codexUsageStore,
                wakaTimeUsageStore: wakaTimeUsageStore,
                typingStats: typingStats,
                onCodexDisplayCountChange: { [weak self] count in
                    self?.updatePopoverSize(codexAccountCount: count)
                },
                onTypingDetails: { [weak self] in
                    self?.showStatisticsDetails(initialTab: .typing)
                },
                onWakaTimeDetails: { [weak self] in
                    self?.showStatisticsDetails(initialTab: .development)
                }
            )
        )
        updatePopoverSize()

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateStatusBarLogoSpeed()
                self.updateStatusTitle(self.store.statusLine)
            }
            .store(in: &cancellables)

        // Each setting owns only the work it affects. This prevents harmless
        // layout and appearance edits from restarting metric sampling, probing
        // the sensor helper, or synchronizing Codex accounts.
        observeSetting(settings.$theme) { $0.applyTheme() }

        observeSetting(settings.$refreshInterval) { $0.store.setRefreshInterval($0.settings.refreshInterval) }
        observeSetting(settings.$processLimit) { $0.store.setProcessLimit($0.settings.processLimit) }
        observeSetting(settings.$processSort) { $0.store.setProcessSort($0.settings.processSort) }
        observeSetting(settings.$powerSavingMode) { $0.store.setPowerSavingMode($0.settings.powerSavingMode) }
        observeSetting(settings.$batteryRefreshInterval) { $0.applyPowerPolicy() }
        observeSetting(settings.$lowBatterySavingEnabled) { $0.applyPowerPolicy() }
        observeSetting(settings.$lowBatteryThreshold) { $0.applyPowerPolicy() }
        observeSetting(settings.$sensorHelperEnabled) { $0.store.setSensorHelperEnabled($0.settings.sensorHelperEnabled) }
        observeSetting(settings.$showGPUCard) { app in
            app.store.setGPUMonitoringEnabled(app.settings.showGPUCard)
            app.updatePopoverSize()
        }
        observeSetting(settings.$typingStatsEnabled) { app in
            app.typingStats.setEnabled(app.settings.typingStatsEnabled)
            app.updateStatusTitle(app.store.statusLine)
        }

        observeSetting(settings.$showCPUCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showMemoryCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showDiskCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showNetworkCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showFanCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showTypingCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showPowerCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showProcessesCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showCodexCard) { app in
            app.updatePopoverSize()
            app.codexUsageStore.synchronize()
        }
        observeSetting(settings.$showWakaTimeCard) { $0.updatePopoverSize() }
        observeSetting(settings.$dashboardDensity) { $0.updatePopoverSize() }
        observeSetting(settings.$dashboardModuleOrder) { $0.updatePopoverSize() }

        observeSetting(settings.$showCPU) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$showMemory) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$showDownload) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$showUpload) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$showCodexStatusItem) { app in
            app.codexUsageStore.synchronize()
            app.updateStatusTitle(app.store.statusLine)
        }
        observeSetting(settings.$showTypingStatusItem) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$codexStatusMetric) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$codexStatusBarMode) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$statusBarMetricOrder) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$systemStatusBarStyle) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$privacyMode) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$showStatusBarLogo) { app in
            app.updateStatusBarLogo()
            app.updateStatusTitle(app.store.statusLine)
        }
        observeSetting(settings.$statusBarLogoAnimation) { $0.updateStatusBarLogo() }
        observeSetting(settings.$statusBarRunner) { $0.updateStatusBarLogo() }

        observeSetting(settings.$wakaTimeEnabled) { app in
            app.wakaTimeUsageStore.synchronize(isEnabled: app.settings.wakaTimeEnabled)
        }
        observeSetting(settings.$wakaTimeRange) { $0.wakaTimeUsageStore.refresh() }

        observeSetting(settings.$codexDefaultAccountName) { $0.scheduleCodexSettingsUpdate() }
        observeSetting(settings.$codexHomePath) { $0.scheduleCodexSettingsUpdate(refreshDefaultAccount: true) }
        observeSetting(settings.$codexAutoRefresh) { $0.codexUsageStore.synchronize() }
        observeSetting(settings.$codexRefreshInterval) { $0.codexUsageStore.synchronize() }
        observeSetting(settings.$codexManagedAccounts) { $0.codexUsageStore.synchronize() }


        wakaTimeUsageStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePopoverSize()
            }
            .store(in: &cancellables)

        typingStats.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTypingStatusUpdate()
            }
            .store(in: &cancellables)

        codexUsageStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updateStatusTitle(self.store.statusLine)
                }
            }
            .store(in: &cancellables)

        updateStatusBarLogo()
        typingStats.setEnabled(settings.typingStatsEnabled)
        wakaTimeUsageStore.synchronize(isEnabled: settings.wakaTimeEnabled)
        updateStatusTitle(store.statusLine)
        checkForUpdatesIfNeeded()
    }

    private func observeSetting<P: Publisher>(
        _ publisher: P,
        perform action: @escaping (TorliAppDelegate) -> Void
    ) where P.Failure == Never {
        publisher
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                action(self)
            }
            .store(in: &cancellables)
    }

    private func applyTheme() {
        settingsWindow?.appearance = settings.theme.windowAppearance
        settingsWindow?.backgroundColor = AppColors.backgroundNSColor
        statisticsDetailsWindow?.appearance = settings.theme.windowAppearance
        statisticsDetailsWindow?.backgroundColor = AppColors.backgroundNSColor
        updateStatusTitle(store.statusLine)
    }

    private func applyPowerPolicy() {
        store.setPowerPolicy(
            batteryRefreshInterval: settings.batteryRefreshInterval,
            enablesLowBatterySaving: settings.lowBatterySavingEnabled,
            lowBatteryThreshold: settings.lowBatteryThreshold
        )
    }

    private func scheduleCodexSettingsUpdate(refreshDefaultAccount: Bool = false) {
        pendingCodexDefaultRefresh = pendingCodexDefaultRefresh || refreshDefaultAccount
        codexSettingsUpdateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let shouldRefreshDefaultAccount = self.pendingCodexDefaultRefresh
            self.pendingCodexDefaultRefresh = false
            self.codexSettingsUpdateWorkItem = nil
            if shouldRefreshDefaultAccount {
                self.codexUsageStore.refresh(accountID: CodexAccountConfiguration.defaultAccountID)
            } else {
                self.codexUsageStore.synchronize()
            }
        }
        codexSettingsUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    deinit {
        stopOutsideClickMonitors()
    }
}
