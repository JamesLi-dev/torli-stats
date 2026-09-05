import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import IOKit.ps
import ServiceManagement
import Darwin
import TorliStatsShared

// MARK: - App entry point

/// Keeps the status text and runner in separate views. Updating a status
/// item's `image` causes AppKit to redraw the whole status-item scene; updating
/// this small image subview only invalidates the animated runner.
private final class StatusBarLayeredContentView: NSView {
    private let textImageView = NSImageView()
    private let runnerImageView = NSImageView()
    private var textImage: NSImage?
    private var runnerOriginX: CGFloat = 0
    private var runnerSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textImageView.imageScaling = .scaleNone
        runnerImageView.imageScaling = .scaleNone
        runnerImageView.contentTintColor = .labelColor
        addSubview(textImageView)
        addSubview(runnerImageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(textImage: NSImage, runnerOriginX: CGFloat, runnerImage: NSImage?) {
        self.textImage = textImage
        self.runnerOriginX = runnerOriginX
        runnerSize = runnerImage?.size ?? runnerSize
        textImageView.image = textImage
        runnerImageView.image = runnerImage
        needsLayout = true
    }

    func updateRunnerImage(_ image: NSImage?) {
        if let image { runnerSize = image.size }
        runnerImageView.image = image
        needsLayout = true
    }

    // Keep the status button responsible for mouse tracking and its action.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let textImage else { return }
        let originY = floor((bounds.height - textImage.size.height) / 2)
        textImageView.frame = NSRect(origin: NSPoint(x: 0, y: originY), size: textImage.size)
        runnerImageView.frame = NSRect(
            x: runnerOriginX,
            y: floor((bounds.height - runnerSize.height) / 2),
            width: runnerSize.width,
            height: runnerSize.height
        )
    }
}

@main
struct TorliStatsApp: App {
    @NSApplicationDelegateAdaptor(TorliAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class TorliAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private let settings: AppSettings
    private let store: MetricsStore
    private let codexUsageStore: CodexAccountsUsageStore
    private let wakaTimeUsageStore: WakaTimeUsageStore
    private var deckManager: DeckManager?
    private let typingStats = TypingStatsService()
    private let updateChecker = AppUpdateChecker()
    private var announcedUpdateVersion: String?
    private var settingsWindow: NSWindow?
    private var statisticsDetailsWindow: NSWindow?
    private var typingStatusUpdateWorkItem: DispatchWorkItem?
    private var lastTypingStatusUpdate = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var statusLogoAnimator: StatusBarLogoAnimator?
    private var statusLogoImage: NSImage?
    private var codexSettingsUpdateWorkItem: DispatchWorkItem?
    private var pendingCodexDefaultRefresh = false
    private var statusBarLayeredContentView: StatusBarLayeredContentView?
    private var appliedStatusLogoConfiguration: StatusBarLogoConfiguration?

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

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func updatePopoverSize(codexAccountCount: Int? = nil) {
        let visibleAccountCount = codexAccountCount
            ?? min(2, codexUsageStore.accounts.filter(\.isDashboardVisible).count)
        let estimatedHeight = DashboardView.preferredHeight(
            for: settings,
            codexAccountCount: visibleAccountCount
        )
        popover.contentSize = NSSize(
            width: 360,
            height: min(estimatedHeight, DashboardView.maximumPopoverHeight)
        )

        // 内容较长时将 popover 限制在可用的阅读高度，Dashboard 内部负责滚动。
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let view = self.popover.contentViewController?.view else { return }
            view.layoutSubtreeIfNeeded()
            let fittedHeight = view.fittingSize.height
            guard fittedHeight > 0 else { return }
            self.popover.contentSize = NSSize(
                width: 360,
                height: min(fittedHeight, DashboardView.maximumPopoverHeight)
            )
        }
    }

