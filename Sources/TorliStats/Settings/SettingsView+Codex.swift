import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var codexSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            codexDefaultDirectorySection
            codexManagedAccountsSection
        }
    }

    private var codexDefaultDirectorySection: some View {
        SettingsSection(title: StatsL10n.text("codex.settings.default_directory")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    codexFieldLabel(StatsL10n.text("codex.settings.default_account"))
                    TextField(StatsL10n.text("codex.settings.display_name"), text: $settings.codexDefaultAccountName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    codexFieldLabel("Codex Home")
                    Text(displayCodexHomePath(defaultCodexAccount.homePath))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(CodexUsageClient.validate(homePath: defaultCodexAccount.homePath).resolvedPath)
                    Button(StatsL10n.text("codex.settings.choose")) {
                        chooseCodexHome()
                    }
                    .buttonStyle(.bordered)
                    Button(StatsL10n.text("codex.settings.test_connection")) {
                        testCodexConnection(for: defaultCodexAccount)
                    }
                    .buttonStyle(.bordered)
                    .disabled(testingCodexAccountIDs.contains(defaultCodexAccount.id))
                }

                HStack(spacing: 10) {
                    Color.clear.frame(width: 90)
                    CodexHomeStatusView(
                        account: defaultCodexAccount,
                        codexUsageStore: codexUsageStore
                    )
                }

                Divider()

                HStack(spacing: 10) {
                    codexFieldLabel(StatsL10n.text("codex.settings.auto_refresh"))
                    Toggle(StatsL10n.text("codex.settings.enable_auto_refresh"), isOn: $settings.codexAutoRefresh)
                        .toggleStyle(.checkbox)
                    Picker("", selection: $settings.codexRefreshInterval) {
                        ForEach(AppSettings.supportedCodexRefreshIntervals, id: \.self) { interval in
                            Text(StatsL10n.format("codex.settings.refresh_interval", interval)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!settings.codexAutoRefresh)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        StatsL10n.text("codex.settings.token_activity"),
                        isOn: $settings.codexTokenActivityEnabled
                    )
                    .toggleStyle(.checkbox)
                    Text(StatsL10n.text("codex.settings.token_activity_help"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 100)
            }
        }
    }

    private var codexManagedAccountsSection: some View {
        SettingsSection(title: StatsL10n.text("codex.settings.managed_accounts")) {
            VStack(alignment: .leading, spacing: 12) {
                if settings.codexManagedAccounts.isEmpty {
                    Text(StatsL10n.text("codex.settings.no_managed_accounts"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach($settings.codexManagedAccounts) { $account in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            TextField(StatsL10n.text("codex.settings.display_name"), text: $account.displayName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                            Spacer(minLength: 0)
                            Toggle(StatsL10n.text("codex.settings.dashboard"), isOn: $account.isDashboardVisible)
                                .toggleStyle(.checkbox)
                            Toggle(StatsL10n.text("codex.settings.status_bar"), isOn: $account.isStatusBarIncluded)
                                .toggleStyle(.checkbox)
                            Button(StatsL10n.text("codex.settings.remove"), role: .destructive) {
                                pendingCodexAccountRemovalID = account.id
                                pendingCodexAccountRemovalName = account.resolvedDisplayName
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack(spacing: 8) {
                            Text(displayCodexHomePath(account.homePath))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(account.homePath)
                            HStack(spacing: 6) {
                                Button(StatsL10n.text("codex.settings.test_connection")) {
                                    testCodexConnection(for: account)
                                }
                                .buttonStyle(.bordered)
                                .disabled(testingCodexAccountIDs.contains(account.id))
                                Button(StatsL10n.text("codex.settings.login_or_relogin")) {
                                    let didStart = settings.startCodexLogin(for: account)
                                    codexAccountMessage = didStart
                                        ? StatsL10n.format("codex.settings.login_started", account.displayName)
                                        : StatsL10n.text("codex.settings.login_failed")
                                }
                                .buttonStyle(.bordered)
                            }
                            .fixedSize()
                        }

                        CodexHomeStatusView(
                            account: account,
                            codexUsageStore: codexUsageStore
                        )
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 8) {
                    Button(StatsL10n.text("codex.settings.add_account")) {
                        newCodexAccountName = ""
                        isAddingCodexAccount = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button(StatsL10n.text("codex.settings.refresh_all")) {
                        onCodexRefresh()
                    }
                    .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                }

                Text(codexAccountMessage ?? StatsL10n.text("codex.settings.managed_accounts_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func codexFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .frame(width: 90, alignment: .leading)
    }

    var addCodexAccountSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(StatsL10n.text("codex.settings.add_account"))
                .font(.headline)
            Text(StatsL10n.text("codex.settings.add_account_help"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(StatsL10n.text("codex.settings.account_name_placeholder"), text: $newCodexAccountName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(StatsL10n.text("common.cancel")) {
                    isAddingCodexAccount = false
                }
                Button(StatsL10n.text("codex.settings.create_and_login")) {
                    guard let account = settings.addCodexManagedAccount(named: newCodexAccountName) else {
                        codexAccountMessage = StatsL10n.text("codex.settings.create_failed")
                        isAddingCodexAccount = false
                        return
                    }
                    let didStart = settings.startCodexLogin(for: account)
                    codexAccountMessage = didStart
                        ? StatsL10n.format("codex.settings.created_and_login_started", account.displayName)
                        : StatsL10n.format("codex.settings.created_cli_missing", account.displayName)
                    isAddingCodexAccount = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 390)
    }

    private var defaultCodexAccount: CodexAccountConfiguration {
        settings.codexAccounts.first { $0.id == CodexAccountConfiguration.defaultAccountID }
            ?? CodexAccountConfiguration.defaultAccount(
                homePath: settings.codexHomePath,
                displayName: settings.codexDefaultAccountName,
                isDashboardVisible: settings.showCodexCard,
                isStatusBarIncluded: settings.showCodexStatusItem
            )
    }

    private func testCodexConnection(for account: CodexAccountConfiguration) {
        let validation = CodexUsageClient.validate(homePath: account.homePath)
        guard validation.isReady else {
            codexAccountMessage = StatsL10n.format("codex.settings.connection_validation_failed", account.resolvedDisplayName, validation.summary)
            return
        }

        testingCodexAccountIDs.insert(account.id)
        codexAccountMessage = StatsL10n.format("codex.settings.testing_connection", account.resolvedDisplayName)
        codexUsageStore.testConnection(for: account) { result in
            DispatchQueue.main.async {
                testingCodexAccountIDs.remove(account.id)
                switch result {
                case .success:
                    codexAccountMessage = StatsL10n.format("codex.settings.connection_succeeded", account.resolvedDisplayName)
                case let .failure(error):
                    codexAccountMessage = StatsL10n.format("codex.settings.connection_failed", account.resolvedDisplayName, error.localizedDescription)
                }
            }
        }
    }

    private func displayCodexHomePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return StatsL10n.text("codex.settings.home_path_automatic") }

        let home = NSHomeDirectory()
        if trimmed == home { return "~" }
        if trimmed.hasPrefix(home + "/") {
            return "~/" + String(trimmed.dropFirst(home.count + 1))
        }
        return trimmed
    }

    private func chooseCodexHome() {
        let panel = NSOpenPanel()
        panel.title = StatsL10n.text("codex.settings.choose_home_title")
        panel.message = StatsL10n.text("codex.settings.choose_home_message")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.codexHomePath.isEmpty ? NSHomeDirectory() : settings.codexHomePath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.codexHomePath = url.path
        }
    }
}
