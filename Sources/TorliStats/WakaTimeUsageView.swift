import SwiftUI

struct WakaTimeUsageView: View {
    @ObservedObject var store: WakaTimeUsageStore
    let range: WakaTimeRange
    let density: DashboardDensity
    let onDetails: () -> Void

    private var isLoading: Bool {
        if case .loading = store.state { return true }
        return false
    }
    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            HStack(spacing: 7) {
                Label(StatsL10n.text("wakatime.dashboard_title"), systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDetails) { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(DashboardIconButtonStyle()).foregroundStyle(.secondary)
                    .help(StatsL10n.text("wakatime.open_details"))
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(DashboardIconButtonStyle()).foregroundStyle(.secondary)
                    .disabled(isLoading).help(StatsL10n.text("wakatime.refresh"))
            }
            if case .notConfigured = store.state {
                DashboardEmptyState(icon: "link", message: StatsL10n.text("wakatime.not_configured"),
                    action: onDetails, actionHelp: StatsL10n.text("wakatime.open_details"))
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(StatsL10n.text("wakatime.today")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(store.todayPeriod.map { StatisticsFormatting.compactDuration($0.totalSeconds) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardPalette.diskProgress)
                }
                if density != .compact, let statistics = FeatureRegistry.shared.statistics {
                    statistics.developmentSummary(store: store)
                }
                Text(store.state.statusText).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(density == .compact ? 8 : 10)
        .dashboardCardSurface()
    }
}
