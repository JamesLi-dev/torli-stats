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
                Text("上次成功刷新：\(lastRefresh, style: .time)")
            } else {
                Text("尚未成功刷新")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help("Codex Home：\(validation.resolvedPath)")
    }
}