    private func updateStatusBarLogo() {
        guard let button = statusItem?.button else { return }

        let configuration = StatusBarLogoConfiguration(
            isVisible: settings.showStatusBarLogo,
            runner: settings.statusBarRunner,
            acceleratesWithCPU: settings.statusBarLogoAnimation,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        guard configuration != appliedStatusLogoConfiguration else { return }
        appliedStatusLogoConfiguration = configuration
        statusLogoAnimator = nil

        button.image = nil
        button.imagePosition = .noImage

        guard configuration.isVisible else {
            statusLogoImage = nil
            updateStatusTitle(store.statusLine)
            return
        }

        statusLogoAnimator = StatusBarLogoAnimator(
            runner: configuration.runner,
            animated: !configuration.reduceMotion,
            acceleratesWithCPU: configuration.acceleratesWithCPU,
            cpuUsage: store.cpu
        ) { [weak self] image in
            guard let self else { return }
            self.updateStatusBarRunnerImage(image)
        }
    }

    private func updateStatusBarLogoSpeed() {
        statusLogoAnimator?.setCPUUsage(store.cpu)
    }

    /// A key press updates several input-stat values. The status bar only
    /// needs a periodic aggregate refresh, rather than one expensive image
    /// composition for every published value.
    private func scheduleTypingStatusUpdate() {
        guard settings.showTypingStatusItem,
              settings.typingStatsEnabled,
              settings.statusBarMetricOrder.contains(.typing) else { return }

        // An animated runner already composites the current metric text on
        // its next frame, so a separate input-driven redraw is redundant.
        if settings.showStatusBarLogo,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }

        guard typingStatusUpdateWorkItem == nil else { return }
        let minimumInterval: TimeInterval = 0.4
        let delay = max(0, lastTypingStatusUpdate.addingTimeInterval(minimumInterval).timeIntervalSinceNow)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.typingStatusUpdateWorkItem = nil
            self.lastTypingStatusUpdate = Date()
            self.updateStatusTitle(self.store.statusLine)
        }
        typingStatusUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            startOutsideClickMonitors()
        }
    }

    private func closePopover() {
        stopOutsideClickMonitors()
        popover.performClose(nil)
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if event.window !== popoverWindow && event.window !== statusWindow {
                self.closePopover()
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    private func stopOutsideClickMonitors() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitors()
    }

    deinit {
        stopOutsideClickMonitors()
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        closePopover()

        let menu = NSMenu()
        menu.autoenablesItems = false
        // Privacy mode previously used NSMenuItem.state, which makes AppKit
        // reserve an empty state/checkmark column for every menu item. Use
        // matching symbols instead so the leading edges stay compact.
        menu.showsStateColumn = false

        let aboutItem = NSMenuItem(
            title: "关于 Torli Stats",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.image = menuSymbol("info.circle")
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "打开设置",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.image = menuSymbol("gearshape")
        menu.addItem(settingsItem)

        let notesToggleItem = NSMenuItem(
            title: NotesSettings.notesDeckEnabled ? "关闭桌面便签" : "开启桌面便签",
            action: #selector(toggleNotesDeck),
            keyEquivalent: ""
        )
        notesToggleItem.image = menuSymbol(NotesSettings.notesDeckEnabled ? "note.text" : "note.text.badge.plus")
        menu.addItem(notesToggleItem)

        if NotesSettings.notesDeckEnabled {
            let newNoteItem = NSMenuItem(title: "新建便签", action: #selector(newNote), keyEquivalent: "n")
            newNoteItem.image = menuSymbol("square.and.pencil")
            menu.addItem(newNoteItem)

            let allNotesItem = NSMenuItem(title: "全部便签", action: #selector(openAllNotes), keyEquivalent: "")
            allNotesItem.image = menuSymbol("note.text")
            menu.addItem(allNotesItem)
        }

        let noteSettingsItem = NSMenuItem(title: "便签设置…", action: #selector(openNoteSettings), keyEquivalent: "")
        noteSettingsItem.image = menuSymbol("slider.horizontal.3")
        menu.addItem(noteSettingsItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: "刷新全部数据",
            action: #selector(refreshAllData),
            keyEquivalent: "r"
        )
        refreshItem.image = menuSymbol("arrow.clockwise")
        menu.addItem(refreshItem)

        let privacyItem = NSMenuItem(
            title: "隐私展示模式",
            action: #selector(togglePrivacyMode),
            keyEquivalent: ""
        )
        privacyItem.image = menuSymbol(settings.privacyMode ? "eye.slash.fill" : "eye.slash")
        menu.addItem(privacyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 Torli Stats",
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
        store.refreshNow()
        codexUsageStore.refresh()
    }

    @objc private func togglePrivacyMode() {
        settings.privacyMode.toggle()
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let sensorStatus = settings.sensorHelperEnabled ? "已授权" : "未授权或不可用"
        let alert = NSAlert()
        alert.messageText = "Torli Stats"
        alert.informativeText = "版本 \(version)（构建 \(build)）\n架构：\(appArchitecture)\n系统：macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)\n传感器辅助进程：\(sensorStatus)"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "复制诊断信息")
        alert.addButton(withTitle: "第三方许可证")

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
        return "未知"
        #endif
    }

    private func copyDiagnosticInfo(version: String, build: String, sensorStatus: String) {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let diagnostic = """
        Torli Stats \(version) (\(build))
        架构：\(appArchitecture)
        系统：macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)
        传感器辅助进程：\(sensorStatus)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic, forType: .string)
    }

    private func startNotesDeckIfNeeded() {
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

    @objc private func toggleNotesDeck() {
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

    @objc private func openSettings() {
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

    private func showStatisticsDetails(initialTab: StatisticsDetailTab) {
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

    private func checkForUpdatesIfNeeded() {
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

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private struct StatusBarGroupContent {
        let firstLine: NSAttributedString?
        let secondLine: NSAttributedString?
    }

    private struct CodexStatusBarValue {
        let accountID: UUID
        let prefix: String
        let usedPercent: Double
        let isStale: Bool
    }

    private struct StatusBarTextLayout {
        let image: NSImage
        let runnerOriginX: CGFloat
    }

    private func updateStatusBarRunnerImage(_ image: NSImage?) {
        statusLogoImage = image
        if let statusBarLayeredContentView {
            statusBarLayeredContentView.updateRunnerImage(image)
        } else {
            // The animator can produce its first frame before the static text
            // layout is installed.
            updateStatusTitle(store.statusLine)
        }
    }

    private func updateStatusTitle(_ line: StatusLine) {
        guard let button = statusItem.button else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.minimumLineHeight = 10
        style.maximumLineHeight = 10
        let commonAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
            .baselineOffset: -4
        ]

        if let statusLogoImage,
           settings.statusBarMetricOrder.contains(.logo),
           let layout = makeStatusBarTextLayout(
               runnerSize: statusLogoImage.size,
               line: line,
               attributes: commonAttributes,
               appearance: button.effectiveAppearance
           ) {
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(string: "")

            let contentView: StatusBarLayeredContentView
            if let statusBarLayeredContentView {
                contentView = statusBarLayeredContentView
            } else {
                contentView = StatusBarLayeredContentView(frame: button.bounds)
                contentView.autoresizingMask = [.width, .height]
                button.addSubview(contentView)
                statusBarLayeredContentView = contentView
            }
            statusItem.length = ceil(layout.image.size.width)
            contentView.update(
                textImage: layout.image,
                runnerOriginX: layout.runnerOriginX,
                runnerImage: statusLogoImage
            )
        } else {
            statusBarLayeredContentView?.removeFromSuperview()
            statusBarLayeredContentView = nil
            statusItem.length = NSStatusItem.variableLength
            let groups = settings.statusBarMetricOrder.compactMap {
                normalizedStatusBarGroup(
                    statusBarGroupContent(for: $0, line: line, attributes: commonAttributes),
                    attributes: commonAttributes
                )
            }
            let firstLine = groups.compactMap(\.firstLine)
            let secondLine = groups.compactMap(\.secondLine)
            let attributedTitle = NSMutableAttributedString()

            if !firstLine.isEmpty {
                attributedTitle.append(joinStatusBarSegments(firstLine, attributes: commonAttributes, separator: "  "))
            }
            if !firstLine.isEmpty && !secondLine.isEmpty {
                attributedTitle.append(NSAttributedString(string: "\n", attributes: commonAttributes))
            }
            if !secondLine.isEmpty {
                attributedTitle.append(joinStatusBarSegments(secondLine, attributes: commonAttributes, separator: "  "))
            }
            if attributedTitle.length == 0 {
                attributedTitle.append(NSAttributedString(string: "Torli", attributes: commonAttributes))
            }
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = attributedTitle
        }

        let codexValues = codexStatusBarValues()
        if codexValues.isEmpty {
            button.toolTip = "Torli Stats"
        } else {
            let details = codexValues.map { value in
                let used = Int(min(100, max(0, value.usedPercent)).rounded())
                let remaining = 100 - used
                return "\(value.prefix) · 已使用 \(used)% · 剩余 \(remaining)%"
            }
            button.toolTip = "Torli Stats · Codex · \(details.joined(separator: "；"))"
        }
    }

    private func makeStatusBarTextLayout(
        runnerSize: NSSize,
        line: StatusLine,
        attributes: [NSAttributedString.Key: Any],
        appearance: NSAppearance
    ) -> StatusBarTextLayout? {
        var segments: [(group: StatusBarMetricGroup, content: StatusBarGroupContent?, width: CGFloat)] = []

        for group in settings.statusBarMetricOrder {
            if group == .logo {
                segments.append((group, nil, runnerSize.width))
                continue
            }
            guard let content = normalizedStatusBarGroup(
                statusBarGroupContent(for: group, line: line, attributes: attributes),
                attributes: attributes
            ) else { continue }
            let width = max(content.firstLine?.size().width ?? 0, content.secondLine?.size().width ?? 0)
            segments.append((group, content, width))
        }

        guard !segments.isEmpty else { return nil }
        // Keep status-bar groups compact while leaving a visible separation.
        let spacing: CGFloat = 8
        let totalWidth = segments.reduce(CGFloat.zero) { $0 + $1.width }
            + CGFloat(max(0, segments.count - 1)) * spacing
        guard totalWidth > 0 else { return nil }

        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: 20))
        image.lockFocus()
        var x: CGFloat = 0
        var runnerOriginX: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            for segment in segments {
                if segment.group == .logo {
                    // Leave a transparent runner-sized slot. The runner is a
                    // separate image subview and is the only element updated
                    // for animation frames.
                    runnerOriginX = x
                } else if let content = segment.content {
                    content.firstLine?.draw(at: NSPoint(x: x, y: 10))
                    content.secondLine?.draw(at: NSPoint(x: x, y: 0))
                }
                x += segment.width + spacing
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return StatusBarTextLayout(image: image, runnerOriginX: runnerOriginX)
    }

    private func statusBarGroupContent(
        for group: StatusBarMetricGroup,
        line: StatusLine,
        attributes: [NSAttributedString.Key: Any]
    ) -> StatusBarGroupContent {
        switch group {
        case .system:
            switch settings.systemStatusBarStyle {
            case .compact:
                return StatusBarGroupContent(
                    firstLine: settings.showCPU ? statusBarText("CPU\(rightAligned(line.cpu, width: 5))", attributes: attributes) : nil,
                    secondLine: settings.showMemory ? statusBarText("MEM\(rightAligned(line.memory, width: 5))", attributes: attributes) : nil
                )
            case .stacked:
                let labels = [
                    settings.showCPU ? "CPU" : nil,
                    settings.showMemory ? "MEM" : nil
                ].compactMap { $0 }
                let values = [
                    settings.showCPU ? line.cpu : nil,
                    settings.showMemory ? line.memory : nil
                ].compactMap { $0 }
                return StatusBarGroupContent(
                    firstLine: labels.isEmpty ? nil : statusBarText(leftAlignedStatusBarColumns(labels, columnWidth: 4, separator: " "), attributes: attributes),
                    secondLine: values.isEmpty ? nil : statusBarText(leftAlignedStatusBarColumns(values, columnWidth: 4, separator: " "), attributes: attributes)
                )
            }

        case .network:
            return StatusBarGroupContent(
                firstLine: settings.showUpload ? statusBarText("↑ \(rightAligned(line.upload, width: 8))", attributes: attributes) : nil,
                secondLine: settings.showDownload ? statusBarText("↓ \(rightAligned(line.download, width: 8))", attributes: attributes) : nil
            )

        case .logo:
            // Logo is composed with the two-line text groups as one image in
            // `updateStatusTitle`, allowing it to be placed at any position.
            return StatusBarGroupContent(firstLine: nil, secondLine: nil)

        case .typing:
            guard settings.showTypingStatusItem,
                  settings.typingStatsEnabled,
                  typingStats.permissionStatus == .monitoring else {
                return StatusBarGroupContent(firstLine: nil, secondLine: nil)
            }
            return StatusBarGroupContent(
                firstLine: statusBarText("输入", attributes: attributes),
                secondLine: statusBarText("\(compactTypingCount(typingStats.todayKeyCount))键", attributes: attributes)
            )

        case .codex:
            let values = codexStatusBarValues()
            guard !values.isEmpty else {
                return StatusBarGroupContent(firstLine: nil, secondLine: nil)
            }
            let labels = values.map { statusBarText($0.isStale ? "\($0.prefix)!" : $0.prefix, attributes: attributes) }
            let percentages = values.map { value in
                let used = Int(min(100, max(0, value.usedPercent)).rounded())
                let remaining = 100 - used
                let displayed = settings.codexStatusMetric == .used ? used : remaining
                return statusBarText(
                    "\(displayed)%",
                    attributes: attributes.merging([
                        .foregroundColor: value.isStale ? NSColor.systemOrange : codexStatusColor(usedPercent: value.usedPercent)
                    ]) { _, new in new }
                )
            }
            // Use the same width for each account's name and percentage
            // column. Without this, a three-character name followed by a
            // four-character value shifts the next account by one character.
            let columnWidths = zip(labels, percentages).map { label, percentage in
                max(label.string.count, percentage.string.count)
            }
            return StatusBarGroupContent(
                firstLine: joinStatusBarColumns(labels, widths: columnWidths, attributes: attributes),
                secondLine: joinStatusBarColumns(percentages, widths: columnWidths, attributes: attributes)
            )
        }
    }

    private func codexStatusBarValues() -> [CodexStatusBarValue] {
        let statusBarAccounts = codexUsageStore.accounts.filter(\.isStatusBarIncluded)
        let values = statusBarAccounts.enumerated().compactMap { index, account -> CodexStatusBarValue? in
            guard let snapshot = codexUsageStore.state(for: account.id).snapshot,
                  let primary = snapshot.primary else {
                return nil
            }
            return CodexStatusBarValue(
                accountID: account.id,
                prefix: settings.privacyMode ? "COD\(index + 1)" : snapshot.account.displayPrefix,
                usedPercent: primary.usedPercent,
                isStale: snapshot.isStale()
            )
        }

        switch settings.codexStatusBarMode {
        case .defaultAccount:
            return values.filter { $0.accountID == CodexAccountConfiguration.defaultAccountID }
        case .lowestRemaining:
            guard let lowestRemaining = values.max(by: { $0.usedPercent < $1.usedPercent }) else { return [] }
            return [CodexStatusBarValue(accountID: lowestRemaining.accountID, prefix: "COD", usedPercent: lowestRemaining.usedPercent, isStale: lowestRemaining.isStale)]
        case .eachAccount:
            return values
        }
    }

    private func statusBarText(_ value: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: value, attributes: attributes)
    }

    private func leftAlignedStatusBarColumns(
        _ values: [String],
        columnWidth: Int = 6,
        separator: String = "  "
    ) -> String {
        values.enumerated().map { index, value in
            guard index < values.count - 1 else { return value }
            return value + String(repeating: " ", count: max(1, columnWidth - value.count))
        }.joined(separator: separator)
    }

    private func normalizedStatusBarGroup(
        _ group: StatusBarGroupContent,
        attributes: [NSAttributedString.Key: Any]
    ) -> StatusBarGroupContent? {
        guard group.firstLine != nil || group.secondLine != nil else { return nil }
        let width = max(group.firstLine?.string.count ?? 0, group.secondLine?.string.count ?? 0)
        let firstLine = group.firstLine.map { segment in
            paddedStatusBarSegment(segment, width: width, attributes: attributes)
        } ?? statusBarText(String(repeating: " ", count: width), attributes: attributes)
        let secondLine = group.secondLine.map { segment in
            paddedStatusBarSegment(segment, width: width, attributes: attributes)
        } ?? statusBarText(String(repeating: " ", count: width), attributes: attributes)
        return StatusBarGroupContent(firstLine: firstLine, secondLine: secondLine)
    }

    private func paddedStatusBarSegment(
        _ segment: NSAttributedString,
        width: Int,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: segment)
        let padding = max(0, width - segment.string.count)
        if padding > 0 {
            result.append(NSAttributedString(string: String(repeating: " ", count: padding), attributes: attributes))
        }
        return result
    }

    private func joinStatusBarColumns(
        _ segments: [NSAttributedString],
        widths: [Int],
        attributes: [NSAttributedString.Key: Any],
        separator: String = "  "
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: separator, attributes: attributes))
            }
            let width = widths.indices.contains(index) ? widths[index] : segment.string.count
            result.append(paddedStatusBarSegment(segment, width: width, attributes: attributes))
        }
        return result
    }

    private func joinStatusBarSegments(
        _ segments: [NSAttributedString],
        attributes: [NSAttributedString.Key: Any],
        separator: String = "  "
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: separator, attributes: attributes))
            }
            result.append(segment)
        }
        return result
    }

    private func compactTypingCount(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : String(value)
    }

    private func codexStatusColor(usedPercent: Double) -> NSColor {
        let remaining = 100 - usedPercent
        if remaining < 20 { return .systemRed }
        if remaining <= 50 { return .systemOrange }
        return .systemGreen
    }

    private func rightAligned(_ value: String, width: Int) -> String {
        let padding = max(0, width - value.count)
        return String(repeating: " ", count: padding) + value
    }
}

// MARK: - Models

private struct StatusBarLogoConfiguration: Equatable {
    let isVisible: Bool
    let runner: StatusBarRunner
    let acceleratesWithCPU: Bool
    let reduceMotion: Bool
}

struct StatusLine {
    let cpu: String
    let memory: String
    let download: String
    let upload: String
}

enum CodexStatusMetric: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: return "剩余量"
        case .used: return "用量"
        }
    }
}

enum CodexStatusBarMode: String, CaseIterable, Identifiable {
    case defaultAccount
    case lowestRemaining
    case eachAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultAccount: return "默认账号"
        case .lowestRemaining: return "最低剩余"
        case .eachAccount: return "逐账号"
        }
    }
}

enum StatusBarMetricGroup: String, CaseIterable, Codable, Identifiable {
    case system
    case network
    case typing
    case codex
    case logo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统（CPU / 内存）"
        case .network: return "网络（下载 / 上传）"
        case .typing: return "输入统计"
        case .codex: return "Codex 使用情况"
        case .logo: return "状态栏 Logo"
        }
    }
}

enum SystemStatusBarStyle: String, CaseIterable, Identifiable {
    case compact
    case stacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .stacked: return "分栏"
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var windowAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum DashboardDensity: String, CaseIterable, Identifiable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .detailed: return "详细"
        }
    }
}

enum DashboardModule: String, CaseIterable, Codable, Identifiable {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case fan
    case typing
    case power
    case codex
    case wakatime
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .disk: return "磁盘"
        case .network: return "网络"
        case .fan: return "风扇"
        case .typing: return "输入"
        case .power: return "电源"
        case .codex: return "Codex"
        case .wakatime: return "WakaTime"
        case .processes: return "进程"
        }
    }

    var isMetric: Bool {
        switch self {
        case .cpu, .gpu, .memory, .disk, .network, .fan, .typing: return true
        case .power, .codex, .wakatime, .processes: return false
        }
    }
}

enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        }
    }
}

final class AppSettings: ObservableObject {
    static let supportedRefreshIntervals = [1, 3, 5, 10, 30]
    static let supportedCodexRefreshIntervals = [1, 5, 10, 30]

    private let defaults = UserDefaults.standard
    private var codexTextPersistenceWorkItem: DispatchWorkItem?

    @Published var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: "themePreference") }
    }
    @Published var showCPU: Bool {
        didSet { defaults.set(showCPU, forKey: "showCPU") }
    }
    @Published var showMemory: Bool {
        didSet { defaults.set(showMemory, forKey: "showMemory") }
    }
    @Published var showDownload: Bool {
        didSet { defaults.set(showDownload, forKey: "showDownload") }
    }
    @Published var showUpload: Bool {
        didSet { defaults.set(showUpload, forKey: "showUpload") }
    }
    @Published var showCPUCard: Bool {
        didSet { defaults.set(showCPUCard, forKey: "showCPUCard") }
    }
    @Published var showGPUCard: Bool {
        didSet { defaults.set(showGPUCard, forKey: "showGPUCard") }
    }
    @Published var showMemoryCard: Bool {
        didSet { defaults.set(showMemoryCard, forKey: "showMemoryCard") }
    }
    @Published var showDiskCard: Bool {
        didSet { defaults.set(showDiskCard, forKey: "showDiskCard") }
    }
    @Published var showNetworkCard: Bool {
        didSet { defaults.set(showNetworkCard, forKey: "showNetworkCard") }
    }
    @Published var showFanCard: Bool {
        didSet { defaults.set(showFanCard, forKey: "showFanCard") }
    }
    @Published var showTypingCard: Bool {
        didSet { defaults.set(showTypingCard, forKey: "showTypingCard") }
    }
    @Published var showPowerCard: Bool {
        didSet { defaults.set(showPowerCard, forKey: "showPowerCard") }
    }
    @Published var showProcessesCard: Bool {
        didSet { defaults.set(showProcessesCard, forKey: "showProcessesCard") }
    }
    @Published var showCodexCard: Bool {
        didSet { defaults.set(showCodexCard, forKey: "showCodexCard") }
    }
    @Published var showWakaTimeCard: Bool {
        didSet { defaults.set(showWakaTimeCard, forKey: "showWakaTimeCard") }
    }
    @Published var wakaTimeEnabled: Bool {
        didSet { defaults.set(wakaTimeEnabled, forKey: "wakaTimeEnabled") }
    }
    @Published var wakaTimeRange: WakaTimeRange {
        didSet { defaults.set(wakaTimeRange.rawValue, forKey: "wakaTimeRange") }
    }
    @Published var dashboardDensity: DashboardDensity {
        didSet { defaults.set(dashboardDensity.rawValue, forKey: "dashboardDensity") }
    }
    @Published var dashboardModuleOrder: [DashboardModule] {
        didSet { defaults.set(dashboardModuleOrder.map(\.rawValue), forKey: "dashboardModuleOrder") }
    }
    @Published var showCodexStatusItem: Bool {
        didSet { defaults.set(showCodexStatusItem, forKey: "showCodexStatusItem") }
    }
    @Published var showTypingStatusItem: Bool {
        didSet { defaults.set(showTypingStatusItem, forKey: "showTypingStatusItem") }
    }
    @Published var codexStatusMetric: CodexStatusMetric {
        didSet { defaults.set(codexStatusMetric.rawValue, forKey: "codexStatusMetric") }
    }
    @Published var codexStatusBarMode: CodexStatusBarMode {
        didSet { defaults.set(codexStatusBarMode.rawValue, forKey: "codexStatusBarMode") }
    }
    @Published var statusBarMetricOrder: [StatusBarMetricGroup] {
        didSet { defaults.set(statusBarMetricOrder.map(\.rawValue), forKey: "statusBarMetricOrder") }
    }
    @Published var systemStatusBarStyle: SystemStatusBarStyle {
        didSet { defaults.set(systemStatusBarStyle.rawValue, forKey: "systemStatusBarStyle") }
    }
    @Published var showStatusBarLogo: Bool {
        didSet { defaults.set(showStatusBarLogo, forKey: "showStatusBarLogo") }
    }
    @Published var statusBarLogoAnimation: Bool {
        didSet { defaults.set(statusBarLogoAnimation, forKey: "statusBarLogoAnimation") }
    }
    @Published var statusBarRunner: StatusBarRunner {
        didSet { defaults.set(statusBarRunner.rawValue, forKey: "statusBarRunner") }
    }
    @Published var privacyMode: Bool {
        didSet { defaults.set(privacyMode, forKey: "privacyMode") }
    }
    @Published var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: "automaticUpdateChecks") }
    }
    @Published var typingStatsEnabled: Bool {
        didSet { defaults.set(typingStatsEnabled, forKey: "typingStatsEnabled") }
    }
    @Published var codexDefaultAccountName: String {
        didSet { scheduleCodexTextPersistence() }
    }
    @Published var codexHomePath: String {
        didSet { scheduleCodexTextPersistence() }
    }
    @Published var codexAutoRefresh: Bool {
        didSet { defaults.set(codexAutoRefresh, forKey: "codexAutoRefresh") }
    }
    @Published var codexRefreshInterval: Int {
        didSet { defaults.set(codexRefreshInterval, forKey: "codexRefreshInterval") }
    }
    @Published var codexManagedAccounts: [CodexAccountConfiguration] {
        didSet {
            guard let data = try? JSONEncoder().encode(codexManagedAccounts) else { return }
            defaults.set(data, forKey: "codexManagedAccounts")
        }
    }
    var codexRefreshSettings: CodexRefreshSettings {
        CodexRefreshSettings(
            isEnabled: codexAutoRefresh,
            intervalMinutes: codexRefreshInterval
        )
    }

    var codexAccounts: [CodexAccountConfiguration] {
        [
            .defaultAccount(
                homePath: codexHomePath,
                displayName: resolvedCodexDisplayName(codexDefaultAccountName, fallback: "默认账号"),
                isDashboardVisible: showCodexCard,
                isStatusBarIncluded: showCodexStatusItem
            )
        ] + codexManagedAccounts
    }
    @Published var refreshInterval: Int {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval") }
    }
    @Published var powerSavingMode: Bool {
        didSet { defaults.set(powerSavingMode, forKey: "powerSavingMode") }
    }
    @Published var batteryRefreshInterval: Int {
        didSet { defaults.set(batteryRefreshInterval, forKey: "batteryRefreshInterval") }
    }
    @Published var lowBatterySavingEnabled: Bool {
        didSet { defaults.set(lowBatterySavingEnabled, forKey: "lowBatterySavingEnabled") }
    }
    @Published var lowBatteryThreshold: Int {
        didSet { defaults.set(lowBatteryThreshold, forKey: "lowBatteryThreshold") }
    }
    @Published var processLimit: Int {
        didSet { defaults.set(processLimit, forKey: "processLimit") }
    }
    @Published var processSort: ProcessSortOption {
        didSet { defaults.set(processSort.rawValue, forKey: "processSort") }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var sensorHelperEnabled: Bool
    @Published private(set) var sensorHelperReachable: Bool
    @Published private(set) var sensorHelperChecking: Bool
    @Published private(set) var sensorFanAvailable: Bool
    @Published private(set) var sensorCPUTemperatureAvailable: Bool
    @Published private(set) var sensorGPUTemperatureAvailable: Bool
    @Published private(set) var sensorLastReadAt: Date?
    @Published private(set) var sensorHelperVersion: String?
    @Published private(set) var sensorProtocolVersion: Int?
    @Published private(set) var sensorSignatureMessage: String?
    @Published private(set) var sensorFanReason: String
    @Published private(set) var sensorCPUTemperatureReason: String
    @Published private(set) var sensorGPUTemperatureReason: String
    @Published private(set) var sensorOperationDiagnostic: String?
    @Published private(set) var sensorHelperMessage: String?
    private let sensorClient = SensorClient()

    init() {
        theme = ThemePreference(rawValue: defaults.string(forKey: "themePreference") ?? "") ?? .system
        showCPU = defaults.object(forKey: "showCPU") as? Bool ?? true
        showMemory = defaults.object(forKey: "showMemory") as? Bool ?? true
        showDownload = defaults.object(forKey: "showDownload") as? Bool ?? true
        showUpload = defaults.object(forKey: "showUpload") as? Bool ?? true
        showCPUCard = defaults.object(forKey: "showCPUCard") as? Bool ?? true
        showGPUCard = defaults.object(forKey: "showGPUCard") as? Bool ?? true
        showMemoryCard = defaults.object(forKey: "showMemoryCard") as? Bool ?? true
        showDiskCard = defaults.object(forKey: "showDiskCard") as? Bool ?? true
        showNetworkCard = defaults.object(forKey: "showNetworkCard") as? Bool ?? true
        showFanCard = defaults.object(forKey: "showFanCard") as? Bool ?? true
        showTypingCard = defaults.object(forKey: "showTypingCard") as? Bool ?? true
        showPowerCard = defaults.object(forKey: "showPowerCard") as? Bool ?? true
        showProcessesCard = defaults.object(forKey: "showProcessesCard") as? Bool ?? true
        showCodexCard = defaults.object(forKey: "showCodexCard") as? Bool ?? true
        showWakaTimeCard = defaults.object(forKey: "showWakaTimeCard") as? Bool ?? true
        wakaTimeEnabled = defaults.object(forKey: "wakaTimeEnabled") as? Bool ?? false
        wakaTimeRange = WakaTimeRange(rawValue: defaults.string(forKey: "wakaTimeRange") ?? "") ?? .last7Days
        dashboardDensity = DashboardDensity(rawValue: defaults.string(forKey: "dashboardDensity") ?? "") ?? .standard
        dashboardModuleOrder = Self.validDashboardModuleOrder(defaults.stringArray(forKey: "dashboardModuleOrder"))
        showCodexStatusItem = defaults.object(forKey: "showCodexStatusItem") as? Bool ?? true
        showTypingStatusItem = defaults.object(forKey: "showTypingStatusItem") as? Bool ?? false
        codexStatusMetric = CodexStatusMetric(rawValue: defaults.string(forKey: "codexStatusMetric") ?? "") ?? .remaining
        codexStatusBarMode = CodexStatusBarMode(rawValue: defaults.string(forKey: "codexStatusBarMode") ?? "") ?? .defaultAccount
        statusBarMetricOrder = Self.validStatusBarMetricOrder(defaults.stringArray(forKey: "statusBarMetricOrder"))
        systemStatusBarStyle = SystemStatusBarStyle(rawValue: defaults.string(forKey: "systemStatusBarStyle") ?? "") ?? .compact
        showStatusBarLogo = defaults.object(forKey: "showStatusBarLogo") as? Bool ?? true
        statusBarLogoAnimation = defaults.object(forKey: "statusBarLogoAnimation") as? Bool ?? true
        statusBarRunner = StatusBarRunner(rawValue: defaults.string(forKey: "statusBarRunner") ?? "") ?? .runCat
        privacyMode = defaults.object(forKey: "privacyMode") as? Bool ?? false
        automaticUpdateChecks = defaults.object(forKey: "automaticUpdateChecks") as? Bool ?? true
        typingStatsEnabled = defaults.object(forKey: "typingStatsEnabled") as? Bool ?? false
        codexDefaultAccountName = defaults.string(forKey: "codexDefaultAccountName") ?? "默认账号"
        codexHomePath = defaults.string(forKey: "codexHomePath") ?? ""
        codexAutoRefresh = defaults.object(forKey: "codexAutoRefresh") as? Bool ?? true
        let savedCodexRefreshInterval = defaults.integer(forKey: "codexRefreshInterval")
        codexRefreshInterval = Self.supportedCodexRefreshIntervals.contains(savedCodexRefreshInterval)
            ? savedCodexRefreshInterval
            : 5
        codexManagedAccounts = Self.loadCodexManagedAccounts(from: defaults.data(forKey: "codexManagedAccounts"))
        let savedInterval = defaults.integer(forKey: "refreshInterval")
        refreshInterval = Self.supportedRefreshIntervals.contains(savedInterval) ? savedInterval : 3
        powerSavingMode = defaults.object(forKey: "powerSavingMode") as? Bool ?? false
        let savedBatteryInterval = defaults.integer(forKey: "batteryRefreshInterval")
        batteryRefreshInterval = Self.supportedRefreshIntervals.contains(savedBatteryInterval) ? savedBatteryInterval : 10
        lowBatterySavingEnabled = defaults.object(forKey: "lowBatterySavingEnabled") as? Bool ?? true
        let savedLowBatteryThreshold = defaults.integer(forKey: "lowBatteryThreshold")
        lowBatteryThreshold = [10, 20, 30].contains(savedLowBatteryThreshold) ? savedLowBatteryThreshold : 20

        let savedLimit = defaults.integer(forKey: "processLimit")
        processLimit = [3, 5, 8, 10, 15].contains(savedLimit) ? savedLimit : 5
        processSort = ProcessSortOption(rawValue: defaults.string(forKey: "processSort") ?? "") ?? .cpu
        launchAtLogin = SMAppService.mainApp.status == .enabled
        sensorHelperEnabled = false
        sensorHelperReachable = false
        sensorHelperChecking = true
        sensorFanAvailable = false
        sensorCPUTemperatureAvailable = false
        sensorGPUTemperatureAvailable = false
        sensorLastReadAt = nil
        sensorHelperVersion = nil
        sensorProtocolVersion = nil
        sensorSignatureMessage = nil
        sensorFanReason = "尚未检测。"
        sensorCPUTemperatureReason = "尚未检测。"
        sensorGPUTemperatureReason = "尚未检测。"
        sensorOperationDiagnostic = nil
        sensorHelperMessage = nil
        probeSensorHelper()
    }

    private func scheduleCodexTextPersistence() {
        codexTextPersistenceWorkItem?.cancel()
        let displayName = codexDefaultAccountName
        let homePath = codexHomePath
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.defaults.set(displayName, forKey: "codexDefaultAccountName")
            self.defaults.set(homePath, forKey: "codexHomePath")
            self.codexTextPersistenceWorkItem = nil
        }
        codexTextPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func resolvedCodexDisplayName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func addCodexManagedAccount(named displayName: String) -> CodexAccountConfiguration? {
        let rootURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".torli-stats-codex", isDirectory: true)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "账号 \(codexManagedAccounts.count + 1)" : trimmedName
        let baseDirectoryName = codexDirectoryName(for: resolvedName)
        let directoryName = uniqueCodexDirectoryName(base: baseDirectoryName, rootURL: rootURL)
        let homeURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: homeURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: homeURL.path)
        } catch {
            return nil
        }

        let account = CodexAccountConfiguration(
            id: UUID(),
            displayName: resolvedName,
            homePath: homeURL.path,
            isDashboardVisible: true,
            isStatusBarIncluded: true
        )
        codexManagedAccounts.append(account)
        return account
    }

    private func codexDirectoryName(for displayName: String) -> String {
        let latinName = displayName
            .applyingTransform(.toLatin, reverse: false)?
            .folding(options: .diacriticInsensitive, locale: .current) ?? displayName
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = latinName.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let result = String(slug)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "account" : result
    }

    private func uniqueCodexDirectoryName(base: String, rootURL: URL) -> String {
        var candidate = base
        var index = 2
        while FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return candidate
    }

    func startCodexLogin(for account: CodexAccountConfiguration) -> Bool {
        guard account.id != CodexAccountConfiguration.defaultAccountID,
              let executable = CodexUsageClient.executableURL() else {
            return false
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("torli-stats-codex-login-\(account.id.uuidString).command")
        let script = "#!/bin/bash\nexport CODEX_HOME=\(shellQuoted(account.homePath))\n\(shellQuoted(executable.path)) login\nrm -f -- \"$0\"\n"
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Terminal", scriptURL.path]
            try task.run()
            return true
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            return false
        }
    }

    func removeCodexManagedAccount(id: UUID) {
        codexManagedAccounts.removeAll { $0.id == id }
    }

    func updateCodexManagedAccount(_ account: CodexAccountConfiguration) {
        guard let index = codexManagedAccounts.firstIndex(where: { $0.id == account.id }) else { return }
        codexManagedAccounts[index] = account
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    private static func loadCodexManagedAccounts(from data: Data?) -> [CodexAccountConfiguration] {
        guard let data,
              let accounts = try? JSONDecoder().decode([CodexAccountConfiguration].self, from: data) else {
            return []
        }
        return accounts.filter { account in
            account.id != CodexAccountConfiguration.defaultAccountID &&
                account.homePath.hasPrefix((NSHomeDirectory() as NSString).appendingPathComponent(".torli-stats-codex") + "/")
        }
    }

    func moveStatusBarMetricGroup(from sourceIndex: Int, by offset: Int) {
        let destinationIndex = sourceIndex + offset
        guard statusBarMetricOrder.indices.contains(sourceIndex),
              statusBarMetricOrder.indices.contains(destinationIndex) else {
            return
        }
        statusBarMetricOrder.swapAt(sourceIndex, destinationIndex)
    }

    func resetStatusBarMetricOrder() {
        statusBarMetricOrder = StatusBarMetricGroup.allCases
    }

    func resetDashboardModuleOrder() {
        dashboardModuleOrder = DashboardModule.allCases
    }

    private static func validDashboardModuleOrder(_ savedOrder: [String]?) -> [DashboardModule] {
        let savedModules = (savedOrder ?? []).compactMap(DashboardModule.init(rawValue:))
        let uniqueModules = savedModules.reduce(into: [DashboardModule]()) { result, module in
            if !result.contains(module) {
                result.append(module)
            }
        }
        return uniqueModules + DashboardModule.allCases.filter { !uniqueModules.contains($0) }
    }

    private static func validStatusBarMetricOrder(_ savedOrder: [String]?) -> [StatusBarMetricGroup] {
        let savedGroups = (savedOrder ?? []).compactMap(StatusBarMetricGroup.init(rawValue:))
        let uniqueGroups = savedGroups.reduce(into: [StatusBarMetricGroup]()) { result, group in
            if !result.contains(group) {
                result.append(group)
            }
        }
        return uniqueGroups + StatusBarMetricGroup.allCases.filter { !uniqueGroups.contains($0) }
    }

    func installSensorHelper() {
        runSensorHelperScript(
            named: "install-sensor-helper",
            successMessage: "辅助进程已安装，正在读取传感器。"
        ) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.probeSensorHelper()
            }
        }
    }

    func uninstallSensorHelper() {
        runSensorHelperScript(
            named: "uninstall-sensor-helper",
            successMessage: "传感器辅助进程已卸载。"
        ) { [weak self] in
            self?.sensorHelperEnabled = false
            self?.sensorHelperReachable = false
            self?.sensorFanAvailable = false
            self?.sensorCPUTemperatureAvailable = false
            self?.sensorGPUTemperatureAvailable = false
            self?.sensorLastReadAt = nil
            self?.sensorHelperVersion = nil
            self?.sensorProtocolVersion = nil
            self?.sensorSignatureMessage = nil
            self?.sensorFanReason = "辅助进程已卸载。"
            self?.sensorCPUTemperatureReason = "辅助进程已卸载。"
            self?.sensorGPUTemperatureReason = "辅助进程已卸载。"
            self?.sensorOperationDiagnostic = nil
        }
    }

    func refreshSensorStatus() {
        probeSensorHelper()
    }

    private func runSensorHelperScript(
        named name: String,
        successMessage: String,
        onSuccess: @escaping () -> Void = {}
    ) {
        guard let scriptURL = Bundle.main.url(forResource: name, withExtension: "sh") else {
            sensorHelperMessage = "找不到传感器安装脚本。"
            sensorOperationDiagnostic = "应用包中缺少 \(name).sh。请重新安装 Torli Stats。"
            return
        }

        sensorHelperChecking = true
        sensorOperationDiagnostic = nil
        sensorHelperMessage = "正在处理传感器辅助进程…"
        let scriptPath = escapeForAppleScript(scriptURL.path)
        let appPath = escapeForAppleScript(Bundle.main.bundlePath)
        let appleScript = "do shell script \"/bin/bash \" & quoted form of \"\(scriptPath)\" & \" \" & quoted form of \"\(appPath)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", appleScript]
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            do {
                try task.run()
                task.waitUntilExit()
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let diagnostic = Self.sensorOperationOutput(output, errorOutput: errorOutput)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.sensorHelperChecking = false
                    if task.terminationStatus == 0 {
                        self.sensorHelperMessage = successMessage
                        onSuccess()
                    } else {
                        self.sensorOperationDiagnostic = diagnostic ?? "osascript 以退出码 \(task.terminationStatus) 结束。"
                        self.sensorHelperMessage = "传感器辅助进程操作失败：\(Self.sensorOperationSummary(self.sensorOperationDiagnostic!))"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.sensorHelperChecking = false
                    self?.sensorOperationDiagnostic = "无法启动授权操作：\(error.localizedDescription)"
                    self?.sensorHelperMessage = "传感器辅助进程操作失败。"
                }
            }
        }
    }

    private func probeSensorHelper() {
        sensorHelperChecking = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installation = SensorHelperInstallationStatus.inspect()
            self?.sensorClient.read { [weak self] values in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let protocolIsCompatible = values.protocolVersion == SensorServiceConstants.protocolVersion
                    let helperIsVerified = values.isHelperReachable && installation.signatureIsValid && protocolIsCompatible

                    self.sensorHelperChecking = false
                    self.sensorHelperReachable = values.isHelperReachable
                    self.sensorHelperEnabled = helperIsVerified
                    self.sensorHelperVersion = values.helperVersion
                    self.sensorProtocolVersion = values.protocolVersion
                    self.sensorSignatureMessage = installation.signatureMessage
                    self.sensorFanReason = values.fanReason
                    self.sensorCPUTemperatureReason = values.cpuTemperatureReason
                    self.sensorGPUTemperatureReason = values.gpuTemperatureReason
                    self.sensorFanAvailable = helperIsVerified && values.isAvailable && values.fanRPM != nil
                    self.sensorCPUTemperatureAvailable = helperIsVerified && values.isAvailable && values.cpuTemperature != nil
                    self.sensorGPUTemperatureAvailable = helperIsVerified && values.isAvailable && values.gpuTemperature != nil

                    if helperIsVerified && values.isAvailable {
                        self.sensorLastReadAt = Date()
                        self.sensorHelperMessage = "辅助进程已运行，版本和签名验证通过。"
                    } else if !values.isHelperReachable {
                        self.sensorLastReadAt = nil
                        self.sensorHelperMessage = values.diagnosticMessage
                    } else if !protocolIsCompatible {
                        self.sensorLastReadAt = nil
                        self.sensorHelperMessage = "辅助进程版本不兼容，请重新安装。"
                    } else if !installation.signatureIsValid {
                        self.sensorLastReadAt = nil
                        self.sensorHelperMessage = installation.signatureMessage
                    } else {
                        self.sensorLastReadAt = nil
                        self.sensorHelperMessage = values.diagnosticMessage ?? "SMC 传感器当前不可用。"
                    }
                }
            }
        }
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        "Intel (x86_64)"
        #else
        "未知"
        #endif
    }

    func copySensorDiagnostics() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let helperVersion = sensorHelperVersion ?? "未读取"
        let protocolVersion = sensorProtocolVersion.map(String.init) ?? "未读取"
        let report = """
        Torli Stats 传感器诊断（不包含设备名称、序列号或账号信息）
        App 版本：\(appVersion)
        macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)
        架构：\(Self.currentArchitecture)
        辅助进程连接：\(sensorHelperEnabled ? "正常" : "不可用或未验证")
        Helper 版本：\(helperVersion)
        协议版本：\(protocolVersion)（期望 \(SensorServiceConstants.protocolVersion)）
        签名：\(sensorSignatureMessage ?? "未检测")
        风扇：\(sensorFanAvailable ? "可用" : "不可用")；\(sensorFanReason)
        CPU 温度：\(sensorCPUTemperatureAvailable ? "可用" : "不可用")；\(sensorCPUTemperatureReason)
        GPU 温度：\(sensorGPUTemperatureAvailable ? "可用" : "不可用")；\(sensorGPUTemperatureReason)
        最近成功读取：\(sensorLastReadAt?.formatted(date: .numeric, time: .standard) ?? "无")
        最近操作诊断：\(sensorOperationDiagnostic.map(Self.sanitizedSensorDiagnostic) ?? "无")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        sensorHelperMessage = "已复制脱敏传感器诊断信息。"
    }

    private static func sensorOperationOutput(_ output: Data, errorOutput: Data) -> String? {
        let combined = [output, errorOutput]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : sanitizedSensorDiagnostic(combined)
    }

    private static func sensorOperationSummary(_ diagnostic: String) -> String {
        let firstLine = diagnostic.split(whereSeparator: \.isNewline).first.map(String.init) ?? diagnostic
        return String(firstLine.prefix(100))
    }

    private static func sanitizedSensorDiagnostic(_ value: String) -> String {
        value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func resetToDefaults() {
        if launchAtLogin {
            setLaunchAtLogin(false)
        }

        [
            "themePreference", "showCPU", "showMemory", "showDownload", "showUpload",
            "showCPUCard", "showGPUCard", "showMemoryCard", "showDiskCard",
            "showNetworkCard", "showFanCard", "showTypingCard", "showPowerCard", "showProcessesCard",
            "showCodexCard", "showWakaTimeCard", "wakaTimeEnabled", "wakaTimeRange", "dashboardDensity", "dashboardModuleOrder", "showCodexStatusItem", "showTypingStatusItem", "codexStatusMetric", "codexStatusBarMode", "statusBarMetricOrder",
            "systemStatusBarStyle", "showStatusBarLogo", "statusBarLogoStyle", "statusBarLogoAnimation", "statusBarRunner", "privacyMode", "automaticUpdateChecks", "typingStatsEnabled", "codexDefaultAccountName", "codexHomePath", "codexAutoRefresh", "codexRefreshInterval", "codexManagedAccounts", "powerSavingMode", "batteryRefreshInterval", "lowBatterySavingEnabled", "lowBatteryThreshold", "processLimit", "processSort", "refreshInterval"
        ].forEach { defaults.removeObject(forKey: $0) }

        theme = .system
        showCPU = true
        showMemory = true
        showDownload = true
        showUpload = true
        showCPUCard = true
        showGPUCard = true
        showMemoryCard = true
        showDiskCard = true
        showNetworkCard = true
        showFanCard = true
        showTypingCard = true
        showPowerCard = true
        showProcessesCard = true
        showCodexCard = true
        showWakaTimeCard = true
        wakaTimeEnabled = false
        wakaTimeRange = .last7Days
        dashboardDensity = .standard
        dashboardModuleOrder = DashboardModule.allCases
        showCodexStatusItem = true
        showTypingStatusItem = false
        codexStatusMetric = .remaining
        codexStatusBarMode = .defaultAccount
        statusBarMetricOrder = StatusBarMetricGroup.allCases
        systemStatusBarStyle = .compact
        showStatusBarLogo = true
        statusBarLogoAnimation = true
        statusBarRunner = .runCat
        privacyMode = false
        automaticUpdateChecks = true
        typingStatsEnabled = false
        codexDefaultAccountName = "默认账号"
        codexHomePath = ""
        codexAutoRefresh = true
        codexRefreshInterval = 5
        codexManagedAccounts = []
        refreshInterval = 3
        powerSavingMode = false
        batteryRefreshInterval = 10
        lowBatterySavingEnabled = true
        lowBatteryThreshold = 20
        processLimit = 5
        processSort = .cpu
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            // 未打包、未签名或系统拒绝注册时保持原状态，避免界面显示错误。
            print("无法更新开机启动设置：\(error.localizedDescription)")
        }
    }
}

struct ProcessRow: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memory: Double
}

struct BatterySnapshot {
    let percentage: Double
    let health: Double?
    let cycleCount: Int?
    let adapterWatts: Int?
    let isCharging: Bool
    let powerSource: String
}

enum BluetoothDeviceKind {
    case headphones
    case keyboard
    case trackpad
    case mouse
    case gameController
    case generic

    var icon: String {
        switch self {
        case .headphones: return "headphones"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .mouse: return "computermouse"
        case .gameController: return "gamecontroller"
        case .generic: return "bluetooth"
        }
    }

    static func detect(name: String, majorType: String, minorType: String) -> Self {
        let description = "\(majorType) \(minorType) \(name)".lowercased()
        if description.contains("keyboard") || description.contains("键盘") { return .keyboard }
        if description.contains("trackpad") || description.contains("触控板") { return .trackpad }
        if description.contains("mouse") || description.contains("鼠标") { return .mouse }
        if description.contains("gamepad") || description.contains("controller") { return .gameController }
        if description.contains("headphone") || description.contains("headset") || description.contains("airpod") || description.contains("earbud") || description.contains("耳机") { return .headphones }
        return .generic
    }
}

struct BluetoothBatterySnapshot {
    let name: String
    let percentage: Double?
    let detail: String
    let kind: BluetoothDeviceKind
}

struct DeviceInfo {
    let model: String
    let cpuModel: String
    let gpuModel: String
    let gpuCores: Int?
    let memory: String
    let system: String
    var uptime: String

    static func placeholder() -> DeviceInfo {
        DeviceInfo(
            model: "Mac",
            cpuModel: "未知 CPU",
            gpuModel: "未知 GPU",
            gpuCores: nil,
            memory: "—",
            system: "macOS",
            uptime: uptimeString()
        )
    }

    static func current() -> DeviceInfo {
        let hardware = systemProfiler("SPHardwareDataType")
        let displays = systemProfiler("SPDisplaysDataType")
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            model: modelName(from: hardware),
            cpuModel: value(for: "Chip:", in: hardware)
                ?? value(for: "Processor Name:", in: hardware)
                ?? hardwareIdentifier(),
            gpuModel: value(for: "Chipset Model:", in: displays) ?? "未知 GPU",
            gpuCores: coreCount(in: displays),
            memory: formatMemory(ProcessInfo.processInfo.physicalMemory),
            system: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            uptime: uptimeString()
        )
    }

    static func uptimeString() -> String {
        var remaining = Int(ProcessInfo.processInfo.systemUptime)
        let days = remaining / 86_400
        remaining %= 86_400
        let hours = remaining / 3_600
        remaining %= 3_600
        let minutes = remaining / 60

        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        return "\(minutes)分钟"
    }

    private static func formatMemory(_ bytes: UInt64) -> String {
        // macOS 展示内存容量使用 GiB 口径，64 GiB 不应显示成 69 GB。
        String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
    }

    private static func systemProfiler(_ dataType: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = [dataType]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func value(for key: String, in output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let value = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func coreCount(in output: String) -> Int? {
        guard let value = value(for: "Total Number of Cores:", in: output) else { return nil }
        let digits = value.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func modelName(from hardware: String) -> String {
        if let model = value(for: "Model Name:", in: hardware) { return model }

        let identifier = hardwareIdentifier()
        switch identifier {
        case let value where value.hasPrefix("MacBookPro"): return "MacBook Pro"
        case let value where value.hasPrefix("MacBookAir"): return "MacBook Air"
        case let value where value.hasPrefix("Macmini"): return "Mac mini"
        case let value where value.hasPrefix("MacPro"): return "Mac Pro"
        case let value where value.hasPrefix("iMac"): return "iMac"
        default: return identifier.isEmpty ? "Mac" : identifier
        }
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return "" }
        return String(cString: value)
    }
}

// MARK: - Metrics store

private struct HighFrequencySnapshot {
    let cpu: Double
    let cpuPerCore: [Double]
    let gpu: Double
    let memory: Double
    let memoryUsed: String
    let memoryTotal: String
    let download: Double
    let upload: Double
    let cpuHistory: [Double]
    let gpuHistory: [Double]
    let memoryHistory: [Double]
    let networkDownloadHistory: [Double]
    let networkUploadHistory: [Double]
    let statusLine: StatusLine
}

private struct LowFrequencySnapshot {
    let diskUsage: Double
    let diskTotal: String
    let diskFree: String
    let battery: BatterySnapshot
    let bluetoothBatteries: [BluetoothBatterySnapshot]
    let processes: [ProcessRow]
    let deviceInfo: DeviceInfo?
}

final class MetricsStore: ObservableObject {
    // Publish one change after each completed snapshot instead of once per
    // field. This keeps SwiftUI from scheduling several redraws for one tick.
    let objectWillChange = ObservableObjectPublisher()

    private(set) var cpu = 0.0
    private(set) var cpuPerCore: [Double] = []
    private(set) var gpu = 0.0
    private(set) var memory = 0.0
    private(set) var memoryUsed = "—"
    private(set) var memoryTotal = "—"
    private(set) var diskUsage = 0.0
    private(set) var diskTotal = "—"
    private(set) var diskFree = "—"
    private(set) var download = 0.0
    private(set) var upload = 0.0
    private(set) var battery = BatterySnapshot(
        percentage: 0,
        health: nil,
        cycleCount: nil,
        adapterWatts: nil,
        isCharging: false,
        powerSource: "电池"
    )
    private(set) var deviceInfo = DeviceInfo.placeholder()
    private(set) var bluetoothBatteries: [BluetoothBatterySnapshot] = []
    private(set) var fanRPM: Int?
    private(set) var cpuTemperature: Double?
    private(set) var gpuTemperature: Double?
    private(set) var processes: [ProcessRow] = []
    private(set) var statusLine = StatusLine(
        cpu: "0%", memory: "0%", download: "0 KB/s", upload: "0 KB/s"
    )

    private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var gpuHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var memoryHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var networkDownloadHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var networkUploadHistory: [Double] = Array(repeating: 0, count: 24)

    // Sampling state is confined to background queues. UI-facing metrics are
    // only changed in apply* methods on the main queue. Keeping the high- and
    // low-frequency queues separate prevents a slow battery/Bluetooth/process
    // read from delaying CPU, GPU, or network updates.
    private let highMetricsQueue = DispatchQueue(label: "local.torli.stats.metrics.high", qos: .userInitiated)
    private let lowMetricsQueue = DispatchQueue(label: "local.torli.stats.metrics.low", qos: .utility)
    private var highTimer: DispatchSourceTimer?
    private var lowTimer: DispatchSourceTimer?
    private var cpuSampler = CPUSampler()
    private var previousNetwork: NetworkTotals?
    private var previousNetworkTime: TimeInterval?
    private var workerGPU = 0.0
    private var hasGPUSample = false
    private var gpuMonitoringEnabled = true
    private var lastGPUSampleTime: TimeInterval?
    // GPU usage is sourced from an `ioreg` subprocess. Ten seconds keeps the
    // dashboard informative while avoiding an expensive process launch on
    // every general metrics tick.
    private let gpuSampleInterval: TimeInterval = 10
    private var recentGPUSamples: [Double] = []
    private var workerCPUHistory = Array(repeating: 0.0, count: 24)
    private var workerGPUHistory = Array(repeating: 0.0, count: 24)
    private var workerMemoryHistory = Array(repeating: 0.0, count: 24)
    private var workerDownloadHistory = Array(repeating: 0.0, count: 24)
    private var workerUploadHistory = Array(repeating: 0.0, count: 24)
    private var workerIntervalSeconds = 3
    private var batteryRefreshIntervalSeconds = 10
    private var lowBatterySavingEnabled = true
    private var lowBatteryThreshold = 20
    private var isUsingBatteryPower = false
    private var batteryPercentage = 100.0
    private var processLimit = 5
    private var processSort: ProcessSortOption = .cpu
    private var powerSavingMode = false
    private var sensorHelperEnabled = false
    private var sensorPollingStopped = false
    private var deviceInfoLoaded = false
    private let sensorClient = SensorClient()
    private(set) var intervalSeconds: Int

    init(refreshInterval: Int = 3) {
        let resolvedInterval = AppSettings.supportedRefreshIntervals.contains(refreshInterval) ? refreshInterval : 3
        intervalSeconds = resolvedInterval
        workerIntervalSeconds = resolvedInterval
        startMonitoring()
    }

    func refreshNow() {
        highMetricsQueue.async { [weak self] in self?.collectHighFrequency() }
        lowMetricsQueue.async { [weak self] in self?.collectLowFrequency() }
    }

    func setRefreshInterval(_ seconds: Int) {
        guard AppSettings.supportedRefreshIntervals.contains(seconds), intervalSeconds != seconds else { return }
        intervalSeconds = seconds
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.workerIntervalSeconds = seconds
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
            self.collectHighFrequency()
        }
    }

    func setGPUMonitoringEnabled(_ enabled: Bool) {
        highMetricsQueue.async { [weak self] in
            guard let self, self.gpuMonitoringEnabled != enabled else { return }
            self.gpuMonitoringEnabled = enabled
            self.hasGPUSample = false
            self.lastGPUSampleTime = nil
            self.recentGPUSamples = []
            self.workerGPU = 0
            self.collectHighFrequency()
        }
    }

    func setPowerPolicy(
        batteryRefreshInterval: Int,
        enablesLowBatterySaving: Bool,
        lowBatteryThreshold: Int
    ) {
        guard AppSettings.supportedRefreshIntervals.contains(batteryRefreshInterval),
              [10, 20, 30].contains(lowBatteryThreshold) else { return }
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.batteryRefreshIntervalSeconds = batteryRefreshInterval
            self.lowBatterySavingEnabled = enablesLowBatterySaving
            self.lowBatteryThreshold = lowBatteryThreshold
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
        }
    }

    func setSensorHelperEnabled(_ enabled: Bool) {
        lowMetricsQueue.async { [weak self] in
            guard let self else { return }
            // AppDelegate also forwards unrelated settings changes here. Do
            // not restart a failed sensor session unless the enabled state
            // actually changed; otherwise a theme/toggle change would defeat
            // the no-retry rule for unavailable fan permissions.
            guard self.sensorHelperEnabled != enabled else { return }
            self.sensorHelperEnabled = enabled
            self.sensorPollingStopped = !enabled
            if enabled {
                self.pollSensorIfNeeded()
            } else {
                DispatchQueue.main.async {
                    self.fanRPM = nil
                    self.cpuTemperature = nil
                    self.gpuTemperature = nil
                }
            }
        }
    }

    func setProcessLimit(_ limit: Int) {
        guard [3, 5, 8, 10, 15].contains(limit) else { return }
        lowMetricsQueue.async { [weak self] in self?.processLimit = limit }
    }

    func setProcessSort(_ sort: ProcessSortOption) {
        lowMetricsQueue.async { [weak self] in self?.processSort = sort }
    }

    func setPowerSavingMode(_ enabled: Bool) {
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.powerSavingMode = enabled
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
            self.collectHighFrequency()
        }
        lowMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.powerSavingMode = enabled
            self.installLowTimer(interval: enabled ? 60 : 30)
        }
    }

    private func startMonitoring() {
        let initialInterval = TimeInterval(intervalSeconds)
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.installHighTimer(interval: self.effectiveHighRefreshInterval(fallback: initialInterval))
            self.collectHighFrequency()
        }
        lowMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.installLowTimer(interval: self.powerSavingMode ? 60 : 30)
            self.collectLowFrequency()
        }
    }

    private func installHighTimer(interval: TimeInterval) {
        highTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: highMetricsQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.collectHighFrequency() }
        timer.resume()
        highTimer = timer
    }

    private func installLowTimer(interval: TimeInterval) {
        lowTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: lowMetricsQueue)
        // Battery, Bluetooth, disk, process and sensor reads are deliberately
        // kept out of the high-frequency path.
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.collectLowFrequency() }
        timer.resume()
        lowTimer = timer
    }

    deinit {
        highTimer?.cancel()
        lowTimer?.cancel()
    }

    private func collectHighFrequency() {
        let cpuSnapshot = cpuSampler.sample()
        let now = ProcessInfo.processInfo.systemUptime
        let stableGPU: Double
        if gpuMonitoringEnabled {
            if !hasGPUSample || lastGPUSampleTime.map({ now - $0 >= gpuSampleInterval }) == true {
                let rawGPU = GPUReader.usage()
                recentGPUSamples.append(rawGPU)
                if recentGPUSamples.count > 5 { recentGPUSamples.removeFirst() }
                lastGPUSampleTime = now
            }
            stableGPU = median(recentGPUSamples)
            // IORegistry 的 GPU 利用率是瞬时采样，偶尔会出现 0/100 的尖峰。
            workerGPU = hasGPUSample ? workerGPU * 0.7 + stableGPU * 0.3 : stableGPU
            hasGPUSample = true
        } else {
            stableGPU = 0
            workerGPU = 0
        }
        let memorySnapshot = MemoryReader.snapshot()
        let memory = memorySnapshot.percentage

        let totals = NetworkReader.totals()
        let elapsed = previousNetworkTime.map { max(now - $0, 0.001) } ?? 0
        let download: Double
        let upload: Double
        if let previousNetwork, elapsed > 0 {
            download = totals.received >= previousNetwork.received
                ? Double(totals.received - previousNetwork.received) / elapsed
                : 0
            upload = totals.sent >= previousNetwork.sent
                ? Double(totals.sent - previousNetwork.sent) / elapsed
                : 0
        } else {
            download = 0
            upload = 0
        }
        previousNetwork = totals
        previousNetworkTime = now

        append(&workerCPUHistory, cpuSnapshot.total)
        append(&workerGPUHistory, workerGPU)
        append(&workerMemoryHistory, memory)
        append(&workerDownloadHistory, download)
        append(&workerUploadHistory, upload)

        let snapshot = HighFrequencySnapshot(
            cpu: cpuSnapshot.total,
            cpuPerCore: cpuSnapshot.perCore,
            gpu: workerGPU,
            memory: memory,
            memoryUsed: memorySnapshot.used,
            memoryTotal: memorySnapshot.total,
            download: download,
            upload: upload,
            cpuHistory: workerCPUHistory,
            gpuHistory: workerGPUHistory,
            memoryHistory: workerMemoryHistory,
            networkDownloadHistory: workerDownloadHistory,
            networkUploadHistory: workerUploadHistory,
            statusLine: StatusLine(
                cpu: "\(Int(cpuSnapshot.total))%",
                memory: "\(Int(memory))%",
                download: formatRate(download),
                upload: formatRate(upload)
            )
        )
        DispatchQueue.main.async { [weak self] in self?.apply(snapshot) }
    }

    private func collectLowFrequency() {
        let disk = DiskReader.snapshot()
        let battery = BatteryReader.snapshot()
        let bluetooth = BluetoothReader.snapshot()
        let processes = ProcessReader.topProcesses(limit: processLimit, sort: processSort)
        let info: DeviceInfo?
        if deviceInfoLoaded {
            info = nil
        } else {
            info = DeviceInfo.current()
            deviceInfoLoaded = true
        }

        updatePowerSource(battery)

        let snapshot = LowFrequencySnapshot(
            diskUsage: disk.usage,
            diskTotal: formatBytes(disk.total),
            diskFree: formatBytes(disk.free),
            battery: battery,
            bluetoothBatteries: bluetooth,
            processes: processes,
            deviceInfo: info
        )
        DispatchQueue.main.async { [weak self] in self?.apply(snapshot) }

        pollSensorIfNeeded()
    }

    private func updatePowerSource(_ battery: BatterySnapshot) {
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            let wasUsingBattery = self.isUsingBatteryPower
            let wasLowBattery = self.isLowBattery
            self.isUsingBatteryPower = !battery.isCharging && battery.powerSource == "电池"
            self.batteryPercentage = battery.percentage

            guard wasUsingBattery != self.isUsingBatteryPower || wasLowBattery != self.isLowBattery else { return }
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
            self.collectHighFrequency()
        }
    }

    private var isLowBattery: Bool {
        isUsingBatteryPower && batteryPercentage <= Double(lowBatteryThreshold)
    }

    private func effectiveHighRefreshInterval(fallback: TimeInterval? = nil) -> TimeInterval {
        let pluggedInInterval = fallback ?? TimeInterval(workerIntervalSeconds)
        let baseInterval = isUsingBatteryPower ? TimeInterval(batteryRefreshIntervalSeconds) : pluggedInInterval
        if lowBatterySavingEnabled && isLowBattery {
            return max(baseInterval, 30)
        }
        if powerSavingMode {
            return max(baseInterval, 10)
        }
        return baseInterval
    }

    private func pollSensorIfNeeded() {
        guard sensorHelperEnabled, !sensorPollingStopped else { return }
        sensorClient.read { [weak self] values in
            guard let self else { return }
            self.lowMetricsQueue.async {
                guard self.sensorHelperEnabled, !self.sensorPollingStopped else { return }
                // A failed helper/permission read is not transient. Do not
                // keep waking the privileged helper every low-frequency tick.
                guard values.isAvailable else {
                    self.sensorPollingStopped = true
                    return
                }

                // A missing fan key is a capability limitation, not a failed
                // helper session. Continue polling so CPU/GPU temperatures can
                // still update on machines that do not expose fan RPM.
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    if let fanRPM = values.fanRPM { self.fanRPM = fanRPM }
                    if let cpuTemperature = values.cpuTemperature { self.cpuTemperature = cpuTemperature }
                    if let gpuTemperature = values.gpuTemperature { self.gpuTemperature = gpuTemperature }
                }
            }
        }
    }

    private func apply(_ snapshot: HighFrequencySnapshot) {
        objectWillChange.send()
        cpu = snapshot.cpu
        cpuPerCore = snapshot.cpuPerCore
        gpu = snapshot.gpu
        memory = snapshot.memory
        memoryUsed = snapshot.memoryUsed
        memoryTotal = snapshot.memoryTotal
        download = snapshot.download
        upload = snapshot.upload
        cpuHistory = snapshot.cpuHistory
        gpuHistory = snapshot.gpuHistory
        memoryHistory = snapshot.memoryHistory
        networkDownloadHistory = snapshot.networkDownloadHistory
        networkUploadHistory = snapshot.networkUploadHistory
        statusLine = snapshot.statusLine
    }

    private func apply(_ snapshot: LowFrequencySnapshot) {
        objectWillChange.send()
        diskUsage = snapshot.diskUsage
        diskTotal = snapshot.diskTotal
        diskFree = snapshot.diskFree
        battery = snapshot.battery
        bluetoothBatteries = snapshot.bluetoothBatteries
        processes = snapshot.processes
        if var info = snapshot.deviceInfo {
            info.uptime = DeviceInfo.uptimeString()
            deviceInfo = info
        } else {
            deviceInfo.uptime = DeviceInfo.uptimeString()
        }
    }

    private func append(_ values: inout [Double], _ value: Double) {
        values.append(value)
        if values.count > 24 { values.removeFirst() }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private func formatRate(_ bytes: Double) -> String {
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB/s", bytes / 1024 / 1024) }
        return String(format: "%.0f KB/s", bytes / 1024)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1 { return String(format: "%.0f GB", gigabytes) }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }
}

