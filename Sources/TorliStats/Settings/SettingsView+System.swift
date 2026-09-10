import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var systemSection: some View {
        SettingsSection(title: StatsL10n.text("settings.category.system")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle(StatsL10n.text("settings.system.launch_at_login"), isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                    Spacer()
                    Button(StatsL10n.text("settings.system.restore_defaults"), role: .destructive) {
                        settings.resetToDefaults()
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle(StatsL10n.text("settings.system.enable_typing"), isOn: Binding(
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
                Text(StatsL10n.text("settings.system.typing_privacy"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if typingStats.permissionStatus == .needsPermission {
                        Button(StatsL10n.text("settings.system.open_input_monitoring")) {
                            typingStats.openInputMonitoringSettings()
                        }
                        Button(StatsL10n.text("settings.system.recheck")) {
                            onRequestTypingStatsPermission()
                        }
                    }
                    Button(StatsL10n.text("settings.system.clear_typing"), role: .destructive) {
                        typingStats.clearHistory()
                    }
                    .disabled(typingStats.totalKeyCount == 0)
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle(StatsL10n.text("settings.system.automatic_updates"), isOn: $settings.automaticUpdateChecks)
                    Spacer(minLength: 0)
                    Button(StatsL10n.text("settings.system.check_updates")) {
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
