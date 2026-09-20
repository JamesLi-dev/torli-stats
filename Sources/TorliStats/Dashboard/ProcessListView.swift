import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessRow]
    let density: DashboardDensity
    let displayMode: ProcessSortOption
    let showPID: Bool
    let onDisplayModeChange: (ProcessSortOption) -> Void

    private var showsCPU: Bool { true }
    private var showsMemory: Bool { true }

    private var displayedProcesses: [ProcessRow] {
        switch density {
        case .compact: return Array(processes.prefix(3))
        case .standard, .detailed: return processes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(StatsL10n.text("dashboard.high_usage_processes"), systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    if density == .detailed && showPID {
                        Text("PID")
                            .frame(width: 42, alignment: .trailing)
                    }
                    if showsCPU {
                        Button("CPU") {
                            onDisplayModeChange(displayMode == .cpu ? .combined : .cpu)
                        }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: displayMode == .cpu ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(displayMode == .cpu ? DashboardPalette.sortSelection : .secondary)
                            .frame(width: 62, alignment: .trailing)
                    }
                    if showsMemory {
                        Button(StatsL10n.text("module.memory")) {
                            onDisplayModeChange(displayMode == .memory ? .combined : .memory)
                        }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: displayMode == .memory ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(displayMode == .memory ? DashboardPalette.sortSelection : .secondary)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            if processes.isEmpty {
                Text(StatsL10n.text("dashboard.loading_processes"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(displayedProcesses.enumerated()), id: \.element.id) { index, process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if density == .detailed && showPID {
                            Text(String(format: "%5d", process.id))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        if showsCPU {
                            Text(String(format: "%5.1f%%", process.cpu))
                                .foregroundStyle(process.cpu > 20 ? DashboardPalette.quotaWarning : DashboardPalette.diskProgress)
                                .frame(width: 62, alignment: .trailing)
                        }
                        if showsMemory {
                            Text(formatMemory(process.memory))
                                .foregroundStyle(memoryColor(process.memory))
                                .frame(width: 76, alignment: .trailing)
                        }
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
        .padding(8)
        .dashboardCardSurface()
    }

    private func formatMemory(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", bytes / 1_000_000_000) }
        return String(format: "%.0f MB", bytes / 1_000_000)
    }

    private func memoryColor(_ bytes: Double) -> Color {
        if bytes >= 2_000_000_000 { return DashboardPalette.quotaCritical }
        if bytes >= 1_000_000_000 { return DashboardPalette.quotaWarning }
        return .secondary
    }
}
