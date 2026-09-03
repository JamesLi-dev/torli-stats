import SwiftUI

enum StatisticsDetailTab: String, CaseIterable, Identifiable {
    case typing
    case development

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typing: return "输入统计"
        case .development: return "开发统计"
        }
    }
}

struct StatisticsDetailView: View {
    @ObservedObject var typingStats: TypingStatsService
    @ObservedObject var wakaTimeUsageStore: WakaTimeUsageStore
    let onClose: () -> Void

    @State private var selectedTab: StatisticsDetailTab

    init(
        typingStats: TypingStatsService,
        wakaTimeUsageStore: WakaTimeUsageStore,
        initialTab: StatisticsDetailTab,
        onClose: @escaping () -> Void
    ) {
        self.typingStats = typingStats
        self.wakaTimeUsageStore = wakaTimeUsageStore
        self.onClose = onClose
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 0) {
                    ForEach(StatisticsDetailTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(width: 118)
                                .padding(.vertical, 8)
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                                .background {
                                    if selectedTab == tab {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(Color.accentColor)
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                        .focusable(false)
                    }
                }
                .padding(3)
                .background(AppColors.badge)
                .clipShape(RoundedRectangle(cornerRadius: 11))

                Spacer(minLength: 0)
                Button("完成", action: onClose)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            }
            .background(ThinScrollViewConfigurator(verticalInset: 6))
        }
        .padding(20)
        .frame(width: 720, height: 640, alignment: .topLeading)
        .background(AppColors.background)
    }
}

private struct TypingStatisticsDetailContent: View {
    @ObservedObject var typingStats: TypingStatsService
    @State private var selectedPeriod = 7

    private var records: [TypingDailyRecord] {
        typingStats.records(forLastDays: selectedPeriod)
    }

    private var periodTotal: Int {
        records.reduce(0) { $0 + $1.keyCount }
    }

    private var activeDays: Int {
        records.filter { $0.keyCount > 0 }.count
    }

    private var averagePerActiveDay: Int {
        guard activeDays > 0 else { return 0 }
        return Int((Double(periodTotal) / Double(activeDays)).rounded())
    }

