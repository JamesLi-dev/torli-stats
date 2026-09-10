import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var wakaTimeSection: some View {
        SettingsSection(title: StatsL10n.text("settings.wakatime.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(StatsL10n.text("settings.wakatime.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SecureField(hasWakaTimeAPIKey ? StatsL10n.text("settings.wakatime.api_key_saved") : StatsL10n.text("settings.wakatime.api_key"), text: $wakaTimeAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Button(StatsL10n.text("settings.wakatime.save_connect")) {
                        let key = wakaTimeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else {
                            wakaTimeMessage = StatsL10n.text("settings.wakatime.enter_api_key")
                            return
                        }
                        guard WakaTimeKeychain.saveAPIKey(key) else {
                            wakaTimeMessage = StatsL10n.text("settings.wakatime.save_failed")
                            return
                        }
                        wakaTimeAPIKey = ""
                        hasWakaTimeAPIKey = true
                        wakaTimeMessage = StatsL10n.text("settings.wakatime.saved_connecting")
                        settings.showWakaTimeCard = true
                        settings.wakaTimeEnabled = true
                        onWakaTimeRefresh()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 10) {
                    Toggle(StatsL10n.text("settings.wakatime.enabled"), isOn: $settings.wakaTimeEnabled)
                        .disabled(!hasWakaTimeAPIKey)
                    Spacer(minLength: 0)
                    Button(StatsL10n.text("wakatime.refresh")) {
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
                        Button(StatsL10n.text("settings.wakatime.remove_api_key"), role: .destructive) {
                            WakaTimeKeychain.deleteAPIKey()
                            wakaTimeAPIKey = ""
                            hasWakaTimeAPIKey = false
                            wakaTimeMessage = StatsL10n.text("settings.wakatime.removed_api_key")
                            settings.wakaTimeEnabled = false
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
