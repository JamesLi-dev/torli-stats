import SwiftUI
import AppKit

extension AppSettings {
    func resetToDefaults() {
        if launchAtLogin {
            setLaunchAtLogin(false)
        }

        [
            "themePreference", "showCPU", "showMemory", "showDownload", "showUpload",
            "showCPUCard", "showGPUCard", "showMemoryCard", "showDiskCard",
            "showNetworkCard", "showFanCard", "showTypingCard", "showPowerCard", "showProcessesCard",
            "showCodexCard", "showWakaTimeCard", "wakaTimeEnabled", "wakaTimeRange", "dashboardDensity", "showDashboardDeviceInfo", "showTemperatureTags", "showProcessPID", "dashboardModuleOrder", "showCodexStatusItem", "showTypingStatusItem", "codexStatusMetric", "codexStatusBarMode", "codexStatusBarAccountLimit", "statusBarMetricOrder",
            "systemStatusBarStyle", "statusBarFontSize", "showStatusBarMetricIcons", "networkRateUnit", "networkRateDecimalPlaces", "showStatusBarLogo", "statusBarLogoStyle", "statusBarLogoAnimation", "statusBarRunner", "privacyMode", "automaticUpdateChecks", "typingStatsEnabled", "codexDefaultAccountName", "codexHomePath", "codexAutoRefresh", "codexTokenActivityEnabled", "codexRefreshInterval", "codexManagedAccounts", "powerSavingMode", "manualMonitoringPaused", "backgroundMonitoringEnabled", "nightMonitoringPauseEnabled", "adaptiveSamplingEnabled", "nightMonitoringPauseStartSeconds", "nightMonitoringPauseEndSeconds", "batteryRefreshInterval", "lowBatterySavingEnabled", "lowBatteryThreshold", "processLimit", "processSort", "refreshInterval"
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
        showDashboardDeviceInfo = true
        showTemperatureTags = true
        showProcessPID = true
        dashboardModuleOrder = DashboardModule.allCases
        showCodexStatusItem = true
        showTypingStatusItem = false
        codexStatusMetric = .remaining
        codexStatusBarMode = .defaultAccount
        codexStatusBarAccountLimit = 3
        statusBarMetricOrder = StatusBarMetricGroup.allCases
        systemStatusBarStyle = .compact
        statusBarFontSize = .standard
        showStatusBarMetricIcons = true
        networkRateUnit = .automatic
        networkRateDecimalPlaces = 1
        showStatusBarLogo = true
        statusBarLogoAnimation = true
        statusBarRunner = .runCat
        privacyMode = false
        automaticUpdateChecks = true
        typingStatsEnabled = false
        codexDefaultAccountName = StatsL10n.text("codex.settings.default_account")
        codexHomePath = ""
        codexAutoRefresh = true
        codexTokenActivityEnabled = true
        codexRefreshInterval = 5
        codexManagedAccounts = []
        refreshInterval = 3
        powerSavingMode = false
        manualMonitoringPaused = false
        backgroundMonitoringEnabled = true
        nightMonitoringPauseEnabled = true
        adaptiveSamplingEnabled = false
        nightMonitoringPauseStartSeconds = 23 * 3_600 + 30 * 60
        nightMonitoringPauseEndSeconds = 7 * 3_600
        batteryRefreshInterval = 10
        lowBatterySavingEnabled = true
        lowBatteryThreshold = 20
        processLimit = 5
        processSort = .cpu
    }

}
