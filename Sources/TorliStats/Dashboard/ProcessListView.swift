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
            HStack(alignment: .center) {
                Label(StatsL10n.text("dashboard.high_usage_processes"), systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    if density == .detailed && showPID {
                        Text("PID")
                            .frame(width: 42, alignment: .trailing)
                    }
                    if showsCPU {
                        Button {
                            onDisplayModeChange(displayMode == .cpu ? .combined : .cpu)
                        } label: {
                            Text("CPU")
                                .frame(width: 40)
                        }
                        .buttonStyle(DashboardSortHeaderButtonStyle(isSelected: displayMode == .cpu))
                        .font(.system(size: 9, weight: displayMode == .cpu ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(displayMode == .cpu ? DashboardPalette.sortSelection : .secondary)
                        .frame(width: 62, alignment: .trailing)
                    }
                    if showsMemory {
                        Button {
                            onDisplayModeChange(displayMode == .memory ? .combined : .memory)
                        } label: {
                            Text(StatsL10n.text("module.memory"))
                                .frame(width: 40)
                        }
                        .buttonStyle(DashboardSortHeaderButtonStyle(isSelected: displayMode == .memory))
                        .font(.system(size: 9, weight: displayMode == .memory ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(displayMode == .memory ? DashboardPalette.sortSelection : .secondary)
                        .frame(width: 76, alignment: .trailing)
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .frame(height: 18)

            if processes.isEmpty {
                DashboardEmptyState(
                    icon: "chart.bar.xaxis",
                    message: StatsL10n.text("activity.no_data")
                )
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
                                .foregroundStyle(cpuColor(process.cpu))
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.18), value: process.cpu)
                                .frame(width: 62, alignment: .trailing)
                        }
                        if showsMemory {
                            Text(formatMemory(process.memory))
                                .foregroundStyle(memoryColor(process.memory))
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.18), value: process.memory)
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

    private func cpuColor(_ usage: Double) -> Color {
        if usage >= 50 { return DashboardPalette.quotaCritical }
        if usage >= 25 { return DashboardPalette.quotaWarning }
        if usage >= 10 { return DashboardPalette.quotaSuccess }
        return .secondary
    }

    private func memoryColor(_ bytes: Double) -> Color {
        if bytes >= 2_000_000_000 { return DashboardPalette.quotaCritical }
        if bytes >= 1_000_000_000 { return DashboardPalette.quotaWarning }
        if bytes >= 500_000_000 { return DashboardPalette.quotaSuccess }
        return .secondary
    }
}