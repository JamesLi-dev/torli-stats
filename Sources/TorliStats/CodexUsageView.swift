import SwiftUI

struct CodexUsageView: View {
    private static let collapsedAccountLimit = 2

    @ObservedObject var store: CodexAccountsUsageStore
    let onDisplayCountChange: (Int) -> Void
    @State private var showsAllAccounts = false

    init(
        store: CodexAccountsUsageStore,
        onDisplayCountChange: @escaping (Int) -> Void = { _ in }
    ) {
        self.store = store
        self.onDisplayCountChange = onDisplayCountChange
    }

    private var visibleAccounts: [CodexAccountConfiguration] {
        store.accounts.filter(\.isDashboardVisible)
    }

    private var displayedAccounts: [CodexAccountConfiguration] {
        showsAllAccounts
            ? visibleAccounts
            : Array(visibleAccounts.prefix(Self.collapsedAccountLimit))
    }

    private var hiddenAccountCount: Int {
        max(0, visibleAccounts.count - Self.collapsedAccountLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if visibleAccounts.isEmpty {
                Text("尚未启用 Codex 使用情况展示。")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedAccounts) { account in
                    CodexAccountUsageRow(
                        account: account,
                        state: store.state(for: account.id),
                        onRefresh: { store.refresh(accountID: account.id) }
                    )
                    if account.id != displayedAccounts.last?.id {
                        Divider()
                    }
                }

                if hiddenAccountCount > 0 {
                    Divider()
                    Button(showsAllAccounts ? "收起其他账号" : "显示其余 \(hiddenAccountCount) 个账号") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsAllAccounts.toggle()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .onAppear(perform: notifyDisplayCountChange)
        .onChange(of: showsAllAccounts) { _ in
            notifyDisplayCountChange()
        }
        .onChange(of: visibleAccounts.count) { count in
            if count <= Self.collapsedAccountLimit {
                showsAllAccounts = false
            }
            notifyDisplayCountChange()
        }
    }

    private func notifyDisplayCountChange() {
        DispatchQueue.main.async {
            onDisplayCountChange(displayedAccounts.count)
        }
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
                        .foregroundStyle(quotaColor(forRemaining: 100 - primary.usedPercent))
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
                    .tint(quotaColor(forRemaining: 100 - primary.usedPercent))

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

    private func quotaColor(forRemaining remaining: Double) -> Color {
        switch remaining {
        case ..<20: return .red
        case ...50: return .orange
        default: return .green
        }
    }

}
