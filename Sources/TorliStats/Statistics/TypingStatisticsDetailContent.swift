import SwiftUI
import AppKit

struct TypingStatisticsDetailContent: View {
    @ObservedObject var typingStats: TypingStatsService
    @State private var selectedPeriod = 7

    private var records: [TypingDailyRecord] {
        typingStats.records(forLastDays: selectedPeriod)
    }

    /// `records(forLastDays:)` fills calendar gaps with zero-value records;
    /// consult persisted records to distinguish those gaps from actual activity.
    private var periodHasActivity: Bool {
        let periodDateIDs = Set(records.map(\.dateID))
        return typingStats.dailyRecords.contains {
            periodDateIDs.contains($0.dateID) && ($0.keyCount > 0 || $0.activeSeconds > 0)
        }
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

    private var heatmapRecords: [ActivityDay] {
        typingStats.dailyRecords.map {
            ActivityDay(dateID: $0.dateID, value: Double($0.keyCount))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSection(title: StatsL10n.text("activity.typing")) {
                ActivityHeatmap(
                    title: StatsL10n.text("statistics.typing.daily_key_count"),
                    records: heatmapRecords,
                    color: .blue
                ) { value in
                    StatsL10n.format("statistics.keys", StatisticsFormatting.compactNumber(value))
                }
                Text(StatsL10n.text("activity.typing_source"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DetailSection(
                title: StatsL10n.text("statistics.typing.overview"),
                subtitle: StatsL10n.text("statistics.typing.privacy"),
                headerAccessory: AnyView(
                    Picker(StatsL10n.text("statistics.typing.period"), selection: $selectedPeriod) {
                        Text(StatsL10n.text("wakatime.last_7_days")).tag(7)
                        Text(StatsL10n.text("wakatime.last_30_days")).tag(30)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel(StatsL10n.text("statistics.typing.period"))
                )
            ) {
                if !periodHasActivity {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text(StatsL10n.text("activity.no_data"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityElement(children: .combine)
                } else {
                    DetailMetricGrid(items: [
                        (StatsL10n.text("statistics.typing.key_count"), StatisticsFormatting.compactNumber(periodTotal)),
                        (StatsL10n.text("statistics.typing.active_days"), StatsL10n.format("statistics.days", activeDays)),
                        (StatsL10n.text("statistics.typing.active_daily_average"), StatisticsFormatting.compactNumber(averagePerActiveDay)),
                        (StatsL10n.text("statistics.typing.peak"), StatisticsFormatting.compactNumber(peakRecord?.keyCount ?? 0))
                    ])
                }
            }

            if periodHasActivity {
                DetailSection(title: StatsL10n.text("statistics.daily_details")) {
                    LazyVStack(spacing: 0) {
                        ForEach(records.reversed()) { record in
                            HStack {
                                Text(record.dateID)
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text(StatisticsFormatting.formatDuration(record.activeSeconds))
                                    .foregroundStyle(.secondary)
                                Text(StatsL10n.format("statistics.keys", StatisticsFormatting.compactNumber(record.keyCount)))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
