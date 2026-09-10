import AppKit
import SwiftUI

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedCategory: SettingsCategory = .appearance
    @Published var selectedStatisticsTab: StatisticsDetailTab = .typing
}

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
    @State var languageRestartRequired = false
    @State var initialLanguage: AppLanguage
    @ObservedObject private var navigation = SettingsNavigation.shared
    @StateObject private var notesSettings = SettingsModel()
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
        self._initialLanguage = State(initialValue: settings.appLanguage)
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
            SettingsWindowBackground()
                .ignoresSafeArea()

            HStack(spacing: 0) {
            sidebar

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    settingsContent
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(28)
                .background(ThinScrollViewConfigurator())
            }
            .scrollIndicators(.hidden)
            .background(.clear)
            }
        }
        .sheet(isPresented: $isAddingCodexAccount) {
            addCodexAccountSheet
        }
        .frame(minWidth: 900, idealWidth: 940, minHeight: 680, idealHeight: 760)
        .background(.clear)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsCategory.allCases) { category in
                SettingsSidebarItem(
                    title: category.title,
                    systemImage: category.systemImage,
                    isSelected: navigation.selectedCategory == category
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        navigation.selectedCategory = category
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.clear)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch navigation.selectedCategory {
        case .appearance:
            settingsPage { appearanceSection }
        case .statusBar:
            settingsPage {
                statusBarSection
                statusBarOrderSection
            }
        case .dashboard:
            settingsPage { dashboardSection }
        case .monitoring:
            settingsPage {
                monitoringSection
                sensorsSection
                Text(StatsL10n.text("settings.refresh_interval_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .development:
            settingsPage {
                codexSection
                wakaTimeSection
            }
        case .statistics:
            StatisticsSettingsPage(
                typingStats: typingStats,
                wakaTimeUsageStore: wakaTimeUsageStore,
                selectedTab: $navigation.selectedStatisticsTab
            )
        case .notes:
            settingsPage {
                NotesSettingsView(model: notesSettings)
            }
        case .system:
            settingsPage { systemSection }
        }
    }

    private func settingsPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) { content() }
    }

}

enum SettingsCategory: CaseIterable, Identifiable {
    case appearance
    case statusBar
    case dashboard
    case monitoring
    case development
    case statistics
    case notes
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: return StatsL10n.text("settings.category.appearance")
        case .statusBar: return StatsL10n.text("settings.category.status_bar")
        case .dashboard: return StatsL10n.text("settings.category.dashboard")
        case .monitoring: return StatsL10n.text("settings.category.monitoring")
        case .development: return StatsL10n.text("settings.category.development")
        case .statistics: return StatsL10n.text("settings.category.statistics")
        case .notes: return StatsL10n.text("settings.category.notes")
        case .system: return StatsL10n.text("settings.category.system")
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "paintpalette"
        case .statusBar: return "menubar.rectangle"
        case .dashboard: return "rectangle.grid.2x2"
        case .monitoring: return "waveform.path.ecg"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .statistics: return "chart.bar.xaxis"
        case .notes: return "note.text"
        case .system: return "gearshape"
        }
    }
}
