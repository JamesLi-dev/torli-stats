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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
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
            Picker(StatsL10n.text("statistics.typing.period"), selection: $selectedPeriod) {
                Text(StatsL10n.text("wakatime.last_7_days")).tag(7)
                Text(StatsL10n.text("wakatime.last_30_days")).tag(30)
            }
            .pickerStyle(.segmented)

            DetailSection(title: StatsL10n.text("statistics.typing.overview"), subtitle: StatsL10n.text("statistics.typing.privacy")) {
                DetailMetricGrid(items: [
                    (StatsL10n.text("statistics.typing.key_count"), compactNumber(periodTotal)),
                    (StatsL10n.text("statistics.typing.active_days"), StatsL10n.format("statistics.days", activeDays)),
                    (StatsL10n.text("statistics.typing.active_daily_average"), compactNumber(averagePerActiveDay)),
                    (StatsL10n.text("statistics.typing.peak"), compactNumber(peakRecord?.keyCount ?? 0))
                ])
            }

            DetailSection(title: StatsL10n.text("statistics.typing.daily_key_count"), subtitle: dateRangeText(records.map(\.dateID))) {
                DetailedDailyBarChart(
                    values: records.map {
                        DetailDailyValue(
                            dateID: $0.dateID,
                            value: Double($0.keyCount),
                            tooltip: StatsL10n.format("statistics.typing.daily_tooltip", $0.dateID, $0.keyCount, formatDuration($0.activeSeconds))
                        )
                    },
                    color: .cyan
                )
                    .frame(height: 202)
            }

            DetailSection(title: StatsL10n.text("statistics.daily_details")) {
                LazyVStack(spacing: 0) {
                    ForEach(records.reversed()) { record in
                        HStack {
                            Text(record.dateID)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(formatDuration(record.activeSeconds))
                                .foregroundStyle(.secondary)
                            Text(StatsL10n.format("statistics.keys", compactNumber(record.keyCount)))
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
        store.snapshots[selectedRange]
    }

    private var period: WakaTimePeriod? {
        store.period(for: selectedRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Picker(StatsL10n.text("statistics.development.period"), selection: $selectedRange) {
                    ForEach(WakaTimeRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    store.refresh()
                } label: {
                    Label(StatsL10n.text("wakatime.refresh"), systemImage: "arrow.clockwise")
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
                    Text(StatsL10n.text("statistics.development.empty"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(store.state.statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .onAppear {
            store.loadSnapshotIfNeeded(for: selectedRange)
        }
        .onChange(of: selectedRange) { _, range in
            store.loadSnapshotIfNeeded(for: range)
        }
    }

    private var matchesLoadingState: Bool {
        if case .loading = store.state { return true }
        return false
    }

    @ViewBuilder
    private func developmentContent(_ snapshot: WakaTimeSnapshot) -> some View {
        DetailSection(title: StatsL10n.text("statistics.development.overview"), subtitle: store.state.statusText) {
            DetailMetricGrid(items: [
                (StatsL10n.text("wakatime.today"), compactDuration(store.todayPeriod?.totalSeconds ?? 0)),
                ("\(selectedRange.title)", compactDuration(period?.totalSeconds ?? snapshot.totalSeconds)),
                (StatsL10n.text("statistics.typing.active_daily_average"), compactDuration(period?.averageActiveDaySeconds ?? 0)),
                (StatsL10n.text("statistics.typing.active_days"), StatsL10n.format("statistics.days", period?.activeDayCount ?? 0))
            ])
        }

        if let period, !period.dailyRecords.isEmpty {
            DetailSection(title: StatsL10n.text("statistics.development.daily_coding_duration"), subtitle: dateRangeText(period.dailyRecords.map(\.dateID))) {
                DetailedDailyBarChart(
                    values: period.dailyRecords.map {
                        DetailDailyValue(
                            dateID: $0.dateID,
                            value: $0.totalSeconds,
                            tooltip: StatsL10n.format("statistics.development.daily_tooltip", $0.dateID, compactDuration($0.totalSeconds))
                        )
                    },
                    color: .blue
                )
                .frame(height: 202)
            }
        }

        DetailSection(title: StatsL10n.text("wakatime.languages"), subtitle: StatsL10n.text("statistics.development.wakatime_aggregation")) {
            BreakdownList(values: Array(snapshot.languages.prefix(5)), color: .blue)
        }

        if let aiCoding = snapshot.categories.first(where: { $0.name.caseInsensitiveCompare("AI Coding") == .orderedSame }) {
            DetailSection(title: "AI Coding", subtitle: StatsL10n.format("statistics.development.ai_coding_share", aiCoding.percent)) {
                DetailMetricGrid(items: [
                    (StatsL10n.text("statistics.development.ai_duration"), compactDuration(aiCoding.totalSeconds)),
                    (StatsL10n.text("statistics.development.ai_share"), String(format: "%.1f%%", aiCoding.percent)),
                    (StatsL10n.text("statistics.development.input_tokens"), compactNumber(snapshot.aiInputTokens)),
                    (StatsL10n.text("statistics.development.output_tokens"), compactNumber(snapshot.aiOutputTokens))
                ])
            }
        }

        if !snapshot.aiModelBreakdown.isEmpty {
            DetailSection(title: StatsL10n.text("statistics.development.ai_models"), subtitle: snapshot.aiModelTotalCost > 0 ? StatsL10n.format("statistics.development.model_total_cost", snapshot.aiModelTotalCost) : nil) {
                LazyVStack(spacing: 0) {
                    ForEach(snapshot.aiModelBreakdown) { model in
                        HStack {
                            Text(model.name)
                                .lineLimit(1)
                            Spacer()
                            Text(StatsL10n.format("statistics.lines", compactNumber(Double(model.lines))))
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
            DetailSection(title: StatsL10n.text("statistics.development.editors")) {
                BreakdownList(values: Array(snapshot.editors.prefix(3)), color: .purple)
            }
        }

        Text(StatsL10n.text("statistics.development.privacy"))
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
        .background(.regularMaterial)
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
    let tooltip: String

    var id: String { dateID }
}

private struct DetailedDailyBarChart: View {
    let values: [DetailDailyValue]
    let color: Color
    @State private var hoveredEntryID: String?

    private var hoveredEntry: DetailDailyValue? {
        values.first { $0.id == hoveredEntryID }
    }

    var body: some View {
        GeometryReader { proxy in
            let tooltipHeight: CGFloat = 46
            let tooltipWidth: CGFloat = 164
            let gap: CGFloat = 6
            let barAreaHeight = max(3, proxy.size.height - tooltipHeight - gap)
            let axisHeight: CGFloat = 16
            let axisGap: CGFloat = 3
            let plotHeight = max(3, barAreaHeight - axisHeight - axisGap)
            let maximum = max(values.map(\.value).max() ?? 0, 1)
            let spacing: CGFloat = values.count > 14 ? 2 : 4
            let width = max(3, (proxy.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))

            VStack(spacing: gap) {
                ZStack(alignment: .topLeading) {
                    if let hoveredEntry,
                       let index = values.firstIndex(where: { $0.id == hoveredEntry.id }) {
                        // Keep the bubble in the reserved tooltip lane. It
                        // follows the hovered column horizontally, but can
                        // neither escape the card nor overlap any columns.
                        let columnCenter = CGFloat(index) * (width + spacing) + width / 2
                        let tooltipCenter = min(
                            max(tooltipWidth / 2, columnCenter),
                            max(tooltipWidth / 2, proxy.size.width - tooltipWidth / 2)
                        )
                        Text(hoveredEntry.tooltip)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(width: tooltipWidth, height: tooltipHeight, alignment: .leading)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
                            .position(x: tooltipCenter, y: tooltipHeight / 2)
                    } else {
                        Text(StatsL10n.text("statistics.chart.hover_hint"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(height: tooltipHeight)

                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(values) { entry in
                            dailyBar(
                                entry,
                                width: width,
                                height: max(3, plotHeight * CGFloat(entry.value / maximum))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: plotHeight, alignment: .bottom)

                    dateAxis(
                        totalWidth: proxy.size.width,
                        plotHeight: plotHeight,
                        axisGap: axisGap,
                        axisHeight: axisHeight,
                        columnWidth: width,
                        spacing: spacing
                    )
                }
                .frame(height: barAreaHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StatsL10n.text("statistics.chart.daily_trend"))
    }

    private func dailyBar(_ entry: DetailDailyValue, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(3, width / 2))
            .fill(entry.value > 0 ? color.opacity(0.84) : Color.secondary.opacity(0.14))
            .frame(width: width, height: height)
            .onHover { updateHover(for: entry, isHovering: $0) }
            .accessibilityLabel(entry.tooltip)
    }

    private func dateAxis(
        totalWidth: CGFloat,
        plotHeight: CGFloat,
        axisGap: CGFloat,
        axisHeight: CGFloat,
        columnWidth: CGFloat,
        spacing: CGFloat
    ) -> some View {
        let labelWidth: CGFloat = 34
        return ZStack(alignment: .topLeading) {
            ForEach(dateTickIndices, id: \.self) { index in
                let columnCenter = CGFloat(index) * (columnWidth + spacing) + columnWidth / 2
                let labelCenter = min(
                    max(labelWidth / 2, columnCenter),
                    max(labelWidth / 2, totalWidth - labelWidth / 2)
                )
                Text(shortDate(values[index].dateID))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth)
                    .position(x: labelCenter, y: plotHeight + axisGap + axisHeight / 2)
            }
        }
    }

    private var dateTickIndices: [Int] {
        guard !values.isEmpty else { return [] }
        if values.count <= 7 { return Array(values.indices) }

        let tickStride = values.count <= 14 ? 3 : 5
        var indices = Array(stride(from: 0, to: values.count, by: tickStride))
        if indices.last != values.count - 1 {
            indices.append(values.count - 1)
        }
        return indices
    }

    private func shortDate(_ dateID: String) -> String {
        let parts = dateID.split(separator: "-")
        guard parts.count == 3 else { return dateID }
        return "\(parts[1])/\(parts[2])"
    }

    private func updateHover(for entry: DetailDailyValue, isHovering: Bool) {
        if isHovering {
            hoveredEntryID = entry.id
        } else if hoveredEntryID == entry.id {
            hoveredEntryID = nil
        }
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
    return minutes >= 60 ? StatsL10n.format("statistics.duration", minutes / 60, minutes % 60) : StatsL10n.format("statistics.minutes", minutes)
}

private func dateRangeText(_ dateIDs: [String]) -> String? {
    guard let first = dateIDs.first, let last = dateIDs.last else { return nil }
    return "\(first) — \(last)"
}
