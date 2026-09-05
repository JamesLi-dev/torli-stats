import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessRow]
    let density: DashboardDensity

    private var displayedProcesses: [ProcessRow] {
        switch density {
        case .compact: return Array(processes.prefix(3))
        case .standard, .detailed: return processes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("高占用进程", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(density == .detailed ? "PID     CPU          内存" : "CPU          内存")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if processes.isEmpty {
                Text("正在读取进程…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedProcesses) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if density == .detailed {
                            Text(String(format: "%5d", process.id))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        Text(String(format: "%5.1f%%", process.cpu))
                            .foregroundStyle(process.cpu > 20 ? .orange : .secondary)
                            .frame(width: 62, alignment: .trailing)
                        Text(formatMemory(process.memory))
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .trailing)
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
