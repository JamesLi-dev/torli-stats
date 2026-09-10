import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var appearanceSection: some View {
        SettingsSection(title: StatsL10n.text("settings.appearance.title")) {
            HStack(spacing: 12) {
                SettingsFieldLabel(StatsL10n.text("settings.appearance.theme"))
                Picker("", selection: $settings.theme) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 330, alignment: .leading)
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SettingsFieldLabel(StatsL10n.text("settings.language.title"))
                Picker("", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.localizedName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 330, alignment: .leading)
                if languageRestartRequired {
                    Button(StatsL10n.text("settings.language.restart")) {
                        relaunchForLanguageChange()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
            }
            Text(StatsL10n.text("settings.language.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: settings.appLanguage) { _, language in
            languageRestartRequired = language != initialLanguage
        }
    }

    private func relaunchForLanguageChange() {
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", Bundle.main.bundleURL.path]
        do {
            try launcher.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSApp.terminate(nil)
            }
        } catch {
            // Keep the button available so the user can retry if macOS cannot
            // launch a replacement process.
        }
    }
}
