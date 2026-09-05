import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var systemSection: some View {
        SettingsSection(title: "系统") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("开机启动", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                    Spacer()
                    Button("恢复默认设置", role: .destructive) {
                        settings.resetToDefaults()
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle("启用输入统计", isOn: Binding(
                        get: { settings.typingStatsEnabled },
                        set: { enabled in
                            settings.typingStatsEnabled = enabled
                            if enabled {
                                onRequestTypingStatsPermission()
                            }
                        }
                    ))
                    Text(typingStats.permissionStatus.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text("仅在本机统计有效按键和输入速度；不记录输入内容、键码或应用信息。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if typingStats.permissionStatus == .needsPermission {
                        Button("打开输入监控设置") {
                            typingStats.openInputMonitoringSettings()
                        }
                        Button("重新检测") {
                            onRequestTypingStatsPermission()
                        }
                    }
                    Button("清除输入统计", role: .destructive) {
                        typingStats.clearHistory()
                    }
                    .disabled(typingStats.totalKeyCount == 0)
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle("自动检查更新", isOn: $settings.automaticUpdateChecks)
                    Spacer(minLength: 0)
                    Button("检查更新") {
                        onCheckForUpdates()
                    }
                    .disabled(updateChecker.status == .checking)
                }
                Text(updateChecker.status.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
