import SwiftUI

struct CodexUsageView: View {
    private static let collapsedAccountLimit = 2

    @ObservedObject var store: CodexAccountsUsageStore
    @ObservedObject var activityService: CodexTokenActivityService
    let showsTokenActivity: Bool
    let isPrivacyMode: Bool
    let density: DashboardDensity
    let onDisplayCountChange: (Int) -> Void
    let onOpenSettings: (SettingsCategory) -> Void
    @State private var showsAllAccounts = false

    init(
        store: CodexAccountsUsageStore,
        activityService: CodexTokenActivityService,
        showsTokenActivity: Bool,
        isPrivacyMode: Bool = false,
        density: DashboardDensity = .standard,
        onDisplayCountChange: @escaping (Int) -> Void = { _ in },
        onOpenSettings: @escaping (SettingsCategory) -> Void = { _ in }
    ) {
        self.store = store
        self.activityService = activityService
        self.showsTokenActivity = showsTokenActivity
        self.isPrivacyMode = isPrivacyMode
        self.density = density
        self.onDisplayCountChange = onDisplayCountChange
        self.onOpenSettings = onOpenSettings
    }

    private var visibleAccounts: [CodexAccountConfiguration] {
        store.accounts.filter(\.isDashboardVisible)
    }

    private var collapsedLimit: Int {
        Self.collapsedAccountLimit
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

            if showsTokenActivity {
                VStack(alignment: .leading, spacing: 0) {
                    ActivityHeatmap(title: StatsL10n.text("activity.tokens"), records: activityService.records, compact: true, range: .sixMonths) {
                        StatsL10n.format("activity.token_value", StatisticsFormatting.tokenCount($0))
                    }
                    .help(StatsL10n.text("codex.settings.token_activity_help"))
                    if activityService.isLoading || activityService.status != nil {
                        Text(activityService.isLoading ? StatsL10n.text("activity.loading") : activityService.status ?? "")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    // Month labels are drawn with an offset beyond the compact
                    // heatmap's layout bounds, so their visual bottom edge needs
                    // extra clearance before the divider.
                    Divider()
                        .padding(.top, 24)
                        .padding(.bottom, 5)
                }
            }

            if visibleAccounts.isEmpty {
                DashboardEmptyState(
                    icon: "command.circle",
                    message: StatsL10n.text("codex.usage.not_enabled"),
                    tint: DashboardPalette.quotaWarning,
                    action: { onOpenSettings(.development) },
                    actionHelp: StatsL10n.text("codex.settings.title")
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(displayedAccounts) { account in
                        CodexAccountUsageRow(
                            account: account,
                            state: store.state(for: account.id),
                            displayName: isPrivacyMode ? privateLabel(for: account) : account.resolvedDisplayName,
                            density: density,
                            onRefresh: { store.refresh(accountID: account.id) }
                        )
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
        .dashboardCardSurface()
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
                activityService.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(DashboardIconButtonStyle())
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

    private var accountAccent: Color {
        account.id == CodexAccountConfiguration.defaultAccountID
            ? DashboardPalette.quotaSuccess
            : DashboardPalette.diskProgress
    }

    var body: some View {
        HStack(spacing: 7) {
            if let primary = state.snapshot?.primary {
                quotaRing(primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .help(accountHelp)
                    Button(action: onRefresh) {
                        if case .loading = state {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .frame(width: 14, height: 14)
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
                        DashboardStatusSurface {
                            Text(error.localizedDescription)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .top)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.026))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accountAccent.opacity(0.024))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            accountAccent.opacity(0.10),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
    }

    private func quotaRing(_ primary: CodexUsageWindow) -> some View {
        let remaining = 100 - percentage(primary.usedPercent)
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, 100 - primary.usedPercent)) / 100))
                .stroke(quotaColor(forRemaining: 100 - primary.usedPercent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(remaining)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 34, height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatsL10n.format("codex.usage.remaining_percent", remaining))
        .help(StatsL10n.format("codex.usage.remaining_percent", remaining))
    }

    private var accountHelp: String {
        var lines = [displayName, StatsL10n.text(account.id == CodexAccountConfiguration.defaultAccountID
            ? "codex.usage.default" : "codex.usage.configured")]
        if let snapshot = state.snapshot {
            if let plan = snapshot.account.planType, !plan.isEmpty { lines.append(plan) }
            lines.append(StatsL10n.format("codex.usage.updated", snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)))
            if let credits = creditsText(for: snapshot.credits) { lines.append(credits) }
        }
        return lines.joined(separator: "\n")
    }

    private var loadingContent: some View {
        DashboardStatusSurface {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(StatsL10n.text("codex.usage.loading"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotContent(_ snapshot: CodexUsageSnapshot, isRefreshing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.isStale() {
                Label(StatsL10n.text("codex.usage.stale"), systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            if let rateLimitReachedType = snapshot.rateLimitReachedType,
               !rateLimitReachedType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(
                    StatsL10n.format("codex.usage.rate_limit_reached", rateLimitReachedType),
                    systemImage: "exclamationmark.octagon.fill"
                )
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
            }
            if let primary = snapshot.primary {
                VStack(alignment: .leading, spacing: 2) {
                    if let resetsAt = primary.resetsAt {
                        Text(StatsL10n.format("codex.usage.reset", resetsAt.formatted(.relative(presentation: .named))))
                    }
                    if let secondary = snapshot.secondary {
                        Text(StatsL10n.format("codex.usage.weekly_remaining_percent", 100 - percentage(secondary.usedPercent)))
                            .help(secondary.resetsAt.map {
                                StatsL10n.format("codex.usage.weekly_reset", $0.formatted(.relative(presentation: .named)))
                            } ?? "")
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

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

    private func creditsText(for credits: CodexCredits?) -> String? {
        guard let credits, credits.shouldDisplay else {
            return nil
        }
        if credits.unlimited {
            return StatsL10n.text("codex.usage.unlimited_credits")
        }
        return StatsL10n.format("codex.usage.credits", credits.balance ?? "—")
    }

    private func quotaColor(forRemaining remaining: Double) -> Color {
        switch remaining {
        case ..<20: return DashboardPalette.quotaCritical
        case ...50: return DashboardPalette.quotaWarning
        default: return DashboardPalette.quotaSuccess
        }
    }

}
