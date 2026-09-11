import SwiftUI

enum StatisticsDetailTab: String, CaseIterable, Identifiable {
    case typing
    case development

    var id: String { rawValue }

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
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedTab = tab
                        }
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .background(selectedTab == tab ? Color.accentColor : AppColors.badge)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch selectedTab {
                case .typing:
                    TypingStatisticsDetailContent(typingStats: typingStats)
                case .development:
                    DevelopmentStatisticsDetailContent(store: wakaTimeUsageStore)
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
                            TypingStatisticsDetailContent(typingStats: typingStats)
                        case .development:
                            DevelopmentStatisticsDetailContent(store: wakaTimeUsageStore)
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
