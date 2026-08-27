import SwiftUI

struct CodexUsageView: View {
    @ObservedObject var store: CodexAccountsUsageStore

    private var visibleAccounts: [CodexAccountConfiguration] {
        store.accounts.filter(\.isDashboardVisible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if visibleAccounts.isEmpty {
                Text("尚未启用 Codex 使用情况展示。")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleAccounts) { account in
                    CodexAccountUsageRow(
                        account: account,
                        state: store.state(for: account.id),
                        onRefresh: { store.refresh(accountID: account.id) }
                    )
                    if account.id != visibleAccounts.last?.id {
                        Divider()
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
            .help("刷新全部 Codex 账号")
        }
    }
}

private struct CodexAccountUsageRow: View {
    let account: CodexAccountConfiguration
    let state: CodexUsageState
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(state.snapshot?.account.email ?? account.displayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(account.id == CodexAccountConfiguration.defaultAccountID ? "默认" : "配置")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(AppColors.badge)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                if let planType = state.snapshot?.account.planType, !planType.isEmpty {
                    Text(planType.capitalized)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(AppColors.badge)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Spacer(minLength: 0)
                if let snapshot = state.snapshot {
                    Text("更新 \(snapshot.fetchedAt, style: .time)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("刷新 \(account.displayName)")
            }

            switch state {
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
                    Text(error.localizedDescription)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
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
                    Text("用量 \(used)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Text("剩余 \(100 - used)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                        .fixedSize()
                    Spacer(minLength: 4)
                    if let resetsAt = primary.resetsAt {
                        Text("重置：\(resetsAt, style: .relative)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                ProgressView(value: min(100, max(0, 100 - primary.usedPercent)) / 100)
                    .controlSize(.mini)
                    .tint(.green)

                if let secondary = snapshot.secondary {
                    HStack(spacing: 8) {
                        Text("周使用量 \(percentage(secondary.usedPercent))%")
                        if let resetsAt = secondary.resetsAt {
                            Text("周重置：\(resetsAt, style: .relative)")
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            } else {
                Text("账号已登录，但暂时没有额度信息")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentage(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

}
