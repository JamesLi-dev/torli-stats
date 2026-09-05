import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var codexSection: some View {
        SettingsSection(title: "Codex 账号") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("默认账号")
                            .font(.caption.weight(.semibold))
                            .frame(width: 64, alignment: .leading)
                        TextField("显示名称", text: $settings.codexDefaultAccountName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Text("Codex Home")
                            .font(.caption.weight(.semibold))
                            .frame(width: 64, alignment: .leading)
                        Text(displayCodexHomePath(defaultCodexAccount.homePath))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(CodexUsageClient.validate(homePath: defaultCodexAccount.homePath).resolvedPath)
                        Button("选择") {
                            chooseCodexHome()
                        }
                        .buttonStyle(.bordered)
                        Button("测试连接") {
                            testCodexConnection(for: defaultCodexAccount)
                        }
                        .buttonStyle(.bordered)
                        .disabled(testingCodexAccountIDs.contains(defaultCodexAccount.id))
                    }

                    HStack(spacing: 10) {
                        Color.clear.frame(width: 64)
                        CodexHomeStatusView(
                            account: defaultCodexAccount,
                            codexUsageStore: codexUsageStore
                        )
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Text("自动刷新")
                        .font(.caption.weight(.semibold))
                        .frame(width: 64, alignment: .leading)
                    Toggle("启用 Codex 自动刷新", isOn: $settings.codexAutoRefresh)
                    Picker("", selection: $settings.codexRefreshInterval) {
                        ForEach(AppSettings.supportedCodexRefreshIntervals, id: \.self) { interval in
                            Text("每 \(interval) 分钟").tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!settings.codexAutoRefresh)
                    Spacer(minLength: 0)
                }

                if !settings.codexManagedAccounts.isEmpty {
                    Divider()
                    Text("Torli Stats 管理的账号")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach($settings.codexManagedAccounts) { $account in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                TextField("显示名称", text: $account.displayName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 260)
                                Spacer(minLength: 0)
                                Toggle("面板", isOn: $account.isDashboardVisible)
                                    .toggleStyle(.checkbox)
                                Toggle("状态栏", isOn: $account.isStatusBarIncluded)
                                    .toggleStyle(.checkbox)
                                Button("移除", role: .destructive) {
                                    settings.removeCodexManagedAccount(id: account.id)
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
                                    Button("测试连接") {
                                        testCodexConnection(for: account)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(testingCodexAccountIDs.contains(account.id))
                                    Button("登录 / 重新登录") {
                                        let didStart = settings.startCodexLogin(for: account)
                                        codexAccountMessage = didStart
                                            ? "已在终端打开 \(account.displayName) 的 Codex 登录。完成后点击“刷新全部”验证。"
                                            : "无法启动 Codex 登录。请确认 Codex CLI 已安装。"
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
                    }
                }

                HStack(spacing: 8) {
                    Button("添加账号") {
                        newCodexAccountName = ""
                        isAddingCodexAccount = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("刷新全部") {
                        onCodexRefresh()
                    }
                    .buttonStyle(.bordered)
                }

                Text(codexAccountMessage ?? "显示名称会用于 Dashboard、状态栏和提示信息；新增账号保存在 ~/.torli-stats-codex/<账号目录>，移除只删除本应用配置，不删除本地登录态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var addCodexAccountSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加 Codex 账号")
                .font(.headline)
            Text("账号将使用独立目录 ~/.torli-stats-codex/<名称>，并在终端完成一次 Codex 登录。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("账号名称，例如：个人账号", text: $newCodexAccountName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") {
                    isAddingCodexAccount = false
                }
                Button("创建并登录") {
                    guard let account = settings.addCodexManagedAccount(named: newCodexAccountName) else {
                        codexAccountMessage = "无法创建 ~/.torli-stats-codex 账号目录。"
                        isAddingCodexAccount = false
                        return
                    }
                    let didStart = settings.startCodexLogin(for: account)
                    codexAccountMessage = didStart
                        ? "已创建 \(account.displayName)，并在终端打开 Codex 登录。"
                        : "已创建 \(account.displayName)，但未找到 Codex CLI。"
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
            codexAccountMessage = "\(account.resolvedDisplayName)：\(validation.summary)。"
            return
        }

        testingCodexAccountIDs.insert(account.id)
        codexAccountMessage = "正在测试 \(account.resolvedDisplayName) 的 Codex 连接…"
        codexUsageStore.testConnection(for: account) { result in
            DispatchQueue.main.async {
                testingCodexAccountIDs.remove(account.id)
                switch result {
                case .success:
                    codexAccountMessage = "\(account.resolvedDisplayName)：连接正常，已成功读取使用情况。"
                case let .failure(error):
                    codexAccountMessage = "\(account.resolvedDisplayName)：连接失败，\(error.localizedDescription)。"
                }
            }
        }
    }

    private func displayCodexHomePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "自动：CODEX_HOME / ~/.codex" }

        let home = NSHomeDirectory()
        if trimmed == home { return "~" }
        if trimmed.hasPrefix(home + "/") {
            return "~/" + String(trimmed.dropFirst(home.count + 1))
        }
        return trimmed
    }

    private func chooseCodexHome() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex Home"
        panel.message = "请选择包含 auth.json 的 Codex Home 目录。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.codexHomePath.isEmpty ? NSHomeDirectory() : settings.codexHomePath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.codexHomePath = url.path
        }
    }
}
