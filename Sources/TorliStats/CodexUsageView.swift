import SwiftUI

struct CodexUsageView: View {
    private static let collapsedAccountLimit = 2

    @ObservedObject var store: CodexAccountsUsageStore
    let isPrivacyMode: Bool
    let density: DashboardDensity
    let onDisplayCountChange: (Int) -> Void
    @State private var showsAllAccounts = false

    init(
        store: CodexAccountsUsageStore,
        isPrivacyMode: Bool = false,
        density: DashboardDensity = .standard,
        onDisplayCountChange: @escaping (Int) -> Void = { _ in }
    ) {
        self.store = store
        self.isPrivacyMode = isPrivacyMode
        self.density = density
        self.onDisplayCountChange = onDisplayCountChange
    }

    private var visibleAccounts: [CodexAccountConfiguration] {
        store.accounts.filter(\.isDashboardVisible)
    }

    private var collapsedLimit: Int {
        switch density {
        case .compact: return 1
        case .standard: return Self.collapsedAccountLimit
        case .detailed: return 3
        }
    }

    private var displayedAccounts: [CodexAccountConfiguration] {
        showsAllAccounts
            ? visibleAccounts
            : Array(visibleAccounts.prefix(collapsedLimit))
    }

    private var hiddenAccountCount: Int {
        max(0, visibleAccounts.count - collapsedLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if visibleAccounts.isEmpty {
                Text(StatsL10n.text("codex.usage.not_enabled"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedAccounts) { account in
                    CodexAccountUsageRow(
                        account: account,
                        state: store.state(for: account.id),
                        displayName: isPrivacyMode ? privateLabel(for: account) : account.resolvedDisplayName,
                        density: density,
                        onRefresh: { store.refresh(accountID: account.id) }
                    )
                    if account.id != displayedAccounts.last?.id {
                        Divider()
                    }
                }

                if hiddenAccountCount > 0 {
                    Divider()
                    Button(showsAllAccounts ? StatsL10n.text("codex.usage.collapse_accounts") : StatsL10n.format("codex.usage.show_other_accounts", hiddenAccountCount)) {
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
        .padding(density == .compact ? 8 : 10)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .onAppear(perform: notifyDisplayCountChange)
        .onChange(of: showsAllAccounts) { _, _ in
            notifyDisplayCountChange()
        }
        .onChange(of: visibleAccounts.count) { _, count in
            if count <= collapsedLimit {
                showsAllAccounts = false
            }
            notifyDisplayCountChange()
        }
    }

    private func privateLabel(for account: CodexAccountConfiguration) -> String {
        let index = visibleAccounts.firstIndex(where: { $0.id == account.id }) ?? 0
        return "Codex \(index + 1)"
    }

    private func notifyDisplayCountChange() {
        DispatchQueue.main.async {
            onDisplayCountChange(displayedAccounts.count)
        }
    }

    private var header: some View {
        HStack {
            Label(StatsL10n.text("codex.usage.title"), systemImage: "command.circle")
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
            .help(StatsL10n.text("codex.usage.refresh_all"))
        }
    }
}

private struct CodexAccountUsageRow: View {
    let account: CodexAccountConfiguration
    let state: CodexUsageState
    let displayName: String
    let density: DashboardDensity
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(displayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(account.id == CodexAccountConfiguration.defaultAccountID ? StatsL10n.text("codex.usage.default") : StatsL10n.text("codex.usage.configured"))
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
                if density == .detailed, let snapshot = state.snapshot {
                    Text(StatsL10n.format("codex.usage.updated", snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(StatsL10n.format("codex.usage.refresh_account", displayName))
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
            case let .retrying(error, snapshot, attempt, retryAt):
                if let snapshot {
                    snapshotContent(snapshot, isRefreshing: false)
                }
                Text(StatsL10n.format("codex.usage.retrying", error.localizedDescription, retryAt.formatted(.relative(presentation: .named)), attempt))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
            case let .available(snapshot):
                snapshotContent(snapshot, isRefreshing: false)
            case let .unavailable(error, snapshot):
                if let snapshot {
                    snapshotContent(snapshot, isRefreshing: false)
                    Text(StatsL10n.format("codex.usage.last_update_failed", error.localizedDescription))
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
            Text(StatsL10n.text("codex.usage.loading"))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func snapshotContent(_ snapshot: CodexUsageSnapshot, isRefreshing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.isStale() {
                Label(StatsL10n.text("codex.usage.stale"), systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            if let primary = snapshot.primary {
                let used = percentage(primary.usedPercent)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(StatsL10n.format("codex.usage.used_percent", used))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Text(StatsL10n.format("codex.usage.remaining_percent", 100 - used))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(quotaColor(forRemaining: 100 - primary.usedPercent))
                        .fixedSize()
                    Spacer(minLength: 4)
                    if let resetsAt = primary.resetsAt {
                        Text(StatsL10n.format("codex.usage.reset", resetsAt.formatted(.relative(presentation: .named))))
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
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
                    .frame(height: 4)

                if density != .compact, let secondary = snapshot.secondary {
                    HStack(spacing: 8) {
                        Text(StatsL10n.format("codex.usage.weekly_used_percent", percentage(secondary.usedPercent)))
                        if let resetsAt = secondary.resetsAt {
                            Text(StatsL10n.format("codex.usage.weekly_reset", resetsAt.formatted(.relative(presentation: .named))))
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            } else {
                Text(StatsL10n.text("codex.usage.no_quota"))
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
