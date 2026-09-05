import AppKit
import SwiftUI

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
