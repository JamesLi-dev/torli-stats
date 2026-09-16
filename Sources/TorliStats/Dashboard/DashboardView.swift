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
    static let panelWidth: CGFloat = 360
    static let maximumPopoverHeight: CGFloat = 820

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: MetricsStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var codexUsageStore: CodexAccountsUsageStore
    @ObservedObject var codexTokenActivityService: CodexTokenActivityService
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore
    @ObservedObject var typingStats: TypingStatsService
    let onCodexDisplayCountChange: (Int) -> Void
    let onTypingDetails: () -> Void
    let onWakaTimeDetails: () -> Void
    var onTypingPermission: () -> Void = {}
    var onOpenSettings: (SettingsCategory) -> Void = { _ in }

    private var metricGridSpacing: CGFloat {
        DashboardLayout.metricSpacing(for: settings.dashboardDensity)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: metricGridSpacing),
            GridItem(.flexible(), spacing: metricGridSpacing)
        ]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DashboardLayout.sectionSpacing) {
                if settings.showDashboardDeviceInfo {
                    DeviceInfoView(
                        info: store.deviceInfo,
                        isPrivacyMode: settings.privacyMode,
                        density: settings.dashboardDensity
                    )
                }

                if store.isMonitoringPaused || store.isAdaptiveLowFrequency {
                    HStack(spacing: 6) {
                        Image(systemName: store.isMonitoringPaused ? "moon.zzz.fill" : "leaf.fill")
                        Text(monitoringStatusMessage)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(monitoringStatusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(monitoringStatusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(monitoringStatusColor.opacity(0.16), lineWidth: 0.6)
                    }
                }

                ForEach(layoutBlocks) { block in
                    switch block {
                    case let .metrics(modules):
                        LazyVGrid(columns: columns, spacing: metricGridSpacing) {
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
            .frame(width: Self.panelWidth, alignment: .top)
        }
        .frame(width: Self.panelWidth)
        .overlay(alignment: .bottom) {
            scrollHint
        }
        .background(panelSurface)
        .clipShape(DashboardLayout.popoverShape)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private var usesDarkGlass: Bool {
        settings.theme == .dark || (settings.theme == .system && colorScheme == .dark)
    }

    private var monitoringStatusColor: Color {
        store.isMonitoringPaused ? DashboardPalette.quotaWarning : DashboardPalette.quotaSuccess
    }

    private var needsScrollHint: Bool {
        Self.preferredHeight(
            for: settings,
            codexAccountCount: codexUsageStore.accounts.filter(\.isDashboardVisible).count
        ) > Self.maximumPopoverHeight
    }

    @ViewBuilder
    private var scrollHint: some View {
        if needsScrollHint {
            LinearGradient(
                colors: [
                    Color.clear,
                    (usesDarkGlass ? Color.black : Color.white).opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            .clipShape(DashboardLayout.popoverShape)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var panelSurface: some View {
        if usesDarkGlass {
            DashboardLayout.popoverShape
                .fill(.regularMaterial)
                .overlay {
                    DashboardLayout.popoverShape
                        .fill(AppColors.background.opacity(0.16))
                        .allowsHitTesting(false)
                }
        } else {
            // Keep the light surface translucent, then add only a quiet cool
            // gradient so the cards have depth without competing with their
            // metric colors.
            DashboardLayout.popoverShape
                .fill(.thinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.52),
                            Color.white.opacity(0.28),
                            Color(red: 0.88, green: 0.93, blue: 1.0).opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(DashboardLayout.popoverShape)
                    .allowsHitTesting(false)
                }
                .overlay {
                    DashboardLayout.popoverShape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.82),
                                    Color.white.opacity(0.38),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
        }
    }

    private var monitoringStatusMessage: String {
        if store.isAdaptiveLowFrequency {
            return StatsL10n.text("dashboard.low_impact_sampling")
        }
        return store.monitoringPauseMessage ?? StatsL10n.text("dashboard.monitoring_paused")
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
            MetricCard(title: "CPU", icon: "cpu", value: "\(Int(store.cpu))%", badge: StatsL10n.format("dashboard.cpu_cores", store.cpuPerCore.count), density: settings.dashboardDensity, valueColor: highUsageColor(store.cpu, warning: 70, critical: 90)) {
                CPUBarChart(values: store.cpuPerCore)
            } footer: {
                if settings.showTemperatureTags {
                    TemperatureTag(value: settings.sensorHelperEnabled ? store.cpuTemperature : nil)
                }
            }
        case .gpu:
            MetricCard(title: "GPU", icon: "display", value: "\(Int(store.gpu))%", badge: store.deviceInfo.gpuCores.map { StatsL10n.format("dashboard.gpu_cores", $0) } ?? "—", density: settings.dashboardDensity) {
                Sparkline(values: store.gpuHistory, color: .orange)
            } footer: {
                HStack(spacing: 6) {
                    Text(store.deviceInfo.gpuModel)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if settings.showTemperatureTags {
                        TemperatureTag(value: settings.sensorHelperEnabled ? store.gpuTemperature : nil)
                    }
                }
            }
        case .memory:
            MetricCard(
                title: StatsL10n.text("dashboard.memory"),
                icon: "memorychip",
                value: "\(Int(store.memory))%",
                badge: memoryPressureTitle,
                density: settings.dashboardDensity,
                valueColor: highUsageColor(store.memory, warning: 75, critical: 90),
                badgeColor: memoryPressureColor
            ) {
                Sparkline(values: store.memoryHistory, color: .yellow)
            } footer: {
                Text(StatsL10n.format("dashboard.memory_usage", store.memoryUsed, store.memoryTotal))
                    .help(StatsL10n.text("dashboard.memory_usage_help"))
            }
        case .disk:
            MetricCard(title: StatsL10n.text("dashboard.disk"), icon: "internaldrive", value: "\(Int(store.diskUsage))%", badge: store.diskTotal, density: settings.dashboardDensity, valueColor: highUsageColor(store.diskUsage, warning: 80, critical: 90)) {
                DashboardProgressBar(value: store.diskUsage / 100, tint: DashboardPalette.diskProgress)
            } footer: {
                Text(StatsL10n.format("dashboard.available_space", store.diskFree))
            }
        case .network:
            MetricCard(title: StatsL10n.text("dashboard.network"), icon: "network", value: formatRate(store.download), badge: StatsL10n.text("dashboard.live"), density: settings.dashboardDensity) {
                NetworkChart(download: store.networkDownloadHistory, upload: store.networkUploadHistory)
            } footer: {
                HStack(spacing: 14) {
                    Text("↑  \(formatRate(store.upload))")
                    Text("↓  \(formatRate(store.download))")
                }
            }
        case .fan:
            MetricCard(title: StatsL10n.text("dashboard.fan"), icon: "fanblades.fill", value: store.fanRPM.map(String.init) ?? "—", badge: "RPM", density: settings.dashboardDensity) {
                if !settings.sensorHelperEnabled || store.fanRPM == nil {
                    DashboardEmptyState(
                        icon: "fanblades.fill",
                        message: settings.sensorHelperEnabled
                            ? StatsL10n.text("dashboard.sensor_unavailable")
                            : StatsL10n.text("dashboard.authorize_fan"),
                        action: { onOpenSettings(.monitoring) },
                        actionHelp: StatsL10n.text("sensor.settings.title")
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                        Text(StatsL10n.text("dashboard.current_speed"))
                    }
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text(settings.sensorHelperEnabled
                    ? (store.fanRPM == nil ? StatsL10n.text("dashboard.rpm_unavailable") : StatsL10n.text("dashboard.fan_speed"))
                    : StatsL10n.text("dashboard.authorize_fan"))
            }
        case .typing:
            MetricCard(
                title: StatsL10n.text("dashboard.typing"),
                icon: "keyboard",
                value: compactNumber(typingStats.todayKeyCount),
                badge: typingTrendBadge,
                density: settings.dashboardDensity,
                valueColor: typingStats.permissionStatus == .monitoring ? .primary : .secondary,
                isInteractive: true
            ) {
                if settings.dashboardDensity == .standard || settings.dashboardDensity == .detailed {
                    if typingStats.permissionStatus == .monitoring {
                        TypingTrendSparkline(records: typingStats.records(forLastDays: 14))
                    } else {
                        DashboardEmptyState(
                            icon: "keyboard",
                            message: typingStats.permissionStatus.description,
                            tint: typingStats.permissionStatus == .needsPermission
                                ? DashboardPalette.quotaWarning
                                : .secondary,
                            action: typingStats.permissionStatus == .needsPermission ? onTypingPermission : nil,
                            actionHelp: StatsL10n.text("settings.system.open_input_monitoring")
                        )
                    }
                }
            } footer: {
                HStack(spacing: 4) {
                    Text(typingStats.permissionStatus == .monitoring
                        ? StatsL10n.format("dashboard.typing_summary", compactNumber(typingStats.totalKeyCount), formatTypingDuration(typingStats.activeSeconds))
                        : typingStats.permissionStatus.description)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.secondary)
            }
            .contentShape(DashboardLayout.cardShape)
            .onTapGesture(perform: onTypingDetails)
            .help(StatsL10n.text("dashboard.typing_details"))
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
                activityService: codexTokenActivityService,
                showsTokenActivity: settings.codexTokenActivityEnabled,
                isPrivacyMode: settings.privacyMode,
                density: settings.dashboardDensity,
                onDisplayCountChange: onCodexDisplayCountChange,
                onOpenSettings: onOpenSettings
            )
        case .wakatime:
            WakaTimeUsageView(
                store: wakaTimeUsageStore,
                range: settings.wakaTimeRange,
                density: settings.dashboardDensity,
                onDetails: onWakaTimeDetails
            )
        case .processes:
            ProcessListView(
                processes: store.processes,
                density: settings.dashboardDensity,
                displayMode: settings.processSort,
                showPID: settings.showProcessPID
            )
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

        let metricCardHeight = DashboardLayout.metricCardHeight(for: settings.dashboardDensity)

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

        var blockHeights: [CGFloat] = []
        if settings.showDashboardDeviceInfo { blockHeights.append(48) }
        if metricRows > 0 {
            blockHeights.append(
                metricRows * metricCardHeight
                    + max(0, metricRows - 1) * DashboardLayout.metricSpacing(for: settings.dashboardDensity)
            )
        }
        if settings.showPowerCard { blockHeights.append(powerHeight) }
        if codexAccountCount > 0 {
            var codexHeight = codexBaseHeight + CGFloat(max(0, codexAccountCount - 1)) * 88
            if settings.codexTokenActivityEnabled { codexHeight += 175 }
            blockHeights.append(codexHeight)
        }
        if settings.showWakaTimeCard && settings.wakaTimeEnabled {
            switch settings.dashboardDensity {
            case .compact: blockHeights.append(95)
            case .standard: blockHeights.append(210)
            case .detailed: blockHeights.append(280)
            }
        }
        if settings.showProcessesCard {
            blockHeights.append(42 + CGFloat(processRowCount) * 18)
        }

        let padding = settings.dashboardDensity == .compact ? 6 : 8
        let spacing = CGFloat(max(0, blockHeights.count - 1)) * DashboardLayout.sectionSpacing
        let height = CGFloat(padding * 2) + blockHeights.reduce(0, +) + spacing

        // The popover height follows the enabled modules and process count;
        // only the minimum keeps an empty or partially loaded panel usable.
        return max(height, 160)
    }

    private var memoryPressureTitle: String {
        switch store.memoryPressure {
        case .normal: return StatsL10n.text("dashboard.memory_pressure.normal")
        case .warning: return StatsL10n.text("dashboard.memory_pressure.warning")
        case .critical: return StatsL10n.text("dashboard.memory_pressure.critical")
        case .unknown: return StatsL10n.text("dashboard.memory_pressure.unknown")
        }
    }

    private var memoryPressureColor: Color {
        switch store.memoryPressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
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
        return settings.dashboardDensity == .compact ? StatsL10n.format("dashboard.typing_today_badge", speed) : speed
    }

    private func compactNumber(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : String(value)
    }

    private func formatTypingDuration(_ value: TimeInterval) -> String {
        let minutes = Int(value) / 60
        return minutes >= 60 ? StatsL10n.format("statistics.duration", minutes / 60, minutes % 60) : StatsL10n.format("statistics.minutes", minutes)
    }
}

struct DashboardEmptyState: View {
    let icon: String
    let message: String
    var tint: Color = .secondary
    var action: (() -> Void)?
    var actionHelp: String?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            if let action, let actionHelp {
                Button(action: action) {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(DashboardIconButtonStyle())
                .help(actionHelp)
                .accessibilityLabel(actionHelp)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 0.6)
        }
    }
}

enum DashboardLayout {
    // Keep the SwiftUI background aligned with the native NSPopover mask;
    // larger radii leave a second, visible curve inside the outer bezel.
    // Keep the panel's outer curve visibly softer than its inner cards while
    // the custom borderless panel defines the final bezel.
    static let popoverCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 12
    static let progressBarHeight: CGFloat = 4
    static let codexProgressBarHeight: CGFloat = 5
    static let sectionSpacing: CGFloat = 8

    static func metricCardHeight(for density: DashboardDensity) -> CGFloat {
        switch density {
        case .compact: return 58
        // Leave enough room for the footer chip (for example the CPU
        // temperature tag) without letting it draw past the card boundary.
        case .standard: return 120
        case .detailed: return 134
        }
    }

    static var popoverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: popoverCornerRadius, style: .continuous)
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    static func metricSpacing(for density: DashboardDensity) -> CGFloat {
        density == .compact ? 6 : 8
    }
}

private struct DashboardCardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private let isInteractive: Bool
    @State private var isHovered = false

    init(isInteractive: Bool) {
        self.isInteractive = isInteractive
    }

    private var cardTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.white.opacity(0.20)
    }

    private var border: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.14), Color.white.opacity(0.035)]
                : [Color.white.opacity(0.68), Color.black.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func body(content: Content) -> some View {
        content
            .background {
                DashboardLayout.cardShape
                    .fill(.thinMaterial)
                    .overlay {
                        DashboardLayout.cardShape
                            .fill(cardTint)
                            .allowsHitTesting(false)
                    }
            }
            .overlay {
                DashboardLayout.cardShape
                    .stroke(border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(DashboardLayout.cardShape)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05),
                radius: isInteractive && isHovered ? 8 : 5,
                y: isInteractive && isHovered ? 2 : 1
            )
            .brightness(isInteractive && isHovered ? 0.012 : 0)
            .onHover { hovering in
                guard isInteractive else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func dashboardCardSurface(interactive: Bool = false) -> some View {
        modifier(DashboardCardSurfaceModifier(isInteractive: interactive))
    }
}
