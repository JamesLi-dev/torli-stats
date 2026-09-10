import SwiftUI

struct CodexHomeStatusView: View {
    let account: CodexAccountConfiguration
    @ObservedObject var codexUsageStore: CodexAccountsUsageStore

    private var validation: CodexHomeValidation {
        CodexUsageClient.validate(homePath: account.homePath)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: validation.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(validation.isReady ? .green : .orange)
            Text(validation.summary)
            Spacer(minLength: 4)
            if let lastRefresh = codexUsageStore.lastSuccessfulRefresh(for: account.id) {
                Text(StatsL10n.format("codex.home.last_refresh", lastRefresh.formatted(date: .omitted, time: .shortened)))
            } else {
                Text(StatsL10n.text("codex.home.no_refresh"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(StatsL10n.format("codex.home.path", validation.resolvedPath))
    }
}