// MARK: - System readers

private struct CPUSnapshot {
    let total: Double
    let perCore: [Double]
}

private struct CPUSampler {
    private var previous: [UInt64]?

    mutating func sample() -> CPUSnapshot {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else {
            return CPUSnapshot(total: 0, perCore: [])
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: processorInfo),
                vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        let coreCount = Int(processorCount)
        var current = Array(repeating: UInt64(0), count: coreCount * Int(CPU_STATE_MAX))
        for core in 0..<coreCount {
            let offset = core * Int(CPU_STATE_MAX)
            for state in 0..<Int(CPU_STATE_MAX) {
                current[offset + state] = UInt64(processorInfo[offset + state])
            }
        }

        // The first sample only establishes a baseline. A processor can also
        // be added/removed while the app is running, so reset in that case.
        guard let previous, previous.count == current.count else {
            self.previous = current
            return CPUSnapshot(total: 0, perCore: Array(repeating: 0, count: coreCount))
        }
        self.previous = current

        var perCore: [Double] = []
        perCore.reserveCapacity(coreCount)
        var busyTicks: UInt64 = 0
        var totalTicks: UInt64 = 0

        for core in 0..<coreCount {
            let offset = core * Int(CPU_STATE_MAX)
            let user = current[offset + Int(CPU_STATE_USER)] - previous[offset + Int(CPU_STATE_USER)]
            let system = current[offset + Int(CPU_STATE_SYSTEM)] - previous[offset + Int(CPU_STATE_SYSTEM)]
            let nice = current[offset + Int(CPU_STATE_NICE)] - previous[offset + Int(CPU_STATE_NICE)]
            let idle = current[offset + Int(CPU_STATE_IDLE)] - previous[offset + Int(CPU_STATE_IDLE)]
            let busy = user + system + nice
            let total = busy + idle
            busyTicks += busy
            totalTicks += total
            perCore.append(total > 0 ? min(100, Double(busy) / Double(total) * 100) : 0)
        }

        let overall = totalTicks > 0 ? Double(busyTicks) / Double(totalTicks) * 100 : 0
        return CPUSnapshot(total: min(100, max(0, overall)), perCore: perCore)
    }
}

