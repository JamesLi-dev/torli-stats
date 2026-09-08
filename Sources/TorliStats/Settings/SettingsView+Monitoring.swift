import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var monitoringSection: some View {
        SettingsSection(title: "监控") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("接电间隔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(AppSettings.supportedRefreshIntervals, id: \.self) { interval in
                            Text("\(interval) 秒").tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    Toggle("始终省电", isOn: $settings.powerSavingMode)
                }
                HStack(spacing: 10) {
                    Text("电池间隔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.batteryRefreshInterval) {
                        ForEach(AppSettings.supportedRefreshIntervals, id: \.self) { interval in
                            Text("\(interval) 秒").tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    Toggle("低电量自动省电", isOn: $settings.lowBatterySavingEnabled)
                }
                if settings.lowBatterySavingEnabled {
                    HStack(spacing: 10) {
                        Text("低电量阈值")
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
                        Text("低于阈值时最慢每 30 秒刷新一次")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle("夜间暂停监控", isOn: $settings.nightMonitoringPauseEnabled)
                if settings.nightMonitoringPauseEnabled {
                    HStack(spacing: 10) {
                        Text("暂停时段")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        DatePicker(
                            "开始",
                            selection: timeBinding(\.nightMonitoringPauseStartSeconds),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        DatePicker(
                            "结束",
                            selection: timeBinding(\.nightMonitoringPauseEndSeconds),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Spacer()
                    }
                    Text("暂停 CPU、网络、传感器、进程及自动 Codex/WakaTime 刷新；手动刷新仍可使用。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text("进程数量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.processLimit) {
                        Text("3 个").tag(3)
                        Text("5 个").tag(5)
                        Text("8 个").tag(8)
                        Text("10 个").tag(10)
                        Text("15 个").tag(15)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    Text("排序")
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
