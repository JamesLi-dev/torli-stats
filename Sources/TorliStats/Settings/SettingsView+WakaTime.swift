import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var wakaTimeSection: some View {
        SettingsSection(title: "WakaTime 开发统计") {
            VStack(alignment: .leading, spacing: 10) {
                Text("配置自己的 API Key 后才会请求 WakaTime；密钥仅保存在本机钥匙串，启用后每 30 分钟自动同步一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SecureField(hasWakaTimeAPIKey ? "已保存 API Key（可输入新值替换）" : "WakaTime API Key", text: $wakaTimeAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Button("保存并连接") {
                        let key = wakaTimeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else {
                            wakaTimeMessage = "请输入 WakaTime API Key。"
                            return
                        }
                        guard WakaTimeKeychain.saveAPIKey(key) else {
                            wakaTimeMessage = "无法保存 API Key 到钥匙串。"
                            return
                        }
                        wakaTimeAPIKey = ""
                        hasWakaTimeAPIKey = true
                        wakaTimeMessage = "已保存到钥匙串，正在连接。"
                        settings.showWakaTimeCard = true
                        settings.wakaTimeEnabled = true
                        onWakaTimeRefresh()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 10) {
                    Toggle("启用 WakaTime 统计", isOn: $settings.wakaTimeEnabled)
                        .disabled(!hasWakaTimeAPIKey)
                    Spacer(minLength: 0)
                    Button("刷新") {
                        onWakaTimeRefresh()
                    }
                    .disabled(!settings.wakaTimeEnabled)
                }

                HStack(spacing: 8) {
                    Text(wakaTimeMessage ?? wakaTimeUsageStore.state.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if hasWakaTimeAPIKey {
                        Button("移除 API Key", role: .destructive) {
                            WakaTimeKeychain.deleteAPIKey()
                            wakaTimeAPIKey = ""
                            hasWakaTimeAPIKey = false
                            wakaTimeMessage = "已从钥匙串移除 API Key。"
                            settings.wakaTimeEnabled = false
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
