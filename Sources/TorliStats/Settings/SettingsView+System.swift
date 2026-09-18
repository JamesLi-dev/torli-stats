import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var systemSection: some View {
        SettingsSection(title: StatsL10n.text("settings.category.system")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(StatsL10n.text("settings.system.launch_at_login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))

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
                SettingsStatusMessage(
                    text: StatsL10n.text("settings.system.typing_privacy"),
                    icon: "hand.raised",
                    tint: .secondary
                )
                HStack(spacing: 8) {
                    if typingStats.permissionStatus == .needsPermission {
                        Button(StatsL10n.text("settings.system.open_input_monitoring")) {
                            typingStats.openInputMonitoringSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        Button(StatsL10n.text("settings.system.recheck")) {
                            onRequestTypingStatsPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(StatsL10n.text("settings.system.clear_typing"), role: .destructive) {
                        typingStats.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(typingStats.totalKeyCount == 0)
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle(StatsL10n.text("settings.system.automatic_updates"), isOn: $settings.automaticUpdateChecks)
                    Spacer(minLength: 0)
                    Button(StatsL10n.text("settings.system.check_updates")) {
                        onCheckForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(updateChecker.status == .checking)
                }
                SettingsStatusMessage(
                    text: updateChecker.status.description,
                    icon: "arrow.triangle.2.circlepath",
                    tint: .secondary
                )

                Divider()

                SettingsDestructiveActionRow(
                    title: StatsL10n.text("settings.system.restore_defaults"),
                    actionTitle: StatsL10n.text("settings.system.restore_defaults")
                ) {
                    settings.resetToDefaults()
                }
            }
        }
    }
}
