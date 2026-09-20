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
                DashboardEmptyState(
                    icon: "link",
                    message: StatsL10n.text("wakatime.not_configured"),
                    tint: DashboardPalette.diskProgress,
                    action: onDetails,
                    actionHelp: StatsL10n.text("wakatime.open_details")
                )
            case .loading(let snapshot):
                if let snapshot {
                    snapshotContent(snapshot, status: StatsL10n.text("wakatime.refreshing"))
                } else {
                    DashboardStatusSurface(tint: DashboardPalette.diskProgress) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(StatsL10n.text("wakatime.syncing"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .available(let snapshot, let refreshedAt):
                snapshotContent(snapshot, status: StatsL10n.format("wakatime.status.updated_at", refreshedAt.formatted(date: .omitted, time: .shortened)))
            case .unavailable(let message, let snapshot):
                if let snapshot {
                    snapshotContent(snapshot, status: StatsL10n.format("wakatime.cached", message))
                } else {
                    DashboardStatusSurface(tint: DashboardPalette.diskProgress) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(density == .compact ? 8 : 10)
        .dashboardCardSurface()
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label(StatsL10n.text("wakatime.dashboard_title"), systemImage: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if density != .compact {
                DashboardChip(
                    text: StatsL10n.text("wakatime.details_30_days"),
                    tint: DashboardPalette.diskProgress,
                    fontSize: 8,
                    weight: .semibold,
                    cornerRadius: 5
                )
            }
            Spacer()
            Button(action: onDetails) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(DashboardIconButtonStyle())
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
            .buttonStyle(DashboardIconButtonStyle())
            .foregroundStyle(.secondary)
            .help(StatsL10n.text("wakatime.refresh"))
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: WakaTimeSnapshot, status: String) -> some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            durationSummary

            if density == .detailed {
                statisticsSection(title: StatsL10n.text("wakatime.languages"), values: snapshot.languages, limit: 3)
                Divider()
                aiCodingSummary(snapshot)

                if snapshot.aiInputTokens > 0 || snapshot.aiCachedInputTokens > 0 || snapshot.aiOutputTokens > 0 {
                    Divider()
                    tokenSection(snapshot)
                }
            } else {
                Divider()
                aiCodingSummary(snapshot)
            }

            if density != .compact, shouldShowStatusFooter {
                Text(status)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var durationSummary: some View {
        Group {
            if density == .detailed {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    durationValue(title: StatsL10n.text("wakatime.today"), seconds: store.todayPeriod?.totalSeconds, emphasized: true)
                    durationValue(title: StatsL10n.text("wakatime.daily_average"), seconds: store.lastSevenDaysPeriod?.averageActiveDaySeconds)
                    durationValue(title: StatsL10n.text("wakatime.last_7_days"), seconds: store.lastSevenDaysPeriod?.totalSeconds)
                    durationValue(title: StatsL10n.text("wakatime.last_30_days"), seconds: store.lastThirtyDaysPeriod?.totalSeconds)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    durationValue(title: StatsL10n.text("wakatime.today"), seconds: store.todayPeriod?.totalSeconds, emphasized: true)
                    durationValue(title: StatsL10n.text("wakatime.last_7_days"), seconds: store.lastSevenDaysPeriod?.totalSeconds)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.026))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.black.opacity(0.07)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
        }
    }

    private var shouldShowStatusFooter: Bool {
        if case .available = store.state { return false }
        return true
    }

    private func durationValue(title: String, seconds: Double?, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(seconds.map(compactDuration) ?? "—")
                .font(.system(size: density == .compact ? 16 : (density == .detailed ? 14 : 19), weight: .bold, design: .rounded))
                .foregroundStyle(emphasized ? DashboardPalette.diskProgress : .primary)
                .contentTransition(.numericText())
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
                    DashboardProgressBar(value: value.percent / 100, tint: Color.accentColor.opacity(0.82))
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
            DashboardProgressBar(value: (value?.percent ?? 0) / 100, tint: Color.accentColor.opacity(0.82))
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
