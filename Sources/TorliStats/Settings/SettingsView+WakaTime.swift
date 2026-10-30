import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var wakaTimeSection: some View {
        SettingsSection(title: StatsL10n.text("settings.wakatime.title")) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsInlineHint(
                    text: StatsL10n.text("settings.wakatime.help"),
                    icon: "key.fill"
                )

                Link(StatsL10n.text("settings.wakatime.get_token"), destination: URL(string: "https://wakatime.com/oauth")!)
                if hasLegacyWakaTimeKey && !hasWakaTimeOAuthToken {
                    SettingsInlineHint(text: StatsL10n.text("settings.wakatime.migrate_key"), icon: "exclamationmark.triangle")
                }

                HStack(spacing: 8) {
                    SecureField(hasWakaTimeOAuthToken ? StatsL10n.text("settings.wakatime.token_saved") : StatsL10n.text("settings.wakatime.token"), text: $wakaTimeOAuthToken)
                        .textFieldStyle(.roundedBorder)
                    Button(StatsL10n.text("settings.wakatime.save_connect")) {
                        let key = wakaTimeOAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                            wakaTimeMessage = StatsL10n.text("settings.wakatime.enter_token")
                            return
                        }
                        guard WakaTimeKeychain.saveOAuthToken(key) else {
                            wakaTimeMessage = StatsL10n.text("settings.wakatime.save_failed")
                            return
                        }
                        wakaTimeOAuthToken = ""
                        hasWakaTimeOAuthToken = true
                        hasLegacyWakaTimeKey = false
                        wakaTimeMessage = nil
                        settings.showWakaTimeCard = true
                        settings.wakaTimeEnabled = true
                        onWakaTimeRefresh()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 10) {
                    Toggle(StatsL10n.text("settings.wakatime.enabled"), isOn: $settings.wakaTimeEnabled)
                        .disabled(!hasWakaTimeOAuthToken)
                    Spacer(minLength: 0)
                    Button(StatsL10n.text("wakatime.refresh")) {
                        onWakaTimeRefresh()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!settings.wakaTimeEnabled || !hasWakaTimeOAuthToken)
                }

                HStack(spacing: 8) {
                    SettingsStatusMessage(
                        text: wakaTimeMessage ?? wakaTimeUsageStore.state.statusText,
                        icon: "info.circle",
                        tint: DashboardPalette.diskProgress
                    )
                    if hasWakaTimeOAuthToken || hasLegacyWakaTimeKey {
                        Button(StatsL10n.text("settings.wakatime.remove_token"), role: .destructive) {
                            WakaTimeKeychain.deleteCredentials()
                            wakaTimeOAuthToken = ""
                            hasWakaTimeOAuthToken = false
                            hasLegacyWakaTimeKey = false
                            wakaTimeMessage = StatsL10n.text("settings.wakatime.removed_token")
                            settings.wakaTimeEnabled = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
        }
    }
}
