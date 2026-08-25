import SwiftUI

struct CodexUsageView: View {
    @ObservedObject var store: CodexUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch store.state {
            case .idle:
                loadingContent
            case let .loading(snapshot):
                if let snapshot {
                    snapshotContent(snapshot, isRefreshing: true)
                } else {
                    loadingContent
                }
            case let .available(snapshot):
                snapshotContent(snapshot, isRefreshing: false)
            case let .unavailable(error, snapshot):
                if let snapshot {
                    snapshotContent(snapshot, isRefreshing: false)
                    Text("上次更新失败：\(error.localizedDescription)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error.localizedDescription)
                            .foregroundStyle(.secondary)
                        Text("请确认 Codex CLI 已安装并完成登录。")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var header: some View {
        HStack {
            Label("Codex 使用情况", systemImage: "command.circle")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("刷新 Codex 使用情况")
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取 Codex 使用情况…")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func snapshotContent(_ snapshot: CodexUsageSnapshot, isRefreshing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let primary = snapshot.primary {
                let used = percentage(primary.usedPercent)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(snapshot.account.email ?? "Codex")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let planType = snapshot.account.planType, !planType.isEmpty {
                        Text(planType.capitalized)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(AppColors.badge)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    Text("用量 \(used)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(progressColor(primary.usedPercent))
                        .fixedSize()
                    Text("剩余 \(100 - used)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .help("正在刷新")
                    }
                }

                ProgressView(value: min(100, max(0, primary.usedPercent)) / 100)
                    .tint(progressColor(primary.usedPercent))

                HStack(spacing: 8) {
                    if let resetsAt = primary.resetsAt {
                        Text("重置 \(resetsAt, style: .relative)")
                    }
                    if let credits = snapshot.credits {
                        Text(credits.unlimited ? "Credits：无限制" : (credits.hasCredits ? "Credits：可用" : "Credits：不可用"))
                    }
                    Spacer(minLength: 4)
                    Text("更新 \(snapshot.fetchedAt, style: .time)")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(snapshot.account.email ?? "Codex")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            if let secondary = snapshot.secondary {
                HStack {
                    Text("短窗口")
                    Spacer()
                    Text("已使用 \(percentage(secondary.usedPercent))%")
                    if let resetsAt = secondary.resetsAt {
                        Text("· \(resetsAt, style: .relative)")
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func percentage(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

    private func progressColor(_ usedPercent: Double) -> Color {
        let remaining = 100 - usedPercent
        if remaining < 20 { return .red }
        if remaining <= 50 { return .orange }
        return .green
    }
}