private enum GPUReader {
    static func usage() -> Double {
        // macOS does not expose GPU utilization through a stable public API.
        // IORegistry gives us a useful local-only fallback on Apple Silicon and Intel Macs.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        // -d 2 does not include PerformanceStatistics on some macOS versions.
        process.arguments = ["-r", "-c", "IOAccelerator", "-d", "4"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return 0 }

            // ioreg changes whitespace around `=` between macOS versions. Parse
            // only the value immediately following the known key; extracting
            // all digits from a larger dictionary can turn an unrelated value
            // into 100%.
            let pattern = #"(Renderer Utilization %|Device Utilization %)"\s*=\s*([0-9]+(?:\.[0-9]+)?)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            var rendererValues: [Double] = []
            var deviceValues: [Double] = []

            for match in regex.matches(in: output, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: output),
                      let valueRange = Range(match.range(at: 2), in: output),
                      let value = Double(output[valueRange]) else { continue }
                if output[keyRange] == "Renderer Utilization %" {
                    rendererValues.append(value)
                } else {
                    deviceValues.append(value)
                }
            }

            // Renderer utilization tracks actual rendering work. Prefer it over
            // the device-level field, which can report 100% while the renderer
            // is idle on some Apple GPU drivers.
            let values = rendererValues.isEmpty ? deviceValues : rendererValues
            guard !values.isEmpty else { return 0 }
            let value = values.reduce(0, +) / Double(values.count)
            return min(100, max(0, value))
        } catch {
            return 0
        }
    }
}

