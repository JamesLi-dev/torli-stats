import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var monitoringSection: some View {
        SettingsSection(title: StatsL10n.text("settings.category.monitoring")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(StatsL10n.text("monitoring.plugged_in_interval"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(AppSettings.supportedRefreshIntervals, id: \.self) { interval in
                            Text(StatsL10n.format("monitoring.seconds", interval)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    Toggle(StatsL10n.text("monitoring.always_save_power"), isOn: $settings.powerSavingMode)
                }
                HStack(spacing: 10) {
                    Text(StatsL10n.text("monitoring.battery_interval"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.batteryRefreshInterval) {
                        ForEach(AppSettings.supportedRefreshIntervals, id: \.self) { interval in
                            Text(StatsL10n.format("monitoring.seconds", interval)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    Toggle(StatsL10n.text("monitoring.low_battery_saving"), isOn: $settings.lowBatterySavingEnabled)
                }
                if settings.lowBatterySavingEnabled {
                    HStack(spacing: 10) {
                        Text(StatsL10n.text("monitoring.low_battery_threshold"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Picker("", selection: $settings.lowBatteryThreshold) {
                            ForEach([10, 20, 30], id: \.self) { threshold in
                                Text("\(threshold)%").tag(threshold)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 80)
                        Text(StatsL10n.text("monitoring.low_battery_hint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle(StatsL10n.text("monitoring.adaptive_sampling"), isOn: $settings.adaptiveSamplingEnabled)
                if settings.adaptiveSamplingEnabled {
                    Text(StatsL10n.text("monitoring.adaptive_sampling_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Toggle(StatsL10n.text("monitoring.night_pause"), isOn: $settings.nightMonitoringPauseEnabled)
                if settings.nightMonitoringPauseEnabled {
                    HStack(spacing: 10) {
                        Text(StatsL10n.text("monitoring.pause_schedule"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        DatePicker(
                            StatsL10n.text("monitoring.start"),
                            selection: timeBinding(\.nightMonitoringPauseStartSeconds),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        DatePicker(
                            StatsL10n.text("monitoring.end"),
                            selection: timeBinding(\.nightMonitoringPauseEndSeconds),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Spacer()
                    }
                    Text(StatsL10n.text("monitoring.pause_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text(StatsL10n.text("monitoring.process_count"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.processLimit) {
                        Text(StatsL10n.format("monitoring.items", 3)).tag(3)
                        Text(StatsL10n.format("monitoring.items", 5)).tag(5)
                        Text(StatsL10n.format("monitoring.items", 8)).tag(8)
                        Text(StatsL10n.format("monitoring.items", 10)).tag(10)
                        Text(StatsL10n.format("monitoring.items", 15)).tag(15)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    Text(StatsL10n.text("monitoring.sort"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.processSort) {
                        ForEach(ProcessSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
        }
    }

    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let seconds = settings[keyPath: keyPath]
                let calendar = Calendar.autoupdatingCurrent
                let day = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .second, value: seconds, to: day) ?? Date()
            },
            set: { date in
                let calendar = Calendar.autoupdatingCurrent
                settings[keyPath: keyPath] = calendar.component(.hour, from: date) * 3_600
                    + calendar.component(.minute, from: date) * 60
            }
        )
    }
}
