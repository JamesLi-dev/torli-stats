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
    let monitoringPauseController: MonitoringPauseController
    let store: MetricsStore
    let codexUsageStore: CodexAccountsUsageStore
    let codexActivityService: CodexCLIActivityService
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
        monitoringPauseController = MonitoringPauseController(settings: appSettings)
        store = MetricsStore(refreshInterval: appSettings.refreshInterval)
        codexUsageStore = CodexAccountsUsageStore(
            configurationsProvider: { appSettings.codexAccounts },
            refreshSettingsProvider: { appSettings.codexRefreshSettings },
            automaticRefreshPaused: monitoringPauseController.isPaused
        )
        codexActivityService = CodexCLIActivityService()
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
        updateMetricsCollectionRequirements()
        store.setMonitoringPauseState(monitoringPauseController.isPaused, message: nil)
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
                codexActivityService: codexActivityService,
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
        observeSetting(settings.$manualMonitoringPaused) { $0.monitoringPauseController.updateManualPause() }
        observeSetting(settings.$backgroundMonitoringEnabled) { $0.monitoringPauseController.updateBackgroundMonitoring() }
        observeSetting(settings.$nightMonitoringPauseEnabled) { $0.monitoringPauseController.updateSchedule() }
        observeSetting(settings.$adaptiveSamplingEnabled) { $0.monitoringPauseController.updateSchedule() }
        observeSetting(settings.$nightMonitoringPauseStartSeconds) { $0.monitoringPauseController.updateSchedule() }
        observeSetting(settings.$nightMonitoringPauseEndSeconds) { $0.monitoringPauseController.updateSchedule() }
        observeSetting(settings.$batteryRefreshInterval) { $0.applyPowerPolicy() }
        observeSetting(settings.$lowBatterySavingEnabled) { $0.applyPowerPolicy() }
        observeSetting(settings.$lowBatteryThreshold) { $0.applyPowerPolicy() }
        observeSetting(settings.$sensorHelperEnabled) { $0.store.setSensorHelperEnabled($0.settings.sensorHelperEnabled) }
        observeSetting(settings.$showGPUCard) { app in
            app.store.setGPUMonitoringEnabled(app.settings.showGPUCard)
            app.updateMetricsCollectionRequirements()
            app.updatePopoverSize()
        }
        observeSetting(settings.$typingStatsEnabled) { app in
            app.typingStats.setEnabled(app.settings.typingStatsEnabled)
            app.updateStatusTitle(app.store.statusLine)
        }

        observeSetting(settings.$showCPUCard) { app in
            app.updateMetricsCollectionRequirements()
            app.updatePopoverSize()
        }
        observeSetting(settings.$showMemoryCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showDiskCard) { app in
            app.updateMetricsCollectionRequirements()
            app.updatePopoverSize()
        }
        observeSetting(settings.$showNetworkCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showFanCard) { app in
            app.updateMetricsCollectionRequirements()
            app.updatePopoverSize()
        }
        observeSetting(settings.$showTypingCard) { $0.updatePopoverSize() }
        observeSetting(settings.$showPowerCard) { app in
            app.updateMetricsCollectionRequirements()
            app.updatePopoverSize()
        }
        observeSetting(settings.$showProcessesCard) { app in
            app.updateMetricsCollectionRequirements()
            app.updatePopoverSize()
        }
        observeSetting(settings.$showCodexCard) { app in
            app.updatePopoverSize()
            app.codexUsageStore.synchronize()
        }
        observeSetting(settings.$codexActivityTrackingEnabled) { app in
            app.codexActivityService.setEnabled(app.settings.codexActivityTrackingEnabled)
            app.updatePopoverSize()
        }
        observeSetting(settings.$showWakaTimeCard) { $0.updatePopoverSize() }
        observeSetting(settings.$dashboardDensity) { $0.updatePopoverSize() }
        observeSetting(settings.$showDashboardDeviceInfo) { $0.updatePopoverSize() }
        observeSetting(settings.$showTemperatureTags) { $0.updatePopoverSize() }
        observeSetting(settings.$showProcessPID) { $0.updatePopoverSize() }
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
        observeSetting(settings.$codexStatusBarAccountLimit) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$statusBarMetricOrder) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$systemStatusBarStyle) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$statusBarFontSize) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$showStatusBarMetricIcons) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$networkRateUnit) { $0.updateStatusTitle($0.store.statusLine) }
        observeSetting(settings.$networkRateDecimalPlaces) { $0.updateStatusTitle($0.store.statusLine) }
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

        monitoringPauseController.onSamplingModeChanged = { [weak self] mode in
            self?.applyMonitoringMode(mode)
        }
        applyMonitoringMode(monitoringPauseController.mode)
        monitoringPauseController.start()

        updateStatusBarLogo()
        typingStats.setEnabled(settings.typingStatsEnabled)
        codexActivityService.setMonitoringPaused(monitoringPauseController.isPaused)
        codexActivityService.setEnabled(settings.codexActivityTrackingEnabled)
        wakaTimeUsageStore.synchronize(isEnabled: settings.wakaTimeEnabled)
        updateStatusTitle(store.statusLine)
        if !monitoringPauseController.isPaused {
            checkForUpdatesIfNeeded()
        }
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
        settingsWindow?.backgroundColor = .clear
        LibraryWindow.shared.applyAppearance(settings.theme.windowAppearance)
        statisticsDetailsWindow?.appearance = settings.theme.windowAppearance
        statisticsDetailsWindow?.backgroundColor = AppColors.backgroundNSColor
        updateStatusTitle(store.statusLine)
    }

    private func applyMonitoringMode(_ mode: MonitoringSamplingMode) {
        let paused = mode.isPaused
        store.setMonitoringPauseState(paused, message: monitoringPauseMessage(for: mode))
        store.setAdaptiveLowFrequency(mode == .lowFrequency)
        // External requests and input monitoring pause only for hard-stop
        // states. Idle low-frequency mode affects local metric sampling only.
        codexUsageStore.setAutomaticRefreshPaused(paused)
        codexActivityService.setMonitoringPaused(paused)
        wakaTimeUsageStore.setAutomaticRefreshPaused(paused)
        typingStats.setMonitoringPaused(paused)
        statusLogoAnimator?.setPaused(mode != .realtime)
        updateStatusTitle(store.statusLine)
        if !paused {
            checkForUpdatesIfNeeded()
        }
    }

    private func monitoringPauseMessage(for mode: MonitoringSamplingMode) -> String? {
        guard case let .paused(reason) = mode else { return nil }
        switch reason {
        case .manual:
            return StatsL10n.text("monitoring.pause_resume.manual")
        case .dashboardClosed:
            return StatsL10n.text("monitoring.pause_resume.dashboard_closed")
        case .nightSchedule:
            let seconds = settings.nightMonitoringPauseEndSeconds
            return StatsL10n.format("monitoring.pause_until", seconds / 3_600, (seconds % 3_600) / 60)
        case .systemSleep:
            return StatsL10n.text("monitoring.pause_resume.system_sleep")
        case .displaySleep:
            return StatsL10n.text("monitoring.pause_resume.display_sleep")
        case .screenLocked:
            return StatsL10n.text("monitoring.pause_resume.screen_locked")
        }
    }

    private func updateMetricsCollectionRequirements() {
        store.setLowFrequencyMonitoring(
            disk: settings.showDiskCard,
            bluetooth: settings.showPowerCard,
            processes: settings.showProcessesCard,
            sensorReadings: settings.showCPUCard || settings.showGPUCard || settings.showFanCard
        )
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
