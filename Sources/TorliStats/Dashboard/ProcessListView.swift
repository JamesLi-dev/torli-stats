import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessRow]
    let density: DashboardDensity
    let displayMode: ProcessSortOption
    let showPID: Bool

    private var showsCPU: Bool { displayMode != .memory }
    private var showsMemory: Bool { displayMode != .cpu }

    private var displayedProcesses: [ProcessRow] {
        switch density {
        case .compact: return Array(processes.prefix(3))
        case .standard, .detailed: return processes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(StatsL10n.text("dashboard.high_usage_processes"), systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    if density == .detailed && showPID {
                        Text("PID")
                            .frame(width: 42, alignment: .trailing)
                    }
                    if showsCPU {
                        Text("CPU")
                            .frame(width: 62, alignment: .trailing)
                    }
                    if showsMemory {
                        Text(StatsL10n.text("module.memory"))
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
                ForEach(displayedProcesses) { process in
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
                                .foregroundStyle(process.cpu > 20 ? .orange : .secondary)
                                .frame(width: 62, alignment: .trailing)
                        }
                        if showsMemory {
                            Text(formatMemory(process.memory))
                                .foregroundStyle(.secondary)
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(8)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func formatMemory(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", bytes / 1_000_000_000) }
        return String(format: "%.0f MB", bytes / 1_000_000)
    }
}