private struct MemorySnapshot {
    let percentage: Double
    let used: String
    let total: String
}

private enum MemoryReader {
    static func snapshot() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS, totalBytes > 0 else {
            return MemorySnapshot(percentage: 0, used: "—", total: format(totalBytes))
        }

        let pageSize = UInt64(vm_page_size)
        let reclaimable = UInt64(stats.free_count + stats.inactive_count + stats.speculative_count) * pageSize
        let usedBytes = totalBytes - min(totalBytes, reclaimable)
        return MemorySnapshot(
            percentage: min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100)),
            used: format(usedBytes),
            total: format(totalBytes)
        )
    }

    private static func format(_ bytes: UInt64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
    }
}

private struct NetworkTotals {
    let received: UInt64
    let sent: UInt64
}

private enum NetworkReader {
    static func totals() -> NetworkTotals {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else {
            return NetworkTotals(received: 0, sent: 0)
        }
        defer { freeifaddrs(addressList) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = current {
            let item = interface.pointee
            let name = String(cString: item.ifa_name)
            let isIgnored = name == "lo0" || name.hasPrefix("utun") || name.hasPrefix("awdl")
            if !isIgnored, item.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = item.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(stats.ifi_ibytes)
                sent += UInt64(stats.ifi_obytes)
            }
            current = item.ifa_next
        }

        return NetworkTotals(received: received, sent: sent)
    }
}

private struct DiskSnapshot {
    let usage: Double
    let total: UInt64
    let free: UInt64
}

private enum DiskReader {
    static func snapshot() -> DiskSnapshot {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attributes[.systemSize] as? NSNumber)?.uint64Value ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
            let usage = total > 0 ? Double(total - min(total, free)) / Double(total) * 100 : 0
            return DiskSnapshot(usage: usage, total: total, free: free)
        } catch {
            return DiskSnapshot(usage: 0, total: 0, free: 0)
        }
    }
}

private struct BatteryRegistrySnapshot {
    let health: Double?
    let cycleCount: Int?
}

private enum BatteryReader {
    private static var cachedRegistry: BatteryRegistrySnapshot?
    private static var lastRegistryRead: TimeInterval = 0

    static func snapshot() -> BatterySnapshot {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let registry = registrySnapshot()

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let design = (description[kIOPSDesignCapacityKey] as? NSNumber)?.doubleValue
            let health = design.map { max(0, min(100, maximum / max($0, 1) * 100)) }
                ?? BatteryHealthReader.snapshot() ?? registry.health
            let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
            let charging = state == kIOPSACPowerValue
            return BatterySnapshot(
                percentage: maximum > 0 ? current / maximum * 100 : 0,
                health: health,
                cycleCount: registry.cycleCount,
                adapterWatts: charging ? adapterWatts() : nil,
                isCharging: charging,
                powerSource: charging ? "电源供电" : "电池"
            )
        }

        return BatterySnapshot(
            percentage: 100,
            health: nil,
            cycleCount: registry.cycleCount,
            adapterWatts: adapterWatts(),
            isCharging: true,
            powerSource: "电源供电"
        )
    }

    private static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = (details[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue,
              watts > 0 else {
            return nil
        }
        return watts
    }

    private static func registrySnapshot() -> BatteryRegistrySnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedRegistry, now - lastRegistryRead < 60 { return cachedRegistry }
        lastRegistryRead = now

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-c", "AppleSmartBattery", "-d", "2"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return cachedRegistry ?? BatteryRegistrySnapshot(health: nil, cycleCount: nil)
            }
            let design = registryValue("DesignCapacity", in: output)
            let fullCharge = registryValue("NominalChargeCapacity", in: output)
                ?? registryValue("AppleRawMaxCapacity", in: output)
            let health: Double? = if let design, let fullCharge, design > 0 {
                max(0, min(100, fullCharge / design * 100))
            } else {
                nil
            }
            let cycleCount = registryValue("CycleCount", in: output).map(Int.init)
            let snapshot = BatteryRegistrySnapshot(health: health, cycleCount: cycleCount)
            cachedRegistry = snapshot
            return snapshot
        } catch {
            return cachedRegistry ?? BatteryRegistrySnapshot(health: nil, cycleCount: nil)
        }
    }

    private static func registryValue(_ key: String, in output: String) -> Double? {
        // ioreg may change indentation and spacing around `=`. Parse the
        // key/value pair itself instead of relying on a particular line shape.
        let pattern = #"\"\#(key)\"\s*=\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output)
              ),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[range])
    }
}

private enum BatteryHealthReader {
    private static var cached: Double?
    private static var lastRead: TimeInterval = 0

    static func snapshot() -> Double? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRead < 60 { return cached }
        lastRead = now

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return cached }
            let pattern = #"Maximum Capacity:\s*([0-9]+)%"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)),
                  let range = Range(match.range(at: 1), in: output),
                  let value = Double(output[range]) else { return cached }
            cached = value
            return value
        } catch {
            return cached
        }
    }
}

private enum BluetoothReader {
    // system_profiler is relatively expensive to launch. Bluetooth battery
    // levels are intentionally cached between low-frequency refreshes.
    private static var cached: [BluetoothBatterySnapshot] = []
    private static var lastReadTime: TimeInterval = 0
    private static let cacheDuration: TimeInterval = 60

    static func snapshot() -> [BluetoothBatterySnapshot] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReadTime < cacheDuration { return cached }
        lastReadTime = now

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return cached }
            cached = parse(output)
            return cached
        } catch {
            return cached
        }
    }

    private static func parse(_ output: String) -> [BluetoothBatterySnapshot] {
        var snapshots: [BluetoothBatterySnapshot] = []
        var connectedSection = false
        var currentName: String?
        var currentConnected = false
        var majorType = ""
        var minorType = ""
        var left: Double?
        var right: Double?
        var single: Double?

        func flush() {
            guard let currentName,
                  currentConnected,
                  let level = single ?? average(left, right) else { return }

            let detail: String
            if let left, let right {
                detail = "左 \(Int(left))%  ·  右 \(Int(right))%"
            } else if let left {
                detail = "左 \(Int(left))%"
            } else if let right {
                detail = "右 \(Int(right))%"
            } else {
                detail = "电量 \(Int(level))%"
            }
            snapshots.append(BluetoothBatterySnapshot(
                name: currentName,
                percentage: level,
                detail: detail,
                kind: BluetoothDeviceKind.detect(
                    name: currentName,
                    majorType: majorType,
                    minorType: minorType
                )
            ))
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(rawLine)
            let value = raw.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            let indentation = raw.prefix { $0 == " " || $0 == "\t" }.count

            if value == "Connected:" {
                flush()
                currentName = nil
                currentConnected = false
                majorType = ""
                minorType = ""
                left = nil
                right = nil
                single = nil
                connectedSection = true
                continue
            }
            if value == "Not Connected:" {
                flush()
                currentName = nil
                currentConnected = false
                connectedSection = false
                continue
            }

            // system_profiler emits device names as an indented `Name:` line,
            // while properties such as `Battery Level:` are indented further.
            // Treat only non-property headers as device boundaries so several
            // connected devices can be collected independently.
            if indentation <= 12,
               value.hasSuffix(":"),
               !propertyPrefixes.contains(where: { value.hasPrefix($0) }) {
                flush()
                currentName = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
                currentConnected = connectedSection
                majorType = ""
                minorType = ""
                left = nil
                right = nil
                single = nil
                continue
            }

            guard currentName != nil else { continue }
            if let type = string(after: "Major Type:", in: value) {
                majorType = type
            } else if let type = string(after: "Minor Type:", in: value) {
                minorType = type
            } else if let connected = connectionValue(in: value) {
                currentConnected = connected
            } else if let level = percentage(after: "Left Battery Level:", in: value) {
                left = level
            } else if let level = percentage(after: "Right Battery Level:", in: value) {
                right = level
            } else if let level = percentage(after: "Battery Level:", in: value) {
                single = level
            }
        }
        flush()
        return snapshots
    }

    private static let propertyPrefixes = [
        "Address:", "Major Type:", "Minor Type:", "Services:", "Paired:",
        "Configured:", "Connected:", "Firmware Version:", "Battery Level:",
        "Left Battery Level:", "Right Battery Level:"
    ]

    private static func connectionValue(in value: String) -> Bool? {
        guard value.hasPrefix("Connected:") else { return nil }
        let suffix = value.dropFirst("Connected:".count)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if suffix.isEmpty { return true }
        if suffix == "yes" || suffix == "true" { return true }
        if suffix == "no" || suffix == "false" { return false }
        return nil
    }

    private static func average(_ left: Double?, _ right: Double?) -> Double? {
        switch (left, right) {
        case let (left?, right?): return (left + right) / 2
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }

    private static func string(after key: String, in value: String) -> String? {
        guard value.hasPrefix(key) else { return nil }
        return String(value.dropFirst(key.count).trimmingCharacters(in: .whitespaces))
    }

    private static func percentage(after key: String, in value: String) -> Double? {
        guard value.hasPrefix(key) else { return nil }
        let suffix = value.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return Double(suffix.replacingOccurrences(of: "%", with: ""))
    }
}

