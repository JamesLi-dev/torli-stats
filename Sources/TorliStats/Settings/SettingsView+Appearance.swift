import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var appearanceSection: some View {
        SettingsSection(title: "外观") {
            HStack(spacing: 12) {
                        SettingsFieldLabel("主题")
                        Picker("", selection: $settings.theme) {
                            ForEach(ThemePreference.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 240)
            }
        }
    }
}
