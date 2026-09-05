import AppKit
import Combine
import SwiftUI
import ServiceManagement
import TorliStatsShared

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
