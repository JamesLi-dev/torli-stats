import SwiftUI

struct WakaTimeUsageView: View {
    @ObservedObject var store: WakaTimeUsageStore
    let range: WakaTimeRange
    let density: DashboardDensity

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            header

            switch store.state {
            case .notConfigured:
                Text("请先在设置中配置自己的 WakaTime API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .loading(let snapshot):
                if let snapshot {
                    snapshotContent(snapshot, status: "正在刷新")
                } else {
                    ProgressView("正在同步 WakaTime 数据")
                        .controlSize(.small)
                        .font(.caption)
                }
            case .available(let snapshot, let refreshedAt):
                snapshotContent(snapshot, status: "更新于 \(refreshedAt.formatted(date: .omitted, time: .shortened))")
            case .unavailable(let message, let snapshot):
                if let snapshot {
                    snapshotContent(snapshot, status: "\(message) · 显示缓存")
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
            Label("开发统计", systemImage: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if density != .compact {
                Text("近 30 天明细")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(AppColors.badge)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Spacer()
            if case .available(_, let refreshedAt) = store.state {
                Text("更新 \(refreshedAt.formatted(date: .omitted, time: .shortened))")
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
            .help("刷新 WakaTime 数据")
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: WakaTimeSnapshot, status: String) -> some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            durationSummary

            if density == .compact {
                aiCodingSummary(snapshot)
            } else {
                statisticsSection(title: "语言", values: snapshot.languages, limit: density == .standard ? 3 : 5)

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
                durationValue(title: "今天", seconds: store.todayPeriod?.totalSeconds)
                durationValue(title: "日均", seconds: store.lastSevenDaysPeriod?.averageActiveDaySeconds)
                durationValue(title: "近 7 天", seconds: store.lastSevenDaysPeriod?.totalSeconds)
                durationValue(title: "近 30 天", seconds: store.lastThirtyDaysPeriod?.totalSeconds)
            }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                durationValue(title: "今天", seconds: store.todayPeriod?.totalSeconds)
                durationValue(title: "近 7 天", seconds: store.lastSevenDaysPeriod?.totalSeconds)
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
        .accessibilityLabel("\(title)编码时长")
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
                .help("\(value.name)：\(value.text)，\(String(format: "%.2f", value.percent))%")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)统计")
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
        .help(value.map { "AI Coding：\($0.text)，\(String(format: "%.2f", $0.percent))%" } ?? "暂无 AI Coding 分类数据")
    }

    private func tokenSection(_ snapshot: WakaTimeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Text("Token")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                tokenValue(title: "输入", value: snapshot.aiInputTokens)
                tokenValue(title: "缓存", value: snapshot.aiCachedInputTokens)
                tokenValue(title: "输出", value: snapshot.aiOutputTokens)
                Spacer(minLength: 0)
            }

            if !snapshot.aiModelBreakdown.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("模型")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(snapshot.aiModelBreakdown) { model in
                            HStack(spacing: 5) {
                                Text(model.name)
                                    .lineLimit(1)
                                Text("\(compactNumber(Double(model.lines))) 行")
                                    .foregroundStyle(.secondary)
                                if model.cost > 0 {
                                    Text(String(format: "$%.2f", model.cost))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Token 与模型统计")
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
