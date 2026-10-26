import SwiftUI

public enum StatisticsDetailTab: String, CaseIterable, Identifiable {
    case typing
    case development

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .typing: return StatsL10n.text("statistics.tab.typing")
        case .development: return StatsL10n.text("statistics.tab.development")
        }
    }

    var systemImage: String {
        switch self {
        case .typing: return "keyboard"
        case .development: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct StatisticsSettingsPage: View {
    @ObservedObject var typingStats: TypingStatsService
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore
    @Binding var selectedTab: StatisticsDetailTab

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ForEach(StatisticsDetailTab.allCases) { tab in
                    SettingsTabItem(
                        title: tab.title,
                        systemImage: tab.systemImage,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch selectedTab {
                case .typing:
                    StatisticsContent(tab: .typing, typing: typingStats, development: wakaTimeUsageStore)
                case .development:
                    StatisticsContent(tab: .development, typing: typingStats, development: wakaTimeUsageStore)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct StatisticsDetailView: View {
    @ObservedObject var typingStats: TypingStatsService
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore

    @State private var selectedTab: StatisticsDetailTab

    init(
        typingStats: TypingStatsService,
        wakaTimeUsageStore: WakaTimeUsageStore,
        initialTab: StatisticsDetailTab
    ) {
        self.typingStats = typingStats
        self.wakaTimeUsageStore = wakaTimeUsageStore
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            SettingsWindowBackground()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(StatisticsDetailTab.allCases) { tab in
                        SettingsSidebarItem(
                            title: tab.title,
                            systemImage: tab.systemImage,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedTab = tab
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(width: 160)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider()

                ScrollView(.vertical, showsIndicators: true) {
                    Group {
                        switch selectedTab {
                        case .typing:
                            StatisticsContent(tab: .typing, typing: typingStats, development: wakaTimeUsageStore)
                        case .development:
                            StatisticsContent(tab: .development, typing: typingStats, development: wakaTimeUsageStore)
                        }
                    }
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                }
                .background(ThinScrollViewConfigurator(verticalInset: 6))
            }
        }
        .frame(width: 780, height: 640, alignment: .topLeading)
        .background(.clear)
    }
}

private struct StatisticsContent: View {
    let tab: StatisticsDetailTab
    @ObservedObject var typing: TypingStatsService
    @ObservedObject var development: WakaTimeUsageStore
    var body: some View {
        if let provider = FeatureRegistry.shared.statistics {
            provider.details(tab: tab, typing: typing, development: development)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if tab == .typing {
                    DetailSection(title: StatsL10n.text("statistics.today_input"), subtitle: typing.permissionStatus.description) {
                        DetailMetricGrid(items: [
                            (StatsL10n.text("statistics.typing.key_count"), StatisticsFormatting.compactNumber(typing.todayKeyCount)),
                            (StatsL10n.text("statistics.active_time"), StatisticsFormatting.compactDuration(typing.activeSeconds)),
                            ("KPM", String(typing.keysPerMinute))
                        ])
                        Text(StatsL10n.text("statistics.typing.privacy")).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    DetailSection(title: StatsL10n.text("statistics.today_development"), subtitle: development.state.statusText) {
                        Text(development.todayPeriod.map { StatisticsFormatting.compactDuration($0.totalSeconds) } ?? "—")
                            .font(.title.bold())
                        Button(StatsL10n.text("wakatime.refresh")) { development.refresh() }
                    }
                }
                Text(StatsL10n.text("statistics.pro_history_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
