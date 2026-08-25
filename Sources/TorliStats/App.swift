import AppKit
import Combine
import SwiftUI
import IOKit.ps
import ServiceManagement
import Darwin
import TorliStatsShared

// MARK: - App entry point

@main
struct TorliStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private let settings = AppSettings()
    private let store: MetricsStore
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        store = MetricsStore()
        super.init()
        store.setProcessLimit(settings.processLimit)
        store.setProcessSort(settings.processSort)
        store.setPowerSavingMode(settings.powerSavingMode)
        store.setSensorHelperEnabled(settings.sensorHelperEnabled)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Torli Stats"

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 780)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(store: store, settings: settings)
        )

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateStatusTitle(self.store.statusLine)
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.store.setProcessLimit(self.settings.processLimit)
                    self.store.setProcessSort(self.settings.processSort)
                    self.store.setPowerSavingMode(self.settings.powerSavingMode)
                    self.store.setSensorHelperEnabled(self.settings.sensorHelperEnabled)
                    self.settingsWindow?.appearance = self.settings.theme.windowAppearance
                    self.settingsWindow?.backgroundColor = AppColors.backgroundNSColor
                    self.updateStatusTitle(self.store.statusLine)
                }
            }
            .store(in: &cancellables)

        updateStatusTitle(store.statusLine)
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
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
        menu.addItem(NSMenuItem(
            title: "打开设置",
            action: #selector(openSettings),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出 Torli Stats",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = self }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY - 4),
            in: button
        )
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settings = SettingsView(
            selectedInterval: store.intervalSeconds,
            settings: self.settings,
            onChange: { [weak self] seconds in
                self?.store.setRefreshInterval(seconds)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Torli Stats 设置"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = AppColors.backgroundNSColor
        window.appearance = self.settings.theme.windowAppearance
        window.minSize = NSSize(width: 820, height: 480)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: settings)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func updateStatusTitle(_ line: StatusLine) {
        guard let button = statusItem.button else { return }

        // 根据设置拼接状态栏内容，同时保持数字列宽对齐。
        var firstLine: [String] = []
        var secondLine: [String] = []
        if settings.showCPU { firstLine.append("CPU\(rightAligned(line.cpu, width: 5))") }
        if settings.showUpload { firstLine.append("↑ \(rightAligned(line.upload, width: 8))") }
        if settings.showMemory { secondLine.append("MEM\(rightAligned(line.memory, width: 5))") }
        if settings.showDownload { secondLine.append("↓ \(rightAligned(line.download, width: 8))") }
        let text = (firstLine + secondLine).joined(separator: "\n").isEmpty
            ? "Torli"
            : ([firstLine.joined(separator: "  "), secondLine.joined(separator: "  ")] as [String])
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        let style = NSMutableParagraphStyle()
        // 两行共用紧凑的行框，不额外添加行间距。
        style.lineSpacing = 0
        style.minimumLineHeight = 10
        style.maximumLineHeight = 10

        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
                // NSStatusBarButton 默认会把多行标题放在中间，向下移动
                // 让第二行基线贴近菜单栏底部。
                .baselineOffset: -4
            ]
        )
    }

    private func rightAligned(_ value: String, width: Int) -> String {
        let padding = max(0, width - value.count)
        return String(repeating: " ", count: padding) + value
    }
}

// MARK: - Models

struct StatusLine {
    let cpu: String
    let memory: String
    let download: String
    let upload: String
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
    private let defaults = UserDefaults.standard

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
    @Published var showPowerCard: Bool {
        didSet { defaults.set(showPowerCard, forKey: "showPowerCard") }
    }
    @Published var showProcessesCard: Bool {
        didSet { defaults.set(showProcessesCard, forKey: "showProcessesCard") }
    }
    @Published var powerSavingMode: Bool {
        didSet { defaults.set(powerSavingMode, forKey: "powerSavingMode") }
    }
    @Published var processLimit: Int {
        didSet { defaults.set(processLimit, forKey: "processLimit") }
    }
    @Published var processSort: ProcessSortOption {
        didSet { defaults.set(processSort.rawValue, forKey: "processSort") }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var sensorHelperEnabled: Bool
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
        showPowerCard = defaults.object(forKey: "showPowerCard") as? Bool ?? true
        showProcessesCard = defaults.object(forKey: "showProcessesCard") as? Bool ?? true
        powerSavingMode = defaults.object(forKey: "powerSavingMode") as? Bool ?? false

        let savedLimit = defaults.integer(forKey: "processLimit")
        processLimit = [5, 8, 10, 15].contains(savedLimit) ? savedLimit : 8
        processSort = ProcessSortOption(rawValue: defaults.string(forKey: "processSort") ?? "") ?? .cpu
        launchAtLogin = SMAppService.mainApp.status == .enabled
        sensorHelperEnabled = false
        sensorHelperMessage = nil
        probeSensorHelper()
    }

