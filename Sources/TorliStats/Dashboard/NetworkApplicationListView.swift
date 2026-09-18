import SwiftUI

private enum NetworkApplicationSort {
    case total
    case download
    case upload
}

struct NetworkApplicationListView: View {
    let applications: [NetworkApplicationRow]
    let hasSample: Bool
    let density: DashboardDensity
    @State private var sort: NetworkApplicationSort = .total

    private var rowCount: Int {
        switch density {
        case .compact: return 3
        case .standard, .detailed: return 5
        }
    }

    private var displayedApplications: [NetworkApplicationRow] {
        Array(sortedApplications.prefix(rowCount))
    }

    private var sortedApplications: [NetworkApplicationRow] {
        applications.sorted { lhs, rhs in
            let lhsValue: Double
            let rhsValue: Double
            switch sort {
            case .total:
                lhsValue = lhs.totalRate
                rhsValue = rhs.totalRate
            case .download:
                lhsValue = lhs.download
                rhsValue = rhs.download
            case .upload:
                lhsValue = lhs.upload
                rhsValue = rhs.upload
            }
            if lhsValue == rhsValue {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhsValue > rhsValue
        }
    }

    // A network burst can involve only one process and disappear on the next
    // sample. Keep this area stable so the rest of the Dashboard never jumps
    // as applications enter or leave the top list.
    private var rowsHeight: CGFloat {
        CGFloat(rowCount * 22 + max(0, rowCount - 1) * 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(StatsL10n.text("dashboard.network_applications"), systemImage: "network")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Button { sort = sort == .download ? .total : .download } label: {
                        Image(systemName: "arrow.down")
                            .frame(width: 66, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: sort == .download ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(sort == .download ? DashboardPalette.sortSelection : .secondary)
                    .help(StatsL10n.text("dashboard.network_sort_download"))

                    Button { sort = sort == .upload ? .total : .upload } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 66, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: sort == .upload ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(sort == .upload ? DashboardPalette.sortSelection : .secondary)
                    .help(StatsL10n.text("dashboard.network_sort_upload"))
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                if displayedApplications.isEmpty {
                    Text(StatsL10n.text(hasSample ? "dashboard.no_network_applications" : "dashboard.loading_network_applications"))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(displayedApplications.enumerated()), id: \.element.id) { index, application in
                        HStack(spacing: 8) {
                            Text(application.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(formatRate(application.download))
                                .foregroundStyle(.secondary)
                                .frame(width: 66, alignment: .trailing)
                            Text(formatRate(application.upload))
                                .foregroundStyle(.secondary)
                                .frame(width: 66, alignment: .trailing)
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .background(
                            index.isMultiple(of: 2)
                                ? Color.primary.opacity(0.035)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowsHeight, maxHeight: rowsHeight, alignment: .topLeading)
        }
        .padding(8)
        .dashboardCardSurface()
    }

    private func formatRate(_ bytes: Double) -> String {
        if bytes >= 1_024 * 1_024 {
            return String(format: "%.1f MB/s", bytes / 1_024 / 1_024)
        }
        return String(format: "%.0f KB/s", bytes / 1_024)
    }
}