    private var peakRecord: TypingDailyRecord? {
        records.max { $0.keyCount < $1.keyCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("输入统计周期", selection: $selectedPeriod) {
                Text("近 7 天").tag(7)
                Text("近 30 天").tag(30)
            }
            .pickerStyle(.segmented)

            DetailSection(title: "输入概览", subtitle: "仅保存按日键数和活跃时长，不记录输入内容、键码或应用信息") {
                DetailMetricGrid(items: [
                    ("键数", compactNumber(periodTotal)),
                    ("活跃天数", "\(activeDays) 天"),
                    ("活跃日均", compactNumber(averagePerActiveDay)),
                    ("最高", compactNumber(peakRecord?.keyCount ?? 0))
                ])
            }

            DetailSection(title: "每日键数", subtitle: dateRangeText(records.map(\.dateID))) {
                DetailedDailyBarChart(values: records.map { DetailDailyValue(dateID: $0.dateID, value: Double($0.keyCount)) }, color: .cyan)
                    .frame(height: 128)
            }

            DetailSection(title: "每日明细") {
                LazyVStack(spacing: 0) {
                    ForEach(records.reversed()) { record in
                        HStack {
                            Text(record.dateID)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(formatDuration(record.activeSeconds))
                                .foregroundStyle(.secondary)
                            Text("\(compactNumber(record.keyCount)) 键")
                                .frame(width: 86, alignment: .trailing)
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct DevelopmentStatisticsDetailContent: View {
    @ObservedObject var store: WakaTimeUsageStore
    @State private var selectedRange: WakaTimeRange = .last30Days

    private var snapshot: WakaTimeSnapshot? {
        store.snapshots[selectedRange] ?? store.state.snapshot
    }

    private var period: WakaTimePeriod? {
        store.period(for: selectedRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Picker("开发统计周期", selection: $selectedRange) {
                    ForEach(WakaTimeRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    store.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(matchesLoadingState)
            }

            if let snapshot {
                developmentContent(snapshot)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("暂无开发统计")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(store.state.statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
    }

    private var matchesLoadingState: Bool {
        if case .loading = store.state { return true }
        return false
    }

    @ViewBuilder
    private func developmentContent(_ snapshot: WakaTimeSnapshot) -> some View {
        DetailSection(title: "编码概览", subtitle: store.state.statusText) {
            DetailMetricGrid(items: [
                ("今天", compactDuration(store.todayPeriod?.totalSeconds ?? 0)),
                ("\(selectedRange.title)", compactDuration(period?.totalSeconds ?? snapshot.totalSeconds)),
                ("活跃日均", compactDuration(period?.averageActiveDaySeconds ?? 0)),
                ("活跃天数", "\(period?.activeDayCount ?? 0) 天")
            ])
        }

        if let period, !period.dailyRecords.isEmpty {
            DetailSection(title: "每日编码时长", subtitle: dateRangeText(period.dailyRecords.map(\.dateID))) {
                DetailedDailyBarChart(
                    values: period.dailyRecords.map { DetailDailyValue(dateID: $0.dateID, value: $0.totalSeconds) },
                    color: .blue
                )
                .frame(height: 128)
            }
        }

        DetailSection(title: "语言", subtitle: "按 WakaTime 聚合时长") {
            BreakdownList(values: Array(snapshot.languages.prefix(5)), color: .blue)
        }

        if let aiCoding = snapshot.categories.first(where: { $0.name.caseInsensitiveCompare("AI Coding") == .orderedSame }) {
            DetailSection(title: "AI Coding", subtitle: "占全部编码时长 \(String(format: "%.0f", aiCoding.percent))%") {
                DetailMetricGrid(items: [
                    ("AI 时长", compactDuration(aiCoding.totalSeconds)),
                    ("AI 占比", String(format: "%.1f%%", aiCoding.percent)),
                    ("输入 Token", compactNumber(snapshot.aiInputTokens)),
                    ("输出 Token", compactNumber(snapshot.aiOutputTokens))
                ])
            }
        }

        if !snapshot.aiModelBreakdown.isEmpty {
            DetailSection(title: "AI 模型", subtitle: snapshot.aiModelTotalCost > 0 ? String(format: "模型总成本 $%.2f", snapshot.aiModelTotalCost) : nil) {
                LazyVStack(spacing: 0) {
                    ForEach(snapshot.aiModelBreakdown) { model in
                        HStack {
                            Text(model.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(compactNumber(Double(model.lines))) 行")
                                .foregroundStyle(.secondary)
                            if model.cost > 0 {
                                Text(String(format: "$%.2f", model.cost))
                                    .frame(width: 58, alignment: .trailing)
                            }
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
        }

        if !snapshot.editors.isEmpty {
            DetailSection(title: "编辑器") {
                BreakdownList(values: Array(snapshot.editors.prefix(3)), color: .purple)
            }
        }

        Text("仅展示 WakaTime 提供的聚合时长、语言、AI 和工具统计，不展示项目、文件、分支或路径。")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(14)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailMetricGrid: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct BreakdownList: View {
    let values: [WakaTimeBreakdown]
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ForEach(values) { value in
                HStack(spacing: 9) {
                    Text(value.name)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color.opacity(0.82))
                            .frame(width: max(2, proxy.size.width * min(1, value.percent / 100)))
                            .frame(maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 4)
                    Text(compactDuration(value.totalSeconds))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }
}

private struct DetailDailyValue: Identifiable {
    let dateID: String
    let value: Double

    var id: String { dateID }
}

private struct DetailedDailyBarChart: View {
    let values: [DetailDailyValue]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(values.map(\.value).max() ?? 0, 1)
            let spacing: CGFloat = values.count > 14 ? 2 : 4
            let width = max(3, (proxy.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(values) { entry in
                    RoundedRectangle(cornerRadius: min(3, width / 2))
                        .fill(entry.value > 0 ? color.opacity(0.84) : Color.secondary.opacity(0.14))
                        .frame(width: width, height: max(3, proxy.size.height * CGFloat(entry.value / maximum)))
                        .help("\(entry.dateID)：\(chartValue(entry.value))")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("每日趋势图")
    }

    private func chartValue(_ value: Double) -> String {
        value >= 3_600 ? compactDuration(value) : "\(Int(value))"
    }
}

private func compactNumber(_ value: Int) -> String {
    value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : String(value)
}

private func compactNumber(_ value: Double) -> String {
    switch value {
    case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
    case 1_000...: return String(format: "%.1fK", value / 1_000)
    default: return String(Int(value))
    }
}

private func compactDuration(_ seconds: Double) -> String {
    let totalMinutes = max(0, Int(seconds / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分"
}

private func dateRangeText(_ dateIDs: [String]) -> String? {
    guard let first = dateIDs.first, let last = dateIDs.last else { return nil }
    return "\(first) — \(last)"
}