    func installSensorHelper() {
        guard let scriptURL = Bundle.main.url(forResource: "install-sensor-helper", withExtension: "sh") else {
            sensorHelperMessage = "找不到传感器安装脚本。"
            return
        }

        let scriptPath = escapeForAppleScript(scriptURL.path)
        let appPath = escapeForAppleScript(Bundle.main.bundlePath)
        let appleScript = "do shell script \"/bin/bash \" & quoted form of \"\(scriptPath)\" & \" \" & quoted form of \"\(appPath)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", appleScript]
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        self?.sensorHelperMessage = "辅助进程已安装，正在读取传感器。"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self?.probeSensorHelper()
                        }
                    } else {
                        self?.sensorHelperMessage = "辅助进程安装未完成。"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.sensorHelperMessage = "安装失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func probeSensorHelper() {
        sensorClient.read { [weak self] values in
            DispatchQueue.main.async {
                self?.sensorHelperEnabled = values.isAvailable
                if values.isAvailable {
                    self?.sensorHelperMessage = "传感器辅助进程已运行。"
                }
            }
        }
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
            "showNetworkCard", "showFanCard", "showPowerCard", "showProcessesCard",
            "powerSavingMode", "processLimit", "processSort", "refreshInterval"
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
        showPowerCard = true
        showProcessesCard = true
        powerSavingMode = false
        processLimit = 8
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

struct BluetoothBatterySnapshot {
    let name: String
    let percentage: Double?
    let detail: String
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
    private var lastGPUSampleTime: TimeInterval?
    private let gpuSampleInterval: TimeInterval = 3
    private var recentGPUSamples: [Double] = []
    private var workerCPUHistory = Array(repeating: 0.0, count: 24)
    private var workerGPUHistory = Array(repeating: 0.0, count: 24)
    private var workerMemoryHistory = Array(repeating: 0.0, count: 24)
    private var workerDownloadHistory = Array(repeating: 0.0, count: 24)
    private var workerUploadHistory = Array(repeating: 0.0, count: 24)
    private var processLimit = 8
    private var processSort: ProcessSortOption = .cpu
    private var powerSavingMode = false
    private var sensorHelperEnabled = false
    private var sensorPollingStopped = false
    private var deviceInfoLoaded = false
    private let sensorClient = SensorClient()
    private(set) var intervalSeconds: Int

    init() {
        let saved = UserDefaults.standard.integer(forKey: "refreshInterval")
        intervalSeconds = [1, 3, 5, 10, 30].contains(saved) ? saved : 3
        startMonitoring()
    }

    func setRefreshInterval(_ seconds: Int) {
        guard [1, 3, 5, 10, 30].contains(seconds) else { return }
        intervalSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "refreshInterval")
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            let interval = self.powerSavingMode ? max(TimeInterval(seconds), 10) : TimeInterval(seconds)
            self.installHighTimer(interval: interval)
            self.collectHighFrequency()
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
        guard [5, 8, 10, 15].contains(limit) else { return }
        lowMetricsQueue.async { [weak self] in self?.processLimit = limit }
    }

    func setProcessSort(_ sort: ProcessSortOption) {
        lowMetricsQueue.async { [weak self] in self?.processSort = sort }
    }

    func setPowerSavingMode(_ enabled: Bool) {
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.powerSavingMode = enabled
            let interval = enabled ? max(TimeInterval(self.intervalSeconds), 10) : TimeInterval(self.intervalSeconds)
            self.installHighTimer(interval: interval)
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
            self.installHighTimer(interval: initialInterval)
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
        if !hasGPUSample || lastGPUSampleTime.map({ now - $0 >= gpuSampleInterval }) == true {
            let rawGPU = GPUReader.usage()
            recentGPUSamples.append(rawGPU)
            if recentGPUSamples.count > 5 { recentGPUSamples.removeFirst() }
            lastGPUSampleTime = now
        }
        let stableGPU = median(recentGPUSamples)
        // IORegistry 的 GPU 利用率是瞬时采样，偶尔会出现 0/100 的尖峰。
        workerGPU = hasGPUSample ? workerGPU * 0.7 + stableGPU * 0.3 : stableGPU
        hasGPUSample = true
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
                cpu: "\(Int(cpuSnapshot.total)) %",
                memory: "\(Int(memory)) %",
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

                // A missing fan key ends polling for this session, but preserve
                // any temperature values returned by the same successful read.
                // Zero RPM remains valid and is not treated as missing.
                if values.fanRPM == nil { self.sensorPollingStopped = true }
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
            snapshots.append(BluetoothBatterySnapshot(name: currentName, percentage: level, detail: detail))
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
                left = nil
                right = nil
                single = nil
                continue
            }

            guard currentName != nil else { continue }
            if let connected = connectionValue(in: value) {
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

struct DashboardView: View {
    @ObservedObject var store: MetricsStore
    @ObservedObject var settings: AppSettings

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                DeviceInfoView(info: store.deviceInfo)

            LazyVGrid(columns: columns, spacing: 8) {
                if settings.showCPUCard {
                    MetricCard(title: "CPU", icon: "cpu", value: "\(Int(store.cpu))%", badge: "\(store.cpuPerCore.count) 核") {
                    CPUBarChart(values: store.cpuPerCore)
                } footer: {
                    TemperatureTag(value: settings.sensorHelperEnabled ? store.cpuTemperature : nil)
                    }
                }

                if settings.showGPUCard {
                    MetricCard(
                    title: "GPU",
                    icon: "display",
                    value: "\(Int(store.gpu))%",
                    badge: store.deviceInfo.gpuCores.map { "\($0) 核" } ?? "—"
                ) {
                    Sparkline(values: store.gpuHistory, color: .orange)
                } footer: {
                    HStack(spacing: 6) {
                        Text(store.deviceInfo.gpuModel)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TemperatureTag(value: settings.sensorHelperEnabled ? store.gpuTemperature : nil)
                    }
                    }
                }

                if settings.showMemoryCard {
                    MetricCard(title: "内存", icon: "memorychip", value: "\(Int(store.memory))%", badge: "已使用") {
                    Sparkline(values: store.memoryHistory, color: .yellow)
                } footer: {
                    Text("已使用 \(store.memoryUsed) / \(store.memoryTotal)")
                    }
                }

                if settings.showDiskCard {
                    MetricCard(title: "磁盘", icon: "internaldrive", value: "\(Int(store.diskUsage))%", badge: store.diskTotal) {
                    ProgressView(value: store.diskUsage / 100)
                        .tint(.blue)
                } footer: {
                    Text("可用  \(store.diskFree)")
                    }
                }

                if settings.showNetworkCard {
                    MetricCard(title: "网络", icon: "network", value: formatRate(store.download), badge: "实时") {
                    NetworkChart(download: store.networkDownloadHistory, upload: store.networkUploadHistory)
                } footer: {
                    HStack(spacing: 14) {
                        Text("↑  \(formatRate(store.upload))")
                        Text("↓  \(formatRate(store.download))")
                    }
                    }
                }

                if settings.showFanCard {
                    MetricCard(
                    title: "风扇",
                    icon: "fanblades.fill",
                    value: store.fanRPM.map { String($0) } ?? "—",
                    badge: "RPM"
                ) {
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
                }
            }

            if settings.showPowerCard {
                PowerStatusView(
                    battery: store.battery,
                    bluetoothBatteries: store.bluetoothBatteries
                )
            }

            if settings.showProcessesCard {
                ProcessListView(processes: store.processes)
            }
            }
            .padding(8)
        }
        .frame(width: 360, height: 780, alignment: .top)
        .background(AppColors.background)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private func formatRate(_ bytes: Double) -> String {
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB/s", bytes / 1024 / 1024) }
        return String(format: "%.0f KB/s", bytes / 1024)
    }

}

struct PowerStatusView: View {
    let battery: BatterySnapshot
    let bluetoothBatteries: [BluetoothBatterySnapshot]

    private let columns = [
        GridItem(.adaptive(minimum: 155), spacing: 10, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("电源", systemImage: battery.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    PowerTag(text: battery.health.map { "健康 \(Int($0))%" } ?? "健康 —")
                    PowerTag(text: battery.cycleCount.map { "循环 \($0) 次" } ?? "循环 —")
                }
            }

            // Keep every device in a flexible two-column grid. Long device
            // names can wrap instead of being clipped, and additional devices
            // naturally continue on the next row.
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                BatteryRing(
                    value: battery.percentage,
                    title: "MacBook",
                    detail: battery.adapterWatts.map { "\(battery.powerSource)  \($0) W" } ?? battery.powerSource,
                    icon: "laptopcomputer"
                )

                ForEach(Array(bluetoothBatteries.enumerated()), id: \.offset) { _, device in
                    BatteryRing(
                        value: device.percentage,
                        title: device.name,
                        detail: device.detail,
                        icon: "airpodspro"
                    )
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

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(AppColors.badge)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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

struct BatteryRing: View {
    let value: Double?
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                    .stroke(value == nil ? Color.primary.opacity(0.18) : Color.green, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(value == nil ? .secondary : .primary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(info.model)
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
                HStack(spacing: 6) {
                    InfoTag(text: "CPU  \(displayCPUModel)")
                    InfoTag(text: "内存  \(info.memory)")
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("运行时间")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(info.uptime)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selectedInterval: Int
    let onChange: (Int) -> Void

    init(selectedInterval: Int, settings: AppSettings, onChange: @escaping (Int) -> Void) {
        _selectedInterval = State(initialValue: selectedInterval)
        self.settings = settings
        self.onChange = onChange
    }

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("偏好设置")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("自动保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 按使用顺序排列：外观 → 状态栏 → 监控，下面是模块和系统设置。
                HStack(alignment: .top, spacing: 16) {
                    SettingsSection(title: "外观", cardMinHeight: 150) {
                        Picker("", selection: $settings.theme) {
                            ForEach(ThemePreference.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    SettingsSection(title: "状态栏", cardMinHeight: 150) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ], alignment: .leading, spacing: 10) {
                            Toggle("CPU", isOn: $settings.showCPU)
                            Toggle("内存", isOn: $settings.showMemory)
                            Toggle("下载", isOn: $settings.showDownload)
                            Toggle("上传", isOn: $settings.showUpload)
                        }
                    }

                    SettingsSection(title: "监控", cardMinHeight: 150) {
                        Picker("更新间隔", selection: $selectedInterval) {
                            Text("1 秒").tag(1)
                            Text("3 秒").tag(3)
                            Text("5 秒").tag(5)
                            Text("10 秒").tag(10)
                            Text("30 秒").tag(30)
                        }
                        .onChange(of: selectedInterval) { newValue in
                            onChange(newValue)
                        }

                        Toggle("省电模式", isOn: $settings.powerSavingMode)

                        Picker("进程数量", selection: $settings.processLimit) {
                            Text("5 个").tag(5)
                            Text("8 个").tag(8)
                            Text("10 个").tag(10)
                            Text("15 个").tag(15)
                        }

                        Picker("进程排序", selection: $settings.processSort) {
                            ForEach(ProcessSortOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                HStack(alignment: .top, spacing: 16) {
                    SettingsSection(title: "面板模块", cardMinHeight: 140) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), alignment: .leading),
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
                            Toggle("电源", isOn: $settings.showPowerCard)
                            Toggle("进程", isOn: $settings.showProcessesCard)
                        }
                    }

                    SettingsSection(title: "系统", cardMinHeight: 140) {
                        Toggle("开机启动", isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { settings.setLaunchAtLogin($0) }
                        ))

                        Button(settings.sensorHelperEnabled ? "更新传感器辅助进程" : "授权读取风扇和温度") {
                            settings.installSensorHelper()
                        }

                        Text(settings.sensorHelperMessage ?? "需要将 App 放在“应用程序”文件夹，并完成管理员授权。")
                            .font(.caption)
                            .foregroundStyle(settings.sensorHelperMessage?.hasPrefix("授权失败") == true ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("恢复默认设置", role: .destructive) {
                            settings.resetToDefaults()
                            selectedInterval = 3
                            onChange(3)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)

                Text("更新间隔越短，数据越及时，但耗电和资源占用也会略有增加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(minWidth: 820, idealWidth: 860, minHeight: 480, idealHeight: 520)
        .background(AppColors.background)
        .preferredColorScheme(settings.theme.colorScheme)
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

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(16)
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
    let content: Content
    let footer: Footer

    init(title: String, icon: String, value: String, badge: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.value = value
        self.badge = badge
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            content
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .frame(height: 28)

            footer
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(minHeight: 124, alignment: .top)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("高占用进程", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("CPU          内存")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if processes.isEmpty {
                Text("正在读取进程…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

private enum AppColors {
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
