import AppKit
import SwiftUI

struct SettingsView: View {
    // Section extensions share this state so sheet and input lifetimes stay unchanged.
    @ObservedObject var settings: AppSettings
    @ObservedObject var codexUsageStore: CodexAccountsUsageStore
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore
    @ObservedObject var typingStats: TypingStatsService
    @ObservedObject var updateChecker: AppUpdateChecker
    @State var draggedStatusBarGroup: StatusBarMetricGroup?
    @State var draggedDashboardModule: DashboardModule?
    @State var codexAccountMessage: String?
    @State var testingCodexAccountIDs = Set<UUID>()
    @State var isAddingCodexAccount = false
    @State var newCodexAccountName = ""
    @State var wakaTimeAPIKey = ""
    @State var hasWakaTimeAPIKey: Bool
    @State var wakaTimeMessage: String?
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

    var visibleStatusBarGroups: [StatusBarMetricGroup] {
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

    var visibleDashboardModules: [DashboardModule] {
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
                        appearanceSection

                        statusBarSection

                        statusBarOrderSection

                        monitoringSection

                    }
                    .frame(minWidth: 400, idealWidth: 444, maxWidth: .infinity, alignment: .top)

                    VStack(alignment: .leading, spacing: 16) {
                        dashboardSection

                        sensorsSection

                        systemSection

                    }
                    .frame(width: 360, alignment: .top)
                }
                .frame(minWidth: 776, maxWidth: .infinity, alignment: .topLeading)

                codexSection

                wakaTimeSection

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

}
