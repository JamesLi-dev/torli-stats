import SwiftUI

struct WakaTimeUsageView: View {
    @ObservedObject var store: WakaTimeUsageStore
    let range: WakaTimeRange
    let density: DashboardDensity
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            header

            switch store.state {
            case .notConfigured:
                Text(StatsL10n.text("wakatime.not_configured"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .loading(let snapshot):
                if let snapshot {
                    snapshotContent(snapshot, status: StatsL10n.text("wakatime.refreshing"))
                } else {
                    ProgressView(StatsL10n.text("wakatime.syncing"))
                        .controlSize(.small)
                        .font(.caption)
                }
            case .available(let snapshot, let refreshedAt):
                snapshotContent(snapshot, status: StatsL10n.format("wakatime.status.updated_at", refreshedAt.formatted(date: .omitted, time: .shortened)))
            case .unavailable(let message, let snapshot):
                if let snapshot {
                    snapshotContent(snapshot, status: StatsL10n.format("wakatime.cached", message))
                } else {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(density == .compact ? 8 : 10)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label(StatsL10n.text("wakatime.dashboard_title"), systemImage: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if density != .compact {
                Text(StatsL10n.text("wakatime.details_30_days"))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(AppColors.badge)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Spacer()
            Button(action: onDetails) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(StatsL10n.text("wakatime.open_details"))
            if case .available(_, let refreshedAt) = store.state {
                Text(StatsL10n.format("wakatime.updated", refreshedAt.formatted(date: .omitted, time: .shortened)))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(StatsL10n.text("wakatime.refresh"))
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: WakaTimeSnapshot, status: String) -> some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            durationSummary

            if density == .compact {
                aiCodingSummary(snapshot)
            } else {
                statisticsSection(title: StatsL10n.text("wakatime.languages"), values: snapshot.languages, limit: density == .standard ? 3 : 5)

                Divider()

                if density == .standard {
                    aiCodingSummary(snapshot)
                } else {
                    statisticsSection(title: "AI Coding", values: snapshot.categories, limit: 5)
                }

                if density == .detailed,
                   snapshot.aiInputTokens > 0 || snapshot.aiCachedInputTokens > 0 || snapshot.aiOutputTokens > 0 {
                    Divider()
                    tokenSection(snapshot)
                }
            }

            if density != .compact, shouldShowStatusFooter {
                Text(status)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var durationSummary: some View {
        if density == .detailed {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                durationValue(title: StatsL10n.text("wakatime.today"), seconds: store.todayPeriod?.totalSeconds)
                durationValue(title: StatsL10n.text("wakatime.daily_average"), seconds: store.lastSevenDaysPeriod?.averageActiveDaySeconds)
                durationValue(title: StatsL10n.text("wakatime.last_7_days"), seconds: store.lastSevenDaysPeriod?.totalSeconds)
                durationValue(title: StatsL10n.text("wakatime.last_30_days"), seconds: store.lastThirtyDaysPeriod?.totalSeconds)
            }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                durationValue(title: StatsL10n.text("wakatime.today"), seconds: store.todayPeriod?.totalSeconds)
                durationValue(title: StatsL10n.text("wakatime.last_7_days"), seconds: store.lastSevenDaysPeriod?.totalSeconds)
            }
        }
    }

    private var shouldShowStatusFooter: Bool {
        if case .available = store.state { return false }
        return true
    }

    private func durationValue(title: String, seconds: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(seconds.map(compactDuration) ?? "—")
                .font(.system(size: density == .compact ? 16 : (density == .detailed ? 14 : 19), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StatsL10n.format("wakatime.duration_accessibility", title))
    }

    private func statisticsSection(title: String, values: [WakaTimeBreakdown], limit: Int) -> some View {
        let topValues = Array(values.prefix(limit))
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(topValues) { value in
                HStack(spacing: 7) {
                    Text(value.name)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 76, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.82))
                            .frame(width: max(2, proxy.size.width * min(1, value.percent / 100)))
                            .frame(maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 3)
                    Text(compactDuration(value.totalSeconds))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 48, alignment: .trailing)
                }
                .help(StatsL10n.format("wakatime.breakdown_help", value.name, value.text, value.percent))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StatsL10n.format("wakatime.statistics_accessibility", title))
    }

    private func aiCodingSummary(_ snapshot: WakaTimeSnapshot) -> some View {
        let value = snapshot.categories.first { $0.name.caseInsensitiveCompare("AI Coding") == .orderedSame }
        return HStack(spacing: 7) {
            Text("AI Coding")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(width: 76, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.accentColor.opacity(0.82))
                    .frame(width: max(2, proxy.size.width * min(1, (value?.percent ?? 0) / 100)))
                    .frame(maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 3)
            Text(value.map { "\(compactDuration($0.totalSeconds)) · \(String(format: "%.0f", $0.percent))%" } ?? "—")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 82, alignment: .trailing)
        }
        .help(value.map { StatsL10n.format("wakatime.ai_coding_help", $0.text, $0.percent) } ?? StatsL10n.text("wakatime.ai_coding_empty"))
    }

    private func tokenSection(_ snapshot: WakaTimeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Text(StatsL10n.text("wakatime.tokens"))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                tokenValue(title: StatsL10n.text("wakatime.input"), value: snapshot.aiInputTokens)
                    .frame(maxWidth: .infinity, alignment: .leading)
                tokenValue(title: StatsL10n.text("wakatime.cached_input"), value: snapshot.aiCachedInputTokens)
                    .frame(maxWidth: .infinity, alignment: .leading)
                tokenValue(title: StatsL10n.text("wakatime.output"), value: snapshot.aiOutputTokens)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !snapshot.aiModelBreakdown.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(StatsL10n.text("wakatime.models"))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(snapshot.aiModelBreakdown) { model in
                            HStack(spacing: 5) {
                                Text(model.name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(StatsL10n.format("statistics.lines", compactNumber(Double(model.lines))))
                                    .foregroundStyle(.secondary)
                                if model.cost > 0 {
                                    Text(String(format: "$%.2f", model.cost))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StatsL10n.text("wakatime.ai_tokens_models_accessibility"))
    }

    private func tokenValue(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(compactNumber(value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
    }

    private func compactDuration(_ seconds: Double) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func compactNumber(_ value: Double) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        default: return String(Int(value))
        }
    }
}