private enum FanReader {
    static func rpm() -> Int? {
        // Apple Silicon 没有公开的风扇 API；powermetrics 需要 root 权限。
        // 如果系统允许无交互读取，则解析其风扇采样，否则返回 nil。
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["-n", "1", "-i", "100"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: output + error, encoding: .utf8) ?? ""
            let pattern = #"(?i)(?:fan|fans).*?([0-9]{3,5})\s*rpm"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[range])
        } catch {
            return nil
        }
    }
}

private enum ProcessReader {
    static func topProcesses(limit: Int, sort: ProcessSortOption) -> [ProcessRow] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let rows: [ProcessRow] = output.split(separator: "\n").compactMap { (line: Substring) -> ProcessRow? in
                let fields = line.split(
                    maxSplits: 3,
                    omittingEmptySubsequences: true,
                    whereSeparator: { character in character == " " || character == "\t" }
                )
                guard fields.count == 4 else { return nil }
                guard let pid = Int32(fields[0]),
                      let cpu = Double(fields[1]),
                      let rss = Double(fields[2]) else { return nil }
                let path = String(fields[3])
                let name = URL(fileURLWithPath: path).lastPathComponent
                return ProcessRow(id: pid, name: name, cpu: cpu, memory: rss * 1024)
            }
            .filter { $0.cpu > 0 }

            return rows
                .sorted {
                    switch sort {
                    case .cpu: return $0.cpu > $1.cpu
                    case .memory: return $0.memory > $1.memory
                    }
                }
                .prefix(limit)
                .map { $0 }
        } catch {
            return []
        }
    }
}

// MARK: - Dashboard

private enum DashboardLayoutBlock: Identifiable {
    case metrics([DashboardModule])
    case module(DashboardModule)

    var id: String {
        switch self {
        case let .metrics(modules): return "metrics-\(modules.map(\.rawValue).joined(separator: "-"))"
        case let .module(module): return "module-\(module.rawValue)"
        }
    }
}

struct DashboardView: View {
    static let maximumPopoverHeight: CGFloat = 820

    @ObservedObject var store: MetricsStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var codexUsageStore: CodexAccountsUsageStore
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore
    @ObservedObject var typingStats: TypingStatsService
    let onCodexDisplayCountChange: (Int) -> Void
    let onTypingDetails: () -> Void
    let onWakaTimeDetails: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: settings.dashboardDensity == .compact ? 3 : 4) {
                DeviceInfoView(
                    info: store.deviceInfo,
                    isPrivacyMode: settings.privacyMode,
                    density: settings.dashboardDensity
                )

                ForEach(layoutBlocks) { block in
                    switch block {
                    case let .metrics(modules):
                        LazyVGrid(columns: columns, spacing: settings.dashboardDensity == .compact ? 3 : 4) {
                            ForEach(modules) { module in
                                metricCard(for: module)
                            }
                        }
                    case let .module(module):
                        moduleView(for: module)
                    }
                }
            }
            .padding(settings.dashboardDensity == .compact ? 6 : 8)
            .frame(width: 360, alignment: .top)
            .background(ThinScrollViewConfigurator(verticalInset: 12))
        }
        .frame(width: 360)
        .background(AppColors.background)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private var layoutBlocks: [DashboardLayoutBlock] {
        var blocks: [DashboardLayoutBlock] = []
        var metricBuffer: [DashboardModule] = []

        func flushMetrics() {
            guard !metricBuffer.isEmpty else { return }
            blocks.append(.metrics(metricBuffer))
            metricBuffer.removeAll()
        }

        for module in settings.dashboardModuleOrder where isModuleVisible(module) {
            if module.isMetric {
                metricBuffer.append(module)
            } else {
                flushMetrics()
                blocks.append(.module(module))
            }
        }
        flushMetrics()
        return blocks
    }

    private func isModuleVisible(_ module: DashboardModule) -> Bool {
        switch module {
        case .cpu: return settings.showCPUCard
        case .gpu: return settings.showGPUCard
        case .memory: return settings.showMemoryCard
        case .disk: return settings.showDiskCard
        case .network: return settings.showNetworkCard
        case .fan: return settings.showFanCard
        case .typing: return settings.showTypingCard && settings.typingStatsEnabled
        case .power: return settings.showPowerCard
        case .codex:
            return settings.showCodexCard && codexUsageStore.accounts.contains(where: \.isDashboardVisible)
        case .wakatime:
            return settings.showWakaTimeCard && settings.wakaTimeEnabled
        case .processes: return settings.showProcessesCard
        }
    }

    @ViewBuilder
    private func metricCard(for module: DashboardModule) -> some View {
        switch module {
        case .cpu:
            MetricCard(title: "CPU", icon: "cpu", value: "\(Int(store.cpu))%", badge: "\(store.cpuPerCore.count) 核", density: settings.dashboardDensity, valueColor: highUsageColor(store.cpu, warning: 70, critical: 90)) {
                CPUBarChart(values: store.cpuPerCore)
            } footer: {
                TemperatureTag(value: settings.sensorHelperEnabled ? store.cpuTemperature : nil)
            }
        case .gpu:
            MetricCard(title: "GPU", icon: "display", value: "\(Int(store.gpu))%", badge: store.deviceInfo.gpuCores.map { "\($0) 核" } ?? "—", density: settings.dashboardDensity) {
                Sparkline(values: store.gpuHistory, color: .orange)
            } footer: {
                HStack(spacing: 6) {
                    Text(store.deviceInfo.gpuModel)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TemperatureTag(value: settings.sensorHelperEnabled ? store.gpuTemperature : nil)
                }
            }
        case .memory:
            MetricCard(title: "内存", icon: "memorychip", value: "\(Int(store.memory))%", badge: "已使用", density: settings.dashboardDensity, valueColor: highUsageColor(store.memory, warning: 75, critical: 90)) {
                Sparkline(values: store.memoryHistory, color: .yellow)
            } footer: {
                Text("已使用 \(store.memoryUsed) / \(store.memoryTotal)")
            }
        case .disk:
            MetricCard(title: "磁盘", icon: "internaldrive", value: "\(Int(store.diskUsage))%", badge: store.diskTotal, density: settings.dashboardDensity, valueColor: highUsageColor(store.diskUsage, warning: 80, critical: 90)) {
                ProgressView(value: store.diskUsage / 100)
                    .tint(.blue)
            } footer: {
                Text("可用  \(store.diskFree)")
            }
        case .network:
            MetricCard(title: "网络", icon: "network", value: formatRate(store.download), badge: "实时", density: settings.dashboardDensity) {
                NetworkChart(download: store.networkDownloadHistory, upload: store.networkUploadHistory)
            } footer: {
                HStack(spacing: 14) {
                    Text("↑  \(formatRate(store.upload))")
                    Text("↓  \(formatRate(store.download))")
                }
            }
        case .fan:
            MetricCard(title: "风扇", icon: "fanblades.fill", value: store.fanRPM.map(String.init) ?? "—", badge: "RPM", density: settings.dashboardDensity) {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text(settings.sensorHelperEnabled
                        ? (store.fanRPM == nil ? "传感器暂不可用" : "当前转速")
                        : "需要授权读取风扇")
                }
                .foregroundStyle(.secondary)
            } footer: {
                Text(settings.sensorHelperEnabled
                    ? (store.fanRPM == nil ? "当前机型未提供 RPM" : "风扇转速")
                    : "需要授权读取风扇")
            }
        case .typing:
            MetricCard(
                title: "输入",
                icon: "keyboard",
                value: compactNumber(typingStats.todayKeyCount),
                badge: typingTrendBadge,
                density: settings.dashboardDensity,
                valueColor: typingStats.permissionStatus == .monitoring ? .primary : .secondary
            ) {
                if settings.dashboardDensity == .standard || settings.dashboardDensity == .detailed {
                    TypingTrendSparkline(records: typingStats.records(forLastDays: 7))
                }
            } footer: {
                HStack(spacing: 4) {
                    Text(typingStats.permissionStatus == .monitoring
                        ? "累计 \(compactNumber(typingStats.totalKeyCount)) · 活跃 \(formatTypingDuration(typingStats.activeSeconds))"
                        : typingStats.permissionStatus.description)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.secondary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .onTapGesture(perform: onTypingDetails)
            .help("查看输入统计趋势")
        case .power, .codex, .wakatime, .processes:
            EmptyView()
        }
    }

    @ViewBuilder
    private func moduleView(for module: DashboardModule) -> some View {
        switch module {
        case .power:
            PowerStatusView(
                battery: store.battery,
                bluetoothBatteries: store.bluetoothBatteries,
                isPrivacyMode: settings.privacyMode,
                density: settings.dashboardDensity
            )
        case .codex:
            CodexUsageView(
                store: codexUsageStore,
                isPrivacyMode: settings.privacyMode,
                density: settings.dashboardDensity,
                onDisplayCountChange: onCodexDisplayCountChange
            )
        case .wakatime:
            WakaTimeUsageView(
                store: wakaTimeUsageStore,
                range: settings.wakaTimeRange,
                density: settings.dashboardDensity,
                onDetails: onWakaTimeDetails
            )
        case .processes:
            ProcessListView(processes: store.processes, density: settings.dashboardDensity)
        case .cpu, .gpu, .memory, .disk, .network, .fan, .typing:
            EmptyView()
        }
    }

    static func preferredHeight(for settings: AppSettings, codexAccountCount: Int = 1) -> CGFloat {
        let metricCount = [
            settings.showCPUCard,
            settings.showGPUCard,
            settings.showMemoryCard,
            settings.showDiskCard,
            settings.showNetworkCard,
            settings.showFanCard,
            settings.showTypingCard && settings.typingStatsEnabled
        ].filter { $0 }.count
        let metricRows = CGFloat((metricCount + 1) / 2)

        let metricCardHeight: CGFloat
        switch settings.dashboardDensity {
        case .compact: metricCardHeight = 58
        case .standard: metricCardHeight = 100
        case .detailed: metricCardHeight = 114
        }

        var height: CGFloat = (settings.dashboardDensity == .compact ? 6 : 8) + 42 // outer padding + device information
        if metricRows > 0 {
            height += metricRows * metricCardHeight + max(0, metricRows - 1) * 4
        }
        let powerHeight: CGFloat
        let codexBaseHeight: CGFloat
        let processRowCount: Int
        switch settings.dashboardDensity {
        case .compact:
            powerHeight = 68
            codexBaseHeight = 76
            processRowCount = min(settings.processLimit, 3)
        case .standard:
            powerHeight = 92
            codexBaseHeight = 112
            processRowCount = settings.processLimit
        case .detailed:
            powerHeight = 102
            codexBaseHeight = 122
            processRowCount = settings.processLimit
        }

        if settings.showPowerCard { height += powerHeight + 4 }
        if codexAccountCount > 0 {
            height += codexBaseHeight + CGFloat(max(0, codexAccountCount - 1)) * 80 + 4
        }
        if settings.showWakaTimeCard && settings.wakaTimeEnabled {
            switch settings.dashboardDensity {
            case .compact: height += 95
            case .standard: height += 210
            case .detailed: height += 280
            }
        }
        if settings.showProcessesCard {
            height += 42 + CGFloat(processRowCount) * 18 + 4
        }

        // The popover height follows the enabled modules and process count;
        // only the minimum keeps an empty or partially loaded panel usable.
        return max(height, 160)
    }

    private func highUsageColor(_ value: Double, warning: Int, critical: Int) -> Color {
        if value >= Double(max(warning, critical)) { return .red }
        if value >= Double(min(warning, critical)) { return .orange }
        return .primary
    }

    private func formatRate(_ bytes: Double) -> String {
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB/s", bytes / 1024 / 1024) }
        return String(format: "%.0f KB/s", bytes / 1024)
    }

    private var typingTrendBadge: String {
        let speed = typingStats.keysPerMinute > 0 ? "\(typingStats.keysPerMinute) KPM" : "— KPM"
        return settings.dashboardDensity == .compact ? "今日 · \(speed)" : speed
    }

    private func compactNumber(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : String(value)
    }

    private func formatTypingDuration(_ value: TimeInterval) -> String {
        let minutes = Int(value) / 60
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分"
    }

}

struct ThinScrollViewConfigurator: NSViewRepresentable {
    var verticalInset: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        ScrollViewConfiguratorView(verticalInset: verticalInset)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ScrollViewConfiguratorView: NSView {
        private let verticalInset: CGFloat

        init(verticalInset: CGFloat) {
            self.verticalInset = verticalInset
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollView()
        }

        private func configureScrollView() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }
                scrollView.scrollerStyle = .overlay
                scrollView.scrollerInsets = NSEdgeInsets(top: self.verticalInset, left: 0, bottom: self.verticalInset, right: 0)
                scrollView.scrollerKnobStyle = .dark
                scrollView.autohidesScrollers = true
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScroller?.controlSize = .mini
                scrollView.verticalScroller?.alphaValue = 0.82
            }
        }
    }
}

struct PowerStatusView: View {
    let battery: BatterySnapshot
    let bluetoothBatteries: [BluetoothBatterySnapshot]
    let isPrivacyMode: Bool
    let density: DashboardDensity

    private let columns = [
        GridItem(.adaptive(minimum: 155), spacing: 10, alignment: .leading)
    ]

    private var batteryColor: Color {
        let percentage = battery.percentage
        if percentage <= 10 { return .red }
        if percentage <= 20 { return .orange }
        return .green
    }

