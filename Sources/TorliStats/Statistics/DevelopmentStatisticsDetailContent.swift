import SwiftUI
import AppKit

struct DevelopmentStatisticsDetailContent: View {
    @ObservedObject var store: WakaTimeUsageStore
    @State private var selectedRange: WakaTimeRange = .last30Days
    @State private var showsTokens = false

    private var snapshot: WakaTimeSnapshot? {
        store.snapshots[selectedRange]
    }

    private var period: WakaTimePeriod? {
        store.period(for: selectedRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSection(
                title: StatsL10n.text("activity.development"),
                headerAccessory: AnyView(
                    ActivityMetricSwitch(showsTokens: $showsTokens)
                )
            ) {
                ActivityHeatmap(
                    title: StatsL10n.text(showsTokens ? "activity.tokens" : "activity.coding_time"),
                    records: activityRecords,
                    color: showsTokens ? .purple : .blue
                ) { value in
                    showsTokens
                        ? StatsL10n.format("activity.token_value", StatisticsFormatting.tokenCount(value))
                        : StatisticsFormatting.compactDuration(value)
                }
                Text(store.activityLoading ? StatsL10n.text("activity.loading") : (store.activityError ?? StatsL10n.text("activity.wakatime_source")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DetailSection(
                title: StatsL10n.text("statistics.development.period"),
                headerAccessory: AnyView(
                    HStack(spacing: 10) {
                        Picker(StatsL10n.text("statistics.development.period"), selection: $selectedRange) {
                            ForEach(WakaTimeRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Button {
                            store.refresh()
                            store.loadActivity(force: true)
                        } label: {
                            Label(StatsL10n.text("wakatime.refresh"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(matchesLoadingState)
                    }
                )
            ) {
                EmptyView()
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
            store.loadActivity()
        }
        .onChange(of: selectedRange) { _, range in
            store.loadSnapshotIfNeeded(for: range)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityRecords: [ActivityDay] {
        let records = store.activityPeriod?.dailyRecords
            ?? ((store.lastThirtyDaysPeriod?.dailyRecords ?? []) + (store.todayPeriod?.dailyRecords ?? []))
        return records.compactMap { record in
            if showsTokens {
                return record.aiTokens.map { ActivityDay(dateID: record.dateID, value: $0) }
            }
            return ActivityDay(dateID: record.dateID, value: record.totalSeconds)
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
                (StatsL10n.text("wakatime.today"), StatisticsFormatting.compactDuration(store.todayPeriod?.totalSeconds ?? 0)),
                ("\(selectedRange.title)", StatisticsFormatting.compactDuration(period?.totalSeconds ?? snapshot.totalSeconds)),
                (StatsL10n.text("statistics.typing.active_daily_average"), StatisticsFormatting.compactDuration(period?.averageActiveDaySeconds ?? 0)),
                (StatsL10n.text("statistics.typing.active_days"), StatsL10n.format("statistics.days", period?.activeDayCount ?? 0))
            ])
        }

        if let period, !period.dailyRecords.isEmpty {
            DetailSection(title: StatsL10n.text("statistics.development.daily_coding_duration"), subtitle: StatisticsFormatting.dateRangeText(period.dailyRecords.map(\.dateID))) {
                DetailedDailyBarChart(
                    values: period.dailyRecords.map {
                        DetailDailyValue(
                            dateID: $0.dateID,
                            value: $0.totalSeconds,
                            tooltip: StatsL10n.format("statistics.development.daily_tooltip", $0.dateID, StatisticsFormatting.compactDuration($0.totalSeconds))
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
                    (StatsL10n.text("statistics.development.ai_duration"), StatisticsFormatting.compactDuration(aiCoding.totalSeconds)),
                    (StatsL10n.text("statistics.development.ai_share"), String(format: "%.1f%%", aiCoding.percent)),
                    (StatsL10n.text("statistics.development.input_tokens"), StatisticsFormatting.compactNumber(snapshot.aiInputTokens)),
                    (StatsL10n.text("statistics.development.output_tokens"), StatisticsFormatting.compactNumber(snapshot.aiOutputTokens))
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
                            Text(StatsL10n.format("statistics.lines", StatisticsFormatting.compactNumber(Double(model.lines))))
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

private struct ActivityMetricSwitch: View {
    @Binding var showsTokens: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(StatsL10n.text("activity.coding_time"), isSelected: !showsTokens) {
                showsTokens = false
            }
            segment("AI Token", isSelected: showsTokens) {
                showsTokens = true
            }
        }
        .frame(width: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func segment(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(isSelected ? Color.accentColor : AppColors.badge)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