    private var healthColor: Color {
        guard let health = battery.health else { return .secondary }
        if health <= 70 { return .red }
        if health <= 80 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("电源", systemImage: battery.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if density != .compact {
                    HStack(spacing: 5) {
                        PowerTag(text: battery.health.map { "健康 \(Int($0))%" } ?? "健康 —", color: healthColor)
                        PowerTag(text: battery.cycleCount.map { "循环 \($0) 次" } ?? "循环 —")
                    }
                }
            }

            if density == .compact {
                HStack(spacing: 8) {
                    CompactBluetoothBatteryRing(
                        value: battery.percentage,
                        icon: "laptopcomputer",
                        accessibilityName: "MacBook"
                    )
                    ForEach(Array(bluetoothBatteries.prefix(4).enumerated()), id: \.offset) { index, device in
                        CompactBluetoothBatteryRing(
                            value: device.percentage,
                            icon: device.kind.icon,
                            accessibilityName: isPrivacyMode ? "蓝牙设备 \(index + 1)" : device.name
                        )
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Keep every device in a flexible two-column grid. With more than
                // two Bluetooth devices, compact rings prevent a long device list.
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    BatteryRing(
                        value: battery.percentage,
                        title: "MacBook",
                        detail: battery.adapterWatts.map { "\(battery.powerSource)  \($0) W" } ?? battery.powerSource,
                        icon: "laptopcomputer",
                        color: batteryColor
                    )

                    ForEach(Array(bluetoothBatteries.enumerated()), id: \.offset) { index, device in
                        if bluetoothBatteries.count > 2 {
                            CompactBluetoothBatteryRing(
                                value: device.percentage,
                                icon: device.kind.icon,
                                accessibilityName: isPrivacyMode ? "蓝牙设备 \(index + 1)" : device.name
                            )
                        } else {
                            BatteryRing(
                                value: device.percentage,
                                title: isPrivacyMode ? "蓝牙设备 \(index + 1)" : device.name,
                                detail: device.detail,
                                icon: device.kind.icon
                            )
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

struct PowerTag: View {
    let text: String
    var color: Color = Color.primary.opacity(0.78)

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(AppColors.badge)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SensorCapabilityRow: View {
    let title: String
    let isAvailable: Bool
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isAvailable ? .green : .secondary)
            Text(title)
                .font(.caption.weight(.medium))
                .frame(width: 58, alignment: .leading)
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(reason)
    }
}

struct TemperatureTag: View {
    let value: Double?

    private var color: Color {
        guard let value else { return .secondary }
        if value >= 90 { return .red }
        if value >= 80 { return Color(red: 0.82, green: 0.22, blue: 0.04) }
        if value >= 65 { return .orange }
        return .green
    }

    var body: some View {
        Text(value.map { String(format: "温度 %.0f°C", $0) } ?? "温度 —")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(value == nil ? 0.08 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("温度")
            .accessibilityValue(value.map { String(format: "%.0f 摄氏度", $0) } ?? "不可用")
    }
}

private struct CompactBluetoothBatteryRing: View {
    let value: Double?
    let icon: String
    let accessibilityName: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                .stroke(
                    value == nil ? Color.primary.opacity(0.18) : Color.green,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .frame(width: 48, height: 48)
        .frame(maxWidth: .infinity, alignment: .center)
        .help(accessibilityName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(value.map { "\(Int($0))%" } ?? "电量不可用")
    }
}

struct BatteryRing: View {
    let value: Double?
    let title: String
    let detail: String
    let icon: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                    .stroke(value == nil ? Color.primary.opacity(0.18) : color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(value == nil ? .secondary : .primary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                        .help(title)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DeviceInfoView: View {
    let info: DeviceInfo
    let isPrivacyMode: Bool
    let density: DashboardDensity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isPrivacyMode ? "此 Mac" : info.model)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(info.system)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.badge)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Spacer(minLength: 0)
                }
                if density != .compact {
                    HStack(spacing: 6) {
                        InfoTag(text: "CPU  \(displayCPUModel)")
                        InfoTag(text: "内存  \(info.memory)")
                    }
                }
            }

            Spacer()

            if density != .compact {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("运行时间")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(info.uptime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var displayCPUModel: String {
        info.cpuModel.hasPrefix("Apple ") ? String(info.cpuModel.dropFirst(6)) : info.cpuModel
    }
}

private struct InfoTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(AppColors.badge)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private struct SettingsFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
            .lineLimit(1)
    }
}

private struct SettingsSubsectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StatusBarMetricGroupDropDelegate: DropDelegate {
    let target: StatusBarMetricGroup
    @Binding var groups: [StatusBarMetricGroup]
    @Binding var draggedGroup: StatusBarMetricGroup?

    func dropEntered(info: DropInfo) {
        guard let draggedGroup,
              draggedGroup != target,
              let sourceIndex = groups.firstIndex(of: draggedGroup),
              let destinationIndex = groups.firstIndex(of: target) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            groups.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedGroup = nil
        return true
    }
}

private struct DashboardModuleDropDelegate: DropDelegate {
    let target: DashboardModule
    @Binding var modules: [DashboardModule]
    @Binding var draggedModule: DashboardModule?

    func dropEntered(info: DropInfo) {
        guard let draggedModule,
              draggedModule != target,
              let sourceIndex = modules.firstIndex(of: draggedModule),
              let destinationIndex = modules.firstIndex(of: target) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            modules.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModule = nil
        return true
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var codexUsageStore: CodexAccountsUsageStore
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore
    @ObservedObject var typingStats: TypingStatsService
    @ObservedObject var updateChecker: AppUpdateChecker
    @State private var draggedStatusBarGroup: StatusBarMetricGroup?
    @State private var draggedDashboardModule: DashboardModule?
    @State private var codexAccountMessage: String?
    @State private var testingCodexAccountIDs = Set<UUID>()
    @State private var isAddingCodexAccount = false
    @State private var newCodexAccountName = ""
    @State private var wakaTimeAPIKey = ""
    @State private var hasWakaTimeAPIKey: Bool
    @State private var wakaTimeMessage: String?
    let onCodexRefresh: () -> Void
    let onWakaTimeRefresh: () -> Void
    let onRequestTypingStatsPermission: () -> Void
    let onCheckForUpdates: () -> Void

    init(
        settings: AppSettings,
        codexUsageStore: CodexAccountsUsageStore,
        wakaTimeUsageStore: WakaTimeUsageStore,
        typingStats: TypingStatsService,
        updateChecker: AppUpdateChecker,
        onCodexRefresh: @escaping () -> Void,
        onWakaTimeRefresh: @escaping () -> Void,
        onRequestTypingStatsPermission: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.settings = settings
        self.codexUsageStore = codexUsageStore
        self.wakaTimeUsageStore = wakaTimeUsageStore
        self._hasWakaTimeAPIKey = State(initialValue: WakaTimeKeychain.readAPIKey() != nil)
        self.typingStats = typingStats
        self.updateChecker = updateChecker
        self.onCodexRefresh = onCodexRefresh
        self.onWakaTimeRefresh = onWakaTimeRefresh
        self.onRequestTypingStatsPermission = onRequestTypingStatsPermission
        self.onCheckForUpdates = onCheckForUpdates
    }

    private var visibleStatusBarGroups: [StatusBarMetricGroup] {
        settings.statusBarMetricOrder.filter { group in
            switch group {
            case .system: return settings.showCPU || settings.showMemory
            case .network: return settings.showDownload || settings.showUpload
            case .typing: return settings.showTypingStatusItem && settings.typingStatsEnabled
            case .codex: return settings.showCodexStatusItem
            case .logo: return settings.showStatusBarLogo
            }
        }
    }

    private var visibleDashboardModules: [DashboardModule] {
        settings.dashboardModuleOrder.filter { module in
            switch module {
            case .cpu: return settings.showCPUCard
            case .gpu: return settings.showGPUCard
            case .memory: return settings.showMemoryCard
            case .disk: return settings.showDiskCard
            case .network: return settings.showNetworkCard
            case .fan: return settings.showFanCard
            case .typing: return settings.showTypingCard && settings.typingStatsEnabled
            case .power: return settings.showPowerCard
            case .codex: return settings.showCodexCard && codexUsageStore.accounts.contains(where: \.isDashboardVisible)
            case .wakatime: return settings.showWakaTimeCard && settings.wakaTimeEnabled
            case .processes: return settings.showProcessesCard
            }
        }
    }

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                // 外观与状态栏、系统位于左列；面板模块、监控位于右列，避免模块间出现大块空白。
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSection(title: "外观") {
                            HStack(spacing: 12) {
                                        SettingsFieldLabel("主题")
                                        Picker("", selection: $settings.theme) {
                                            ForEach(ThemePreference.allCases) { theme in
                                                Text(theme.title).tag(theme)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)
                                        .frame(width: 240)
                            }
                        }

                        SettingsSection(title: "状态栏") {
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsSubsectionTitle("菜单栏显示内容")
                                    LazyVGrid(columns: [
                                        GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)
                                    ], alignment: .leading, spacing: 10) {
                                        Toggle("CPU", isOn: $settings.showCPU)
                                        Toggle("内存", isOn: $settings.showMemory)
                                        Toggle("下载", isOn: $settings.showDownload)
                                        Toggle("上传", isOn: $settings.showUpload)
                                    }
                                    HStack(spacing: 12) {
                                        Toggle("Codex 进度", isOn: $settings.showCodexStatusItem)
                                            .frame(width: 110, alignment: .leading)
                                        Toggle("输入统计", isOn: $settings.showTypingStatusItem)
                                            .frame(width: 90, alignment: .leading)
                                        Picker("", selection: $settings.codexStatusMetric) {
                                            ForEach(CodexStatusMetric.allCases) { metric in
                                                Text(metric.title).tag(metric)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .frame(width: 90)
                                    }
                                    HStack(spacing: 12) {
                                        SettingsFieldLabel("Codex 展示")
                                        Picker("", selection: $settings.codexStatusBarMode) {
                                            ForEach(CodexStatusBarMode.allCases) { mode in
                                                Text(mode.title).tag(mode)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)
                                        .frame(width: 210)
                                    }

                                    Divider()

                                    SettingsSubsectionTitle("系统指标样式")
                                    HStack(spacing: 12) {
                                        SettingsFieldLabel("显示方式")
                                        Picker("", selection: $settings.systemStatusBarStyle) {
                                            ForEach(SystemStatusBarStyle.allCases) { style in
                                                Text(style.title).tag(style)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)
                                        .frame(width: 132)
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 14) {
                                            Toggle("显示 Logo", isOn: $settings.showStatusBarLogo)
                                                .fixedSize(horizontal: true, vertical: false)
                                            Toggle("随 CPU 加速", isOn: $settings.statusBarLogoAnimation)
                                                .toggleStyle(.switch)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .disabled(!settings.showStatusBarLogo)
                                        }
                                        HStack(spacing: 12) {
                                            SettingsFieldLabel("动画样式")
                                            Picker("", selection: $settings.statusBarRunner) {
                                                ForEach(StatusBarRunner.allCases) { runner in
                                                    Text(runner.title).tag(runner)
                                                }
                                            }
                                            .labelsHidden()
                                            .pickerStyle(.menu)
                                            .frame(width: 130)
                                            .disabled(!settings.showStatusBarLogo)
                                        }
                                    }
                                Text("关闭“随 CPU 加速”后以固定 8 FPS 播放；系统启用“减少动态效果”时自动显示静态图标。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        SettingsSection(title: "菜单栏项目顺序") {
                            VStack(alignment: .leading, spacing: 7) {
                                    Text("仅显示已启用的项目；拖动调整其状态栏顺序。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 185), alignment: .leading)],
                                        alignment: .leading,
                                        spacing: 8
                                    ) {
                                        ForEach(visibleStatusBarGroups) { group in
                                            HStack(spacing: 8) {
                                                Image(systemName: group == .logo ? "figure.run" : "line.3.horizontal")
                                                    .foregroundStyle(.secondary)
                                                    .font(.callout)
                                                Text(group.title)
                                                    .font(.callout)
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.and.down")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                            .onDrag {
                                                draggedStatusBarGroup = group
                                                return NSItemProvider(object: group.rawValue as NSString)
                                            }
                                            .onDrop(
                                                of: [UTType.text],
                                                delegate: StatusBarMetricGroupDropDelegate(
                                                    target: group,
                                                    groups: $settings.statusBarMetricOrder,
                                                    draggedGroup: $draggedStatusBarGroup
                                                )
                                            )
                                        }
                                    }

                                    Button("恢复默认顺序") {
                                        settings.resetStatusBarMetricOrder()
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                            }

                        SettingsSection(title: "监控") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Text("接电间隔")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Picker("", selection: $settings.refreshInterval) {
                                        ForEach(AppSettings.supportedRefreshIntervals, id: \.self) { interval in
                                            Text("\(interval) 秒").tag(interval)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 80)
                                    Toggle("始终省电", isOn: $settings.powerSavingMode)
                                }
                                HStack(spacing: 10) {
                                    Text("电池间隔")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Picker("", selection: $settings.batteryRefreshInterval) {
                                        ForEach(AppSettings.supportedRefreshIntervals, id: \.self) { interval in
                                            Text("\(interval) 秒").tag(interval)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 80)
                                    Toggle("低电量自动省电", isOn: $settings.lowBatterySavingEnabled)
                                }
                                if settings.lowBatterySavingEnabled {
                                    HStack(spacing: 10) {
                                        Text("低电量阈值")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                        Picker("", selection: $settings.lowBatteryThreshold) {
                                            ForEach([10, 20, 30], id: \.self) { threshold in
                                                Text("\(threshold)%").tag(threshold)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .frame(width: 80)
                                        Text("低于阈值时最慢每 30 秒刷新一次")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                HStack(spacing: 10) {
                                    Text("进程数量")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Picker("", selection: $settings.processLimit) {
                                        Text("3 个").tag(3)
                                        Text("5 个").tag(5)
                                        Text("8 个").tag(8)
                                        Text("10 个").tag(10)
                                        Text("15 个").tag(15)
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 80)
                                    Text("排序")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("", selection: $settings.processSort) {
                                        ForEach(ProcessSortOption.allCases) { option in
                                            Text(option.title).tag(option)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 80)
                                }
                            }
                        }

                    }
                    .frame(minWidth: 400, idealWidth: 444, maxWidth: .infinity, alignment: .top)

                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSection(title: "面板模块") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Text("显示密度")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Picker("", selection: $settings.dashboardDensity) {
                                        ForEach(DashboardDensity.allCases) { density in
                                            Text(density.title).tag(density)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                }

                                Divider()

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)
                                ], alignment: .leading, spacing: 10) {
                                    Toggle("CPU", isOn: $settings.showCPUCard)
                                    Toggle("GPU", isOn: $settings.showGPUCard)
                                    Toggle("内存", isOn: $settings.showMemoryCard)
                                    Toggle("磁盘", isOn: $settings.showDiskCard)
                                    Toggle("网络", isOn: $settings.showNetworkCard)
                                    Toggle("风扇", isOn: $settings.showFanCard)
                                    Toggle("输入", isOn: $settings.showTypingCard)
                                    Toggle("电源", isOn: $settings.showPowerCard)
                                    Toggle("进程", isOn: $settings.showProcessesCard)
                                    Toggle("Codex", isOn: $settings.showCodexCard)
                                    Toggle("WakaTime", isOn: $settings.showWakaTimeCard)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 7) {
                                Text("仅显示已启用的模块；拖动调整 Dashboard 顺序。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    ForEach(visibleDashboardModules) { module in
                                        HStack(spacing: 7) {
                                            Image(systemName: "line.3.horizontal")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(module.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                            Image(systemName: "arrow.up.and.down")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 3)
                                        .contentShape(Rectangle())
                                        .onDrag {
                                            draggedDashboardModule = module
                                            return NSItemProvider(object: module.rawValue as NSString)
                                        }
                                        .onDrop(
                                            of: [UTType.text],
                                            delegate: DashboardModuleDropDelegate(
                                                target: module,
                                                modules: $settings.dashboardModuleOrder,
                                                draggedModule: $draggedDashboardModule
                                            )
                                        )
                                    }
                                }

                                Button("恢复默认顺序") {
                                    settings.resetDashboardModuleOrder()
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                }
                            }
                        }

                        SettingsSection(title: "传感器") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: settings.sensorHelperEnabled ? "checkmark.shield.fill" : "exclamationmark.shield")
                                        .foregroundStyle(settings.sensorHelperEnabled ? .green : (settings.sensorHelperReachable ? .orange : .secondary))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(settings.sensorHelperEnabled ? "辅助进程运行中" : (settings.sensorHelperReachable ? "辅助进程需要重新安装" : "未授权或不可用"))
                                            .font(.callout.weight(.semibold))
                                        Text(settings.sensorHelperMessage ?? "需要管理员授权后读取风扇和温度。")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: 5) {
                                        HStack(spacing: 6) {
                                            PowerTag(text: "Helper \(settings.sensorHelperVersion ?? "—")")
                                            PowerTag(text: "协议 \(settings.sensorProtocolVersion.map(String.init) ?? "—")")
                                        }
                                        if settings.sensorHelperChecking {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                }

                                if let diagnostic = settings.sensorOperationDiagnostic {
                                    Text(diagnostic)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                        .help(diagnostic)
                                }

                                Text(settings.sensorSignatureMessage ?? "尚未验证辅助进程签名。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(minimum: 150), spacing: 10),
                                        GridItem(.flexible(minimum: 150), spacing: 10)
                                    ],
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    SensorCapabilityRow(
                                        title: "风扇",
                                        isAvailable: settings.sensorFanAvailable,
                                        reason: settings.sensorFanReason
                                    )
                                    SensorCapabilityRow(
                                        title: "CPU 温度",
                                        isAvailable: settings.sensorCPUTemperatureAvailable,
                                        reason: settings.sensorCPUTemperatureReason
                                    )
                                    SensorCapabilityRow(
                                        title: "GPU 温度",
                                        isAvailable: settings.sensorGPUTemperatureAvailable,
                                        reason: settings.sensorGPUTemperatureReason
                                    )
                                }

                                if let lastReadAt = settings.sensorLastReadAt {
                                    Text("上次成功读取：\(lastReadAt, style: .time)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 8) {
                                    Button(settings.sensorHelperReachable ? "重新安装" : "授权读取") {
                                        settings.installSensorHelper()
                                    }
                                    .disabled(settings.sensorHelperChecking)

                                    Button("重新检测") {
                                        settings.refreshSensorStatus()
                                    }
                                    .disabled(settings.sensorHelperChecking)

                                    Button("复制诊断") {
                                        settings.copySensorDiagnostics()
                                    }
                                    .disabled(settings.sensorHelperChecking)

                                    if settings.sensorHelperReachable {
                                        Button("卸载", role: .destructive) {
                                            settings.uninstallSensorHelper()
                                        }
                                        .disabled(settings.sensorHelperChecking)
                                    }
                                }
                            }
                        }

                        SettingsSection(title: "系统") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Toggle("开机启动", isOn: Binding(
                                        get: { settings.launchAtLogin },
                                        set: { settings.setLaunchAtLogin($0) }
                                    ))
                                    Spacer()
                                    Button("恢复默认设置", role: .destructive) {
                                        settings.resetToDefaults()
                                    }
                                }

                                Divider()

                                HStack(spacing: 8) {
                                    Toggle("启用输入统计", isOn: Binding(
                                        get: { settings.typingStatsEnabled },
                                        set: { enabled in
                                            settings.typingStatsEnabled = enabled
                                            if enabled {
                                                onRequestTypingStatsPermission()
                                            }
                                        }
                                    ))
                                    Text(typingStats.permissionStatus.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                                Text("仅在本机统计有效按键和输入速度；不记录输入内容、键码或应用信息。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    if typingStats.permissionStatus == .needsPermission {
                                        Button("打开输入监控设置") {
                                            typingStats.openInputMonitoringSettings()
                                        }
                                        Button("重新检测") {
                                            onRequestTypingStatsPermission()
                                        }
                                    }
                                    Button("清除输入统计", role: .destructive) {
                                        typingStats.clearHistory()
                                    }
                                    .disabled(typingStats.totalKeyCount == 0)
                                }

                                Divider()

                                HStack(spacing: 8) {
                                    Toggle("自动检查更新", isOn: $settings.automaticUpdateChecks)
                                    Spacer(minLength: 0)
                                    Button("检查更新") {
                                        onCheckForUpdates()
                                    }
                                    .disabled(updateChecker.status == .checking)
                                }
                                Text(updateChecker.status.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                    }
                    .frame(width: 360, alignment: .top)
                }
                .frame(minWidth: 776, maxWidth: .infinity, alignment: .topLeading)

                SettingsSection(title: "Codex 账号") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text("默认账号")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 64, alignment: .leading)
                                TextField("显示名称", text: $settings.codexDefaultAccountName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 260)
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 10) {
                                Text("Codex Home")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 64, alignment: .leading)
                                Text(displayCodexHomePath(defaultCodexAccount.homePath))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .help(CodexUsageClient.validate(homePath: defaultCodexAccount.homePath).resolvedPath)
                                Button("选择") {
                                    chooseCodexHome()
                                }
                                .buttonStyle(.bordered)
                                Button("测试连接") {
                                    testCodexConnection(for: defaultCodexAccount)
                                }
                                .buttonStyle(.bordered)
                                .disabled(testingCodexAccountIDs.contains(defaultCodexAccount.id))
                            }

                            HStack(spacing: 10) {
                                Color.clear.frame(width: 64)
                                CodexHomeStatusView(
                                    account: defaultCodexAccount,
                                    codexUsageStore: codexUsageStore
                                )
                            }
                        }

                        Divider()

                        HStack(spacing: 10) {
                            Text("自动刷新")
                                .font(.caption.weight(.semibold))
                                .frame(width: 64, alignment: .leading)
                            Toggle("启用 Codex 自动刷新", isOn: $settings.codexAutoRefresh)
                            Picker("", selection: $settings.codexRefreshInterval) {
                                ForEach(AppSettings.supportedCodexRefreshIntervals, id: \.self) { interval in
                                    Text("每 \(interval) 分钟").tag(interval)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .disabled(!settings.codexAutoRefresh)
                            Spacer(minLength: 0)
                        }

                        if !settings.codexManagedAccounts.isEmpty {
                            Divider()
                            Text("Torli Stats 管理的账号")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach($settings.codexManagedAccounts) { $account in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 10) {
                                        TextField("显示名称", text: $account.displayName)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 260)
                                        Spacer(minLength: 0)
                                        Toggle("面板", isOn: $account.isDashboardVisible)
                                            .toggleStyle(.checkbox)
                                        Toggle("状态栏", isOn: $account.isStatusBarIncluded)
                                            .toggleStyle(.checkbox)
                                        Button("移除", role: .destructive) {
                                            settings.removeCodexManagedAccount(id: account.id)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    HStack(spacing: 8) {
                                        Text(displayCodexHomePath(account.homePath))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .help(account.homePath)
                                        HStack(spacing: 6) {
                                            Button("测试连接") {
                                                testCodexConnection(for: account)
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(testingCodexAccountIDs.contains(account.id))
                                            Button("登录 / 重新登录") {
                                                let didStart = settings.startCodexLogin(for: account)
                                                codexAccountMessage = didStart
                                                    ? "已在终端打开 \(account.displayName) 的 Codex 登录。完成后点击“刷新全部”验证。"
                                                    : "无法启动 Codex 登录。请确认 Codex CLI 已安装。"
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        .fixedSize()
                                    }
                                    CodexHomeStatusView(
                                        account: account,
                                        codexUsageStore: codexUsageStore
                                    )
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button("添加账号") {
                                newCodexAccountName = ""
                                isAddingCodexAccount = true
                            }
                            .buttonStyle(.borderedProminent)

                            Button("刷新全部") {
                                onCodexRefresh()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(codexAccountMessage ?? "显示名称会用于 Dashboard、状态栏和提示信息；新增账号保存在 ~/.torli-stats-codex/<账号目录>，移除只删除本应用配置，不删除本地登录态。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSection(title: "WakaTime 开发统计") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("配置自己的 API Key 后才会请求 WakaTime；密钥仅保存在本机钥匙串，启用后每 30 分钟自动同步一次。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            SecureField(hasWakaTimeAPIKey ? "已保存 API Key（可输入新值替换）" : "WakaTime API Key", text: $wakaTimeAPIKey)
                                .textFieldStyle(.roundedBorder)
                            Button("保存并连接") {
                                let key = wakaTimeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else {
                                    wakaTimeMessage = "请输入 WakaTime API Key。"
                                    return
                                }
                                guard WakaTimeKeychain.saveAPIKey(key) else {
                                    wakaTimeMessage = "无法保存 API Key 到钥匙串。"
                                    return
                                }
                                wakaTimeAPIKey = ""
                                hasWakaTimeAPIKey = true
                                wakaTimeMessage = "已保存到钥匙串，正在连接。"
                                settings.showWakaTimeCard = true
                                settings.wakaTimeEnabled = true
                                onWakaTimeRefresh()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack(spacing: 10) {
                            Toggle("启用 WakaTime 统计", isOn: $settings.wakaTimeEnabled)
                                .disabled(!hasWakaTimeAPIKey)
                            Spacer(minLength: 0)
                            Button("刷新") {
                                onWakaTimeRefresh()
                            }
                            .disabled(!settings.wakaTimeEnabled)
                        }

                        HStack(spacing: 8) {
                            Text(wakaTimeMessage ?? wakaTimeUsageStore.state.statusText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            if hasWakaTimeAPIKey {
                                Button("移除 API Key", role: .destructive) {
                                    WakaTimeKeychain.deleteAPIKey()
                                    wakaTimeAPIKey = ""
                                    hasWakaTimeAPIKey = false
                                    wakaTimeMessage = "已从钥匙串移除 API Key。"
                                    settings.wakaTimeEnabled = false
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Text("更新间隔越短，数据越及时，但耗电和资源占用也会略有增加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(ThinScrollViewConfigurator())
        }
        .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isAddingCodexAccount) {
            addCodexAccountSheet
        }
        .frame(minWidth: 860, idealWidth: 860, minHeight: 680, idealHeight: 760)
        .background(AppColors.background)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private var addCodexAccountSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加 Codex 账号")
                .font(.headline)
            Text("账号将使用独立目录 ~/.torli-stats-codex/<名称>，并在终端完成一次 Codex 登录。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("账号名称，例如：个人账号", text: $newCodexAccountName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") {
                    isAddingCodexAccount = false
                }
                Button("创建并登录") {
                    guard let account = settings.addCodexManagedAccount(named: newCodexAccountName) else {
                        codexAccountMessage = "无法创建 ~/.torli-stats-codex 账号目录。"
                        isAddingCodexAccount = false
                        return
                    }
                    let didStart = settings.startCodexLogin(for: account)
                    codexAccountMessage = didStart
                        ? "已创建 \(account.displayName)，并在终端打开 Codex 登录。"
                        : "已创建 \(account.displayName)，但未找到 Codex CLI。"
                    isAddingCodexAccount = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 390)
    }

    private var defaultCodexAccount: CodexAccountConfiguration {
        settings.codexAccounts.first { $0.id == CodexAccountConfiguration.defaultAccountID }
            ?? CodexAccountConfiguration.defaultAccount(
                homePath: settings.codexHomePath,
                displayName: settings.codexDefaultAccountName,
                isDashboardVisible: settings.showCodexCard,
                isStatusBarIncluded: settings.showCodexStatusItem
            )
    }

    private func testCodexConnection(for account: CodexAccountConfiguration) {
        let validation = CodexUsageClient.validate(homePath: account.homePath)
        guard validation.isReady else {
            codexAccountMessage = "\(account.resolvedDisplayName)：\(validation.summary)。"
            return
        }

        testingCodexAccountIDs.insert(account.id)
        codexAccountMessage = "正在测试 \(account.resolvedDisplayName) 的 Codex 连接…"
        codexUsageStore.testConnection(for: account) { result in
            DispatchQueue.main.async {
                testingCodexAccountIDs.remove(account.id)
                switch result {
                case .success:
                    codexAccountMessage = "\(account.resolvedDisplayName)：连接正常，已成功读取使用情况。"
                case let .failure(error):
                    codexAccountMessage = "\(account.resolvedDisplayName)：连接失败，\(error.localizedDescription)。"
                }
            }
        }
    }

    private func displayCodexHomePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "自动：CODEX_HOME / ~/.codex" }

        let home = NSHomeDirectory()
        if trimmed == home { return "~" }
        if trimmed.hasPrefix(home + "/") {
            return "~/" + String(trimmed.dropFirst(home.count + 1))
        }
        return trimmed
    }

    private func chooseCodexHome() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex Home"
        panel.message = "请选择包含 auth.json 的 Codex Home 目录。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.codexHomePath.isEmpty ? NSHomeDirectory() : settings.codexHomePath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.codexHomePath = url.path
        }
    }
}

private struct CodexHomeStatusView: View {
    let account: CodexAccountConfiguration
    @ObservedObject var codexUsageStore: CodexAccountsUsageStore

    private var validation: CodexHomeValidation {
        CodexUsageClient.validate(homePath: account.homePath)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: validation.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(validation.isReady ? .green : .orange)
            Text(validation.summary)
            Spacer(minLength: 4)
            if let lastRefresh = codexUsageStore.lastSuccessfulRefresh(for: account.id) {
                Text("上次成功刷新：\(lastRefresh, style: .time)")
            } else {
                Text("尚未成功刷新")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help("Codex Home：\(validation.resolvedPath)")
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let cardMinHeight: CGFloat
    let content: Content

    init(title: String, cardMinHeight: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.title = title
        self.cardMinHeight = cardMinHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
            .background(AppColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricCard<Content: View, Footer: View>: View {
    let title: String
    let icon: String
    let value: String
    let badge: String
    let density: DashboardDensity
    let valueColor: Color
    let content: Content
    let footer: Footer

    init(title: String, icon: String, value: String, badge: String, density: DashboardDensity = .standard, valueColor: Color = .primary, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.value = value
        self.badge = badge
        self.density = density
        self.valueColor = valueColor
        self.content = content()
        self.footer = footer()
    }

    private var chartHeight: CGFloat {
        switch density {
        case .compact: return 0
        case .standard: return 24
        case .detailed: return 38
        }
    }

    private var minimumHeight: CGFloat {
        switch density {
        case .compact: return 58
        case .standard: return 100
        case .detailed: return 114
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 3 : 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(badge)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(AppColors.badge)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)

            if density != .compact {
                content
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .frame(height: chartHeight)

                footer
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(density == .compact ? 6 : 6)
        .frame(minHeight: minimumHeight, alignment: .top)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

struct ProcessListView: View {
    let processes: [ProcessRow]
    let density: DashboardDensity

    private var displayedProcesses: [ProcessRow] {
        switch density {
        case .compact: return Array(processes.prefix(3))
        case .standard, .detailed: return processes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("高占用进程", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(density == .detailed ? "PID     CPU          内存" : "CPU          内存")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if processes.isEmpty {
                Text("正在读取进程…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedProcesses) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if density == .detailed {
                            Text(String(format: "%5d", process.id))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        Text(String(format: "%5.1f%%", process.cpu))
                            .foregroundStyle(process.cpu > 20 ? .orange : .secondary)
                            .frame(width: 62, alignment: .trailing)
                        Text(formatMemory(process.memory))
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(8)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func formatMemory(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", bytes / 1_000_000_000) }
        return String(format: "%.0f MB", bytes / 1_000_000)
    }
}

struct CPUBarChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = values.count > 16 ? 1 : 2
            let barWidth = max(1, (geometry.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: min(2, barWidth / 2))
                        .fill(Color.green.opacity(0.9))
                        .frame(width: barWidth, height: max(2, geometry.size.height * CGFloat(min(100, max(0, value)) / 100)))
                        .help("核心 \(index + 1)：\(Int(value))%")
                        .accessibilityLabel("核心 \(index + 1)")
                        .accessibilityValue("\(Int(value))%")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(values.max() ?? 1, 1)
            let minValue = values.min() ?? 0
            let range = max(maxValue - minValue, 1)

            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = geometry.size.height * (1 - CGFloat((value - minValue) / range))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct TypingTrendSparkline: View {
    let records: [TypingDailyRecord]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(records.map(\.keyCount).max() ?? 0, 1)
            let spacing: CGFloat = records.count > 10 ? 2 : 3
            let width = max(2, (geometry.size.width - spacing * CGFloat(max(records.count - 1, 0))) / CGFloat(max(records.count, 1)))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(records) { record in
                    RoundedRectangle(cornerRadius: min(2, width / 2))
                        .fill(record.keyCount == 0 ? Color.secondary.opacity(0.16) : Color.cyan.opacity(0.82))
                        .frame(width: width, height: max(2, geometry.size.height * CGFloat(record.keyCount) / CGFloat(maximum)))
                        .accessibilityLabel(record.dateID)
                        .accessibilityValue("\(record.keyCount) 键")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct NetworkChart: View {
    let download: [Double]
    let upload: [Double]

    var body: some View {
        ZStack {
            Sparkline(values: download, color: .cyan)
            Sparkline(values: upload, color: .green)
        }
    }
}

enum AppColors {
    // 同时适配系统亮色/暗色，并让背景与卡片保持轻微层次。
    static let backgroundNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.075, green: 0.070, blue: 0.060, alpha: 1)
            : NSColor(calibratedRed: 0.93, green: 0.925, blue: 0.90, alpha: 1)
    }
    static let background = Color(nsColor: backgroundNSColor)
    static let card = adaptive(
        light: NSColor(calibratedRed: 0.985, green: 0.98, blue: 0.95, alpha: 1),
        dark: NSColor(calibratedRed: 0.165, green: 0.155, blue: 0.125, alpha: 1)
    )
    static let badge = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
